import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../services/directory_service.dart';
import '../services/directory_repository.dart';
import '../models/window_layout_snapshot.dart';

enum SortColumn { name, dateModified, type, size }

/// Explorer-style view modes. `compact` is retained for older layout caches
/// and behaves like the small-icon view.
enum PaneViewMode {
  details,
  list,
  compact,
  extraLargeIcons,
  largeIcons,
  mediumIcons,
  smallIcons,
  tiles,
  content,
}

/// Quick filters exposed by the command bar. Filtering is local to a pane and
/// never changes the directory enumeration cache.
enum EntryFilter { all, folders, files, images, documents }

class TabInfo {
  final String path;
  final String label;
  const TabInfo({required this.path, required this.label});

  @override
  bool operator ==(Object other) =>
      other is TabInfo && other.path == path && other.label == label;

  @override
  int get hashCode => Object.hash(path, label);
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
  String? _focusedPath;
  bool _loading = false;
  int _revision = 0;
  _ListingRequest? _activeRequest;
  final DirectoryRepository _repository;
  final Future<void> Function() _frameYield;
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;
  String _filterQuery = '';
  EntryFilter _entryFilter = EntryFilter.all;
  PaneViewMode _viewMode = PaneViewMode.details;
  bool _showDetailsPane = false;
  bool _showPreviewPane = false;
  List<double> _columnWidths = [300, 140, 100, 80]; // name, date, type, size

  PaneController(
    String initialPath, {
    DirectoryRepository? repository,
    Future<void> Function()? frameYield,
  }) : _currentPath = initialPath,
       _repository = repository ?? DirectoryRepository(),
       _frameYield = frameYield ?? _defaultFrameYield {
    _tabs.add(TabInfo(path: initialPath, label: _pathLabel(initialPath)));
    if (FileService.isHomePath(initialPath)) {
      _viewMode = PaneViewMode.content;
    }
    _startListing(initialPath);
  }

  PaneController.fromSnapshot(
    PaneLayoutSnapshot snapshot, {
    DirectoryRepository? repository,
    Future<void> Function()? frameYield,
  }) : _currentPath = snapshot.currentPath,
       _repository = repository ?? DirectoryRepository(),
       _frameYield = frameYield ?? _defaultFrameYield {
    _tabs.addAll(
      snapshot.tabs.map((path) => TabInfo(path: path, label: _pathLabel(path))),
    );
    _activeTabIndex = snapshot.activeTabIndex;
    _backStack.addAll(snapshot.backStack);
    _forwardStack.addAll(snapshot.forwardStack);
    _sortColumn = SortColumn.values.byName(snapshot.sortColumn);
    _sortAscending = snapshot.sortAscending;
    _filterQuery = snapshot.filterQuery;
    _entryFilter = EntryFilter.values.byName(snapshot.entryFilter);
    _viewMode = PaneViewMode.values.byName(snapshot.viewMode);
    if (FileService.isHomePath(snapshot.currentPath) &&
        _viewMode != PaneViewMode.tiles &&
        _viewMode != PaneViewMode.content) {
      _viewMode = PaneViewMode.content;
    }
    _showDetailsPane = snapshot.showDetailsPane;
    _showPreviewPane = snapshot.showPreviewPane;
    _columnWidths = List<double>.of(snapshot.columnWidths);
    _startListing(_currentPath);
  }

  static Future<void> _defaultFrameYield() {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
    return c.future;
  }

  String get currentPath => _currentPath;
  bool get isHome => FileService.isHomePath(_currentPath);

  /// Friendly display path for the address bar (shell CLSIDs -> names).
  String get displayPath {
    if (FileService.isHomePath(_currentPath)) return '主文件夹';
    if (_currentPath.startsWith('::') || _currentPath.startsWith('shell:')) {
      return DirectoryService.getDisplayName(_currentPath);
    }
    return _currentPath;
  }

  List<FileEntry> get entries => _entries;
  List<FileEntry> get visibleEntries =>
      _entries.where(_matchesFilter).toList(growable: false);
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;
  bool get canGoUp {
    if (FileService.isHomePath(_currentPath)) return false;
    final parent = p.dirname(_currentPath);
    return parent != _currentPath;
  }

