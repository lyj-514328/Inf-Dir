import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../services/directory_service.dart';
import '../services/directory_repository.dart';

enum SortColumn { name, dateModified, type, size }

class TabInfo {
  String path;
  String label;
  TabInfo({required this.path, required this.label});
}

/// 每次导航独立的列表请求（§11）。
class _ListingRequest {
  final int revision;
  final String path;
  final DirectoryCursor? cursor;

  _ListingRequest(this.revision, this.path, this.cursor);
}

class PaneController extends ChangeNotifier {
  String _currentPath;
  List<FileEntry> _entries = [];
  final List<String> _backStack = [];
  final List<String> _forwardStack = [];
  final List<TabInfo> _tabs = [];
  int _activeTabIndex = 0;
  final Set<String> _selectedPaths = {};
  String? _anchorPath;
  bool _loading = false;
  int _revision = 0;
  _ListingRequest? _activeRequest;
  final DirectoryRepository _repository;
  final Future<void> Function() _frameYield;
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;
  List<double> _columnWidths = [300, 140, 100, 80]; // name, date, type, size

  PaneController(
    String initialPath, {
    DirectoryRepository? repository,
    Future<void> Function()? frameYield,
  })  : _currentPath = initialPath,
        _repository = repository ?? DirectoryRepository(),
        _frameYield = frameYield ?? _defaultFrameYield {
    _tabs.add(TabInfo(path: initialPath, label: _pathLabel(initialPath)));
    _startListing(initialPath);
  }

  static Future<void> _defaultFrameYield() {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
    return c.future;
  }

  String get currentPath => _currentPath;

  /// Friendly display path for the address bar (shell CLSIDs -> names).
  String get displayPath {
    if (_currentPath.startsWith('::') || _currentPath.startsWith('shell:')) {
      return DirectoryService.getDisplayName(_currentPath);
    }
    return _currentPath;
  }
  List<FileEntry> get entries => _entries;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;
  bool get canGoUp {
    final parent = p.dirname(_currentPath);
    return parent != _currentPath;
  }

  bool get isLoading => _loading;
  List<TabInfo> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  Set<String> get selectedPaths => _selectedPaths;
  int get entryCount => _entries.length;
  int get selectedCount => _selectedPaths.length;
  SortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  List<double> get columnWidths => _columnWidths;

  void resizeColumn(int colIndex, double deltaPx) {
    final left = _columnWidths[colIndex] + deltaPx;
    if (left >= 40) {
      _columnWidths[colIndex] = left;
      notifyListeners();
    }
  }

  void initColumnWidths(double paneWidth) {
    const overhead = 4 * 4 + 8 + 20.0;
    final avail = (paneWidth - overhead).clamp(160, double.infinity);
    const totalRatio = 4 + 2 + 2 + 1;
    _columnWidths = [
      (avail * 4 / totalRatio).roundToDouble(),
      (avail * 2 / totalRatio).roundToDouble(),
      (avail * 2 / totalRatio).roundToDouble(),
      (avail * 1 / totalRatio).roundToDouble(),
    ];
    notifyListeners();
  }

  String _pathLabel(String path) {
    if (path.startsWith('::') || path.startsWith('shell:')) {
      return DirectoryService.getDisplayName(path);
    }
    if (path.length <= 3) return path;
    return p.basename(path);
  }

  void _cancelActiveRequest() {
    final old = _activeRequest;
    _activeRequest = null;
    // 只关闭自己 request 拥有的 cursor（§5）。
    old?.cursor?.close();
  }

  /// 只有当前 request 允许提交：revision 与 path 都必须匹配（§11）。
  bool _isCurrent(_ListingRequest request) =>
      identical(_activeRequest, request) &&
      request.revision == _revision &&
      request.path == _currentPath;

  Future<void> _loadEntries(String path) => _startListing(path);

  Future<void> _startListing(String path) async {
    final revision = ++_revision;
    _cancelActiveRequest();

    _loading = true;
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();

    final totalSw = Stopwatch()..start();

    final sessionSw = Stopwatch()..start();
    final cursor = _repository.openCursor(path);
    sessionSw.stop();

    final request = _ListingRequest(revision, path, cursor);
    _activeRequest = request;

    if (cursor == null) {
      if (_isCurrent(request)) {
        _entries = [];
        _loading = false;
        notifyListeners();
        _activeRequest = null;
      }
      debugPrint(
          '[Perf] Paged -- failed to start session (${sessionSw.elapsedMilliseconds}ms)');
      return;
    }

    // 第一页
    final firstSw = Stopwatch()..start();
    final firstPage = cursor.nextPage(count: 100);
    firstSw.stop();

    if (!_isCurrent(request)) {
      // 旧 request 晚返回：只关闭自己的 cursor，不动当前状态（§11）。
      cursor.close();
      return;
    }

    if (firstPage == null) {
      _entries = [];
      _loading = false;
      cursor.close();
      _activeRequest = null;
      notifyListeners();
      return;
    }

    _entries = firstPage;
    _loading = false;
    notifyListeners();

    final buildSw = Stopwatch()..start();
    await _frameYield();
    buildSw.stop();

    debugPrint(
      '[Perf] Paged page#1 -- '
      'Session: ${sessionSw.elapsedMilliseconds}ms, '
      'Load: ${firstSw.elapsedMilliseconds}ms, '
      'Build: ${(buildSw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms, '
      'Items: ${firstPage.length}',
    );

    int pages = 1;
    const pageSize = 100;

    // 剩余分页：只使用本 request 的 cursor，每个异步边界后重新校验。
    while (_isCurrent(request)) {
      await _frameYield();
      if (!_isCurrent(request)) break;

      final sw = Stopwatch()..start();
      final page = cursor.nextPage(count: pageSize);
      sw.stop();

      // 页允许返回，但结果不能提交给已易主的 UI（§2.3）。
      if (!_isCurrent(request)) break;
      if (page == null) break;

      _entries = [..._entries, ...page];
      notifyListeners();
      pages++;
    }

    cursor.close();

    if (_isCurrent(request)) {
      _activeRequest = null;
      _applySort();
      notifyListeners();

      totalSw.stop();
      debugPrint(
        '[Perf] Paged done -- '
        '$pages pages, '
        '${_entries.length} total items, '
        'Total: ${totalSw.elapsedMilliseconds}ms',
      );
    }
  }