  bool get isLoading => _loading;
  List<TabInfo> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  Set<String> get selectedPaths => _selectedPaths;
  String? get focusedPath => _focusedPath;
  int get entryCount => visibleEntries.length;
  int get selectedCount => _selectedPaths.length;
  SortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  String get filterQuery => _filterQuery;
  EntryFilter get entryFilter => _entryFilter;
  PaneViewMode get viewMode => _viewMode;
  bool get showDetailsPane => _showDetailsPane;
  bool get showPreviewPane => _showPreviewPane;
  List<double> get columnWidths => _columnWidths;

  PaneLayoutSnapshot toLayoutSnapshot() => PaneLayoutSnapshot(
    currentPath: _currentPath,
    tabs: _tabs.map((tab) => tab.path).toList(growable: false),
    activeTabIndex: _activeTabIndex,
    backStack: List.unmodifiable(_backStack),
    forwardStack: List.unmodifiable(_forwardStack),
    sortColumn: _sortColumn.name,
    sortAscending: _sortAscending,
    filterQuery: _filterQuery,
    entryFilter: _entryFilter.name,
    viewMode: _viewMode.name,
    showDetailsPane: _showDetailsPane,
    showPreviewPane: _showPreviewPane,
    columnWidths: List.unmodifiable(_columnWidths),
  );

  bool _matchesFilter(FileEntry entry) {
    final query = _filterQuery.trim().toLowerCase();
    if (query.isNotEmpty && !entry.name.toLowerCase().contains(query)) {
      return false;
    }
    switch (_entryFilter) {
      case EntryFilter.all:
        return true;
      case EntryFilter.folders:
        return entry.isDirectory;
      case EntryFilter.files:
        return !entry.isDirectory;
      case EntryFilter.images:
        return !entry.isDirectory &&
            const {
              'jpg',
              'jpeg',
              'png',
              'gif',
              'bmp',
              'webp',
              'svg',
              'ico',
            }.contains(
              p.extension(entry.name).toLowerCase().replaceFirst('.', ''),
            );
      case EntryFilter.documents:
        return !entry.isDirectory &&
            const {
              'txt',
              'md',
              'pdf',
              'doc',
              'docx',
              'xls',
              'xlsx',
              'ppt',
              'pptx',
              'rtf',
            }.contains(
              p.extension(entry.name).toLowerCase().replaceFirst('.', ''),
            );
    }
  }

  void setFilterQuery(String query) {
    final normalized = query.trimLeft();
    if (_filterQuery == normalized) return;
    _filterQuery = normalized;
    _clearSelectionWithoutNotify();
    notifyListeners();
  }

  void setEntryFilter(EntryFilter filter) {
    if (_entryFilter == filter) return;
    _entryFilter = filter;
    _clearSelectionWithoutNotify();
    notifyListeners();
  }

  void setViewMode(PaneViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
  }

  void setDetailsPaneVisible(bool visible) {
    if (_showDetailsPane == visible) return;
    _showDetailsPane = visible;
    if (visible) _showPreviewPane = false;
    notifyListeners();
  }

  void setPreviewPaneVisible(bool visible) {
    if (_showPreviewPane == visible) return;
    _showPreviewPane = visible;
    if (visible) _showDetailsPane = false;
    notifyListeners();
  }

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
    if (FileService.isHomePath(path)) return '主文件夹';
    if (path.startsWith('::') || path.startsWith('shell:')) {
      return DirectoryService.getDisplayName(path);
    }
    if (path.length <= 3) return path;
    return p.basename(path);
  }

  void _updateActiveTabPath(String path) {
    if (_activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex] = TabInfo(path: path, label: _pathLabel(path));
    }
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
    _focusedPath = null;
    notifyListeners();

    if (FileService.isHomePath(path)) {
      _entries = [];
      _loading = false;
      notifyListeners();
      return;
    }

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
        '[Perf] Paged -- failed to start session (${sessionSw.elapsedMilliseconds}ms)',
      );
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

    _entries = _sortedEntries(firstPage);
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

      _entries = _mergeSortedEntries(_entries, page);
      notifyListeners();
      pages++;
    }

    cursor.close();

    if (_isCurrent(request)) {
      _activeRequest = null;

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
    _entries = _sortedEntries(_entries);
  }

  List<FileEntry> _sortedEntries(Iterable<FileEntry> entries) {
    final sorted = List<FileEntry>.of(entries);
    sorted.sort(_compareEntries);
    return sorted;
  }

  List<FileEntry> _mergeSortedEntries(
    List<FileEntry> current,
    List<FileEntry> incoming,
  ) {
    if (incoming.isEmpty) return current;
    if (current.isEmpty) return _sortedEntries(incoming);

    final sortedIncoming = _sortedEntries(incoming);
    final merged = <FileEntry>[];
    var currentIndex = 0;
    var incomingIndex = 0;

    while (currentIndex < current.length &&
        incomingIndex < sortedIncoming.length) {
      if (_compareEntries(
            current[currentIndex],
            sortedIncoming[incomingIndex],
          ) <=
          0) {
        merged.add(current[currentIndex++]);
      } else {
        merged.add(sortedIncoming[incomingIndex++]);
      }
    }

    if (currentIndex < current.length) {
      merged.addAll(current.getRange(currentIndex, current.length));
    }
    if (incomingIndex < sortedIncoming.length) {
      merged.addAll(
        sortedIncoming.getRange(incomingIndex, sortedIncoming.length),
      );
    }
    return merged;
  }

  int _compareEntries(FileEntry a, FileEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;

    final int comparison;
    switch (_sortColumn) {
      case SortColumn.name:
        comparison = a.compareNameTo(b);
      case SortColumn.dateModified:
        comparison = a.modified.compareTo(b.modified);
      case SortColumn.type:
        comparison = a.type.toLowerCase().compareTo(b.type.toLowerCase());
      case SortColumn.size:
        comparison = a.size.compareTo(b.size);
    }
    return _sortAscending ? comparison : -comparison;
  }

  Future<void> navigateTo(String path, {bool addToHistory = true}) async {
    if (addToHistory && _currentPath != path) {
      _backStack.add(_currentPath);
      _forwardStack.clear();
    }
    _currentPath = path;
    _updateActiveTabPath(path);
    await _loadEntries(path);
  }

  void goBack() {
    if (_backStack.isEmpty) return;
    _forwardStack.add(_currentPath);
    final prev = _backStack.removeLast();
    _currentPath = prev;
    _updateActiveTabPath(prev);
    _loadEntries(prev);
  }

  void goForward() {
    if (_forwardStack.isEmpty) return;
    _backStack.add(_currentPath);
    final next = _forwardStack.removeLast();
    _currentPath = next;
    _updateActiveTabPath(next);
    _loadEntries(next);
  }

  void goUp() {
    if (FileService.isHomePath(_currentPath)) return;
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) navigateTo(parent);
  }

  void goHome() {
    _viewMode = PaneViewMode.content;
    navigateTo(FileService.homeViewPath);
  }

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
    _focusedPath = path;
    notifyListeners();
  }

  void toggleSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }
    _anchorPath = path;
    _focusedPath = path;
    notifyListeners();
  }

  void selectRange(String path) {
    _focusedPath = path;
    _anchorPath ??= path;

    final visible = visibleEntries;

    int anchorIndex = -1;
    int clickIndex = -1;
    for (int i = 0; i < visible.length; i++) {
      if (visible[i].path == _anchorPath) anchorIndex = i;
      if (visible[i].path == path) clickIndex = i;
    }
    if (anchorIndex < 0 || clickIndex < 0) {
      selectSingle(path);
      return;
    }

    final start = anchorIndex < clickIndex ? anchorIndex : clickIndex;
    final end = anchorIndex < clickIndex ? clickIndex : anchorIndex;

    _selectedPaths.clear();
    for (int i = start; i <= end; i++) {
      _selectedPaths.add(visible[i].path);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths.clear();
    final visible = visibleEntries;
    for (final e in visible) {
      _selectedPaths.add(e.path);
    }
    _focusedPath ??= visible.isEmpty ? null : visible.first.path;
    notifyListeners();
  }

  void setSortColumn(SortColumn column) {
    if (_sortColumn == column) return;
    _sortColumn = column;
    _applySort();
    notifyListeners();
  }

  void setSortAscending(bool ascending) {
    if (_sortAscending == ascending) return;
    _sortAscending = ascending;
    _applySort();
    notifyListeners();
  }

  void _clearSelectionWithoutNotify() {
    _selectedPaths.clear();
    _anchorPath = null;
    _focusedPath = null;
  }

  void clearSelection() {
    if (_selectedPaths.isNotEmpty || _focusedPath != null) {
      _selectedPaths.clear();
      _anchorPath = null;
      _focusedPath = null;
      notifyListeners();
    }
  }
}