  @override
  void dispose() {
    _revision++;
    _cancelActiveRequest();
    super.dispose();
  }

  void sortBy(SortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    _applySort();
    notifyListeners();
  }

  void _applySort() {
    _entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      int cmp;
      switch (_sortColumn) {
        case SortColumn.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortColumn.dateModified:
          cmp = a.modified.compareTo(b.modified);
        case SortColumn.type:
          cmp = a.type.toLowerCase().compareTo(b.type.toLowerCase());
        case SortColumn.size:
          cmp = a.size.compareTo(b.size);
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  Future<void> navigateTo(String path, {bool addToHistory = true}) async {
    if (addToHistory && _currentPath != path) {
      _backStack.add(_currentPath);
      _forwardStack.clear();
    }
    _currentPath = path;
    if (_activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].path = path;
      _tabs[_activeTabIndex].label = _pathLabel(path);
    }
    await _loadEntries(path);
  }

  void goBack() {
    if (_backStack.isEmpty) return;
    _forwardStack.add(_currentPath);
    final prev = _backStack.removeLast();
    _currentPath = prev;
    if (_activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].path = prev;
      _tabs[_activeTabIndex].label = _pathLabel(prev);
    }
    _loadEntries(prev);
  }

  void goForward() {
    if (_forwardStack.isEmpty) return;
    _backStack.add(_currentPath);
    final next = _forwardStack.removeLast();
    _currentPath = next;
    if (_activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].path = next;
      _tabs[_activeTabIndex].label = _pathLabel(next);
    }
    _loadEntries(next);
  }

  void goUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) navigateTo(parent);
  }

  void goHome() => navigateTo(FileService.homeDirectory);

  void refresh() {
    _repository.invalidate(_currentPath);
    _startListing(_currentPath);
  }

  void addTab([String? path]) {
    final tabPath = path ?? _currentPath;
    _tabs.add(TabInfo(path: tabPath, label: _pathLabel(tabPath)));
    _activeTabIndex = _tabs.length - 1;
    if (tabPath != _currentPath) {
      _currentPath = tabPath;
      _loadEntries(tabPath);
    } else {
      notifyListeners();
    }
  }

  void switchTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeTabIndex) return;
    _activeTabIndex = index;
    final tabPath = _tabs[index].path;
    _currentPath = tabPath;
    _backStack.clear();
    _forwardStack.clear();
    _loadEntries(tabPath);
  }

  void closeTab(int index) {
    if (_tabs.length <= 1) return;
    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (_activeTabIndex > index) {
      _activeTabIndex--;
    }
    final tabPath = _tabs[_activeTabIndex].path;
    _currentPath = tabPath;
    _loadEntries(tabPath);
  }

  void selectSingle(String path) {
    _selectedPaths.clear();
    _selectedPaths.add(path);
    _anchorPath = path;
    notifyListeners();
  }

  void toggleSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }
    _anchorPath = path;
    notifyListeners();
  }

  void selectRange(String path) {
    _anchorPath ??= path;

    int anchorIndex = -1;
    int clickIndex = -1;
    for (int i = 0; i < _entries.length; i++) {
      if (_entries[i].path == _anchorPath) anchorIndex = i;
      if (_entries[i].path == path) clickIndex = i;
    }
    if (anchorIndex < 0 || clickIndex < 0) {
      selectSingle(path);
      return;
    }

    final start = anchorIndex < clickIndex ? anchorIndex : clickIndex;
    final end = anchorIndex < clickIndex ? clickIndex : anchorIndex;

    _selectedPaths.clear();
    for (int i = start; i <= end; i++) {
      _selectedPaths.add(_entries[i].path);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths.clear();
    for (final e in _entries) {
      _selectedPaths.add(e.path);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedPaths.isNotEmpty) {
      _selectedPaths.clear();
      _anchorPath = null;
      notifyListeners();
    }
  }
}
