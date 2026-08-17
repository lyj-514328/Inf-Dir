import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../models/file_group.dart';
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

/// Quick filters exposed by the status-bar filter field. Filtering is local to
/// a pane and never changes the directory enumeration cache.
enum EntryFilter { all, folders, files, images, documents }

/// 过滤输入的模式：由用户显式选择（状态栏过滤框右侧菜单）。
/// - [keyword]：普通子串匹配（大小写由 [PaneController.caseSensitive] 决定）
/// - [glob]：`*` / `?` 通配，按整名匹配
/// - [regex]：正则部分匹配
enum QueryFilterMode { keyword, glob, regex }

/// 单个标签页，携带独立的前进/后退历史。
///
/// 契约：path/label 变化必须替换实例（标签栏 Selector 依赖 `==` 感知变化），
/// 而 [backStack]/[forwardStack] 列表按引用跨实例携带，纯栈变化不产生新实例、
/// 不触发 rebuild。`==`/hashCode 只比较 path+label。
class TabInfo {
  final String path;
  final String label;
  final List<String> backStack;
  final List<String> forwardStack;

  TabInfo({
    required this.path,
    required this.label,
    List<String>? backStack,
    List<String>? forwardStack,
  }) : backStack = backStack ?? <String>[],
       forwardStack = forwardStack ?? <String>[];

  @override
  bool operator ==(Object other) =>
      other is TabInfo && other.path == path && other.label == label;

  @override
  int get hashCode => Object.hash(path, label);
}

/// 标签页完整状态（路径 + 导航历史），用于「最近关闭」记录、跨 pane
/// 移动/复制与会话持久化。
class TabRecord {
  final String path;
  final int index;
  final List<String> backStack;
  final List<String> forwardStack;

  const TabRecord({
    required this.path,
    required this.index,
    required this.backStack,
    required this.forwardStack,
  });
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
  final void Function(TabRecord)? _onTabClosed;
  final String Function(String currentPath)? _newTabPathResolver;
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;
  FileGroupBy _groupBy = FileGroupBy.none;
  bool _groupAscending = true;
  String _filterQuery = '';
  EntryFilter _entryFilter = EntryFilter.all;
  QueryFilterMode _filterMode = QueryFilterMode.keyword;
  bool _caseSensitive = false;
  PaneViewMode _viewMode = PaneViewMode.details;
  bool _showDetailsPane = false;
  bool _showPreviewPane = false;
  List<double> _columnWidths = [300, 140, 100, 80]; // name, date, type, size

  PaneController(
    String initialPath, {
    DirectoryRepository? repository,
    Future<void> Function()? frameYield,
    void Function(TabRecord)? onTabClosed,
    PaneViewMode defaultViewMode = PaneViewMode.details,
    String Function(String currentPath)? newTabPathResolver,
  }) : _currentPath = initialPath,
       _repository = repository ?? DirectoryRepository(),
       _frameYield = frameYield ?? _defaultFrameYield,
       _onTabClosed = onTabClosed,
       _newTabPathResolver = newTabPathResolver {
    _tabs.add(TabInfo(path: initialPath, label: _pathLabel(initialPath)));
    if (FileService.isHomePath(initialPath)) {
      _viewMode = PaneViewMode.content;
    } else {
      _viewMode = defaultViewMode;
    }
    _startListing(initialPath);
  }

  PaneController.fromSnapshot(
    PaneLayoutSnapshot snapshot, {
    DirectoryRepository? repository,
    Future<void> Function()? frameYield,
    void Function(TabRecord)? onTabClosed,
    String Function(String currentPath)? newTabPathResolver,
  }) : _currentPath = snapshot.currentPath,
       _repository = repository ?? DirectoryRepository(),
       _frameYield = frameYield ?? _defaultFrameYield,
       _onTabClosed = onTabClosed,
       _newTabPathResolver = newTabPathResolver {
    _tabs.addAll(
      snapshot.tabs.map(
        (tab) => TabInfo(
          path: tab.path,
          label: _pathLabel(tab.path),
          backStack: List.of(tab.backStack),
          forwardStack: List.of(tab.forwardStack),
        ),
      ),
    );
    _activeTabIndex = snapshot.activeTabIndex;
    _backStack.addAll(_tabs[_activeTabIndex].backStack);
    _forwardStack.addAll(_tabs[_activeTabIndex].forwardStack);
    _sortColumn = SortColumn.values.byName(snapshot.sortColumn);
    _sortAscending = snapshot.sortAscending;
    _groupBy = FileGroupBy.values.byName(snapshot.groupBy);
    _groupAscending = snapshot.groupAscending;
    _filterQuery = snapshot.filterQuery;
    _entryFilter = EntryFilter.values.byName(snapshot.entryFilter);
    _filterMode = QueryFilterMode.values.byName(snapshot.filterMode);
    _caseSensitive = snapshot.caseSensitive;
    _viewMode = PaneViewMode.values.byName(snapshot.viewMode);
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
  List<FileEntry> get visibleEntries {
    final nameMatch = _compileNameMatcher();
    final visible = _entries
        .where(
          (e) =>
              (nameMatch == null || nameMatch(e.name)) &&
              _matchesEntryFilter(e),
        )
        .toList(growable: false);
    if (_groupBy == FileGroupBy.none) return visible;
    return groupFileEntries(
      visible,
      _groupBy,
      ascending: _groupAscending,
    ).expand((group) => group.entries).toList(growable: false);
  }

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
  FileGroupBy get groupBy => _groupBy;
  bool get groupAscending => _groupAscending;
  String get filterQuery => _filterQuery;
  EntryFilter get entryFilter => _entryFilter;
  PaneViewMode get viewMode => _viewMode;
  bool get showDetailsPane => _showDetailsPane;
  bool get showPreviewPane => _showPreviewPane;
  List<double> get columnWidths => _columnWidths;

  PaneLayoutSnapshot toLayoutSnapshot() {
    _flushActiveTab();
    return PaneLayoutSnapshot(
      currentPath: _currentPath,
      tabs: [
        for (final tab in _tabs)
          TabSnapshot(
            path: tab.path,
            backStack: List.unmodifiable(tab.backStack),
            forwardStack: List.unmodifiable(tab.forwardStack),
          ),
      ],
      activeTabIndex: _activeTabIndex,
      backStack: List.unmodifiable(_backStack),
      forwardStack: List.unmodifiable(_forwardStack),
      sortColumn: _sortColumn.name,
      sortAscending: _sortAscending,
      groupBy: _groupBy.name,
      groupAscending: _groupAscending,
      filterQuery: _filterQuery,
      entryFilter: _entryFilter.name,
      filterMode: _filterMode.name,
      caseSensitive: _caseSensitive,
      viewMode: _viewMode.name,
      showDetailsPane: _showDetailsPane,
      showPreviewPane: _showPreviewPane,
      columnWidths: List.unmodifiable(_columnWidths),
    );
  }

  bool _matchesEntryFilter(FileEntry entry) {
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

  /// 当前显式选择的过滤模式（状态栏过滤框右侧菜单）。
  QueryFilterMode get filterMode => _filterMode;

  /// 关键字/glob/正则匹配是否区分大小写。
  bool get caseSensitive => _caseSensitive;

  /// 切换过滤模式（可选同时设置大小写敏感）。
  void setFilterMode(QueryFilterMode mode, {bool? caseSensitive}) {
    final nextCase = caseSensitive ?? _caseSensitive;
    if (_filterMode == mode && _caseSensitive == nextCase) return;
    _filterMode = mode;
    _caseSensitive = nextCase;
    _clearSelectionWithoutNotify();
    notifyListeners();
  }

  /// 把过滤输入编译成名称匹配器（每次求值时只编译一次），null 表示无过滤。
  bool Function(String)? _compileNameMatcher() {
    final query = _filterQuery.trim();
    if (query.isEmpty) return null;
    switch (_filterMode) {
      case QueryFilterMode.regex:
        try {
          final re = RegExp(query, caseSensitive: _caseSensitive);
          return re.hasMatch;
        } on FormatException {
          // 无效正则退化为关键字匹配，避免整列误伤消失。
          return (name) => _nameContains(name, query);
        }
      case QueryFilterMode.glob:
        return _globToRegExp(query, caseSensitive: _caseSensitive).hasMatch;
      case QueryFilterMode.keyword:
        return (name) => _nameContains(name, query);
    }
  }

  bool _nameContains(String name, String query) {
    if (_caseSensitive) return name.contains(query);
    return name.toLowerCase().contains(query.toLowerCase());
  }

  /// glob → 锚定整名的正则。
  static RegExp _globToRegExp(String glob, {bool caseSensitive = false}) {
    final escaped = glob.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'),
      (m) => '\\${m[0]}',
    );
    final pattern = escaped.replaceAll('*', '.*').replaceAll('?', '.');
    return RegExp('^$pattern\$', caseSensitive: caseSensitive);
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
      final tab = _tabs[_activeTabIndex];
      if (tab.path == path) return;
      _tabs[_activeTabIndex] = TabInfo(
        path: path,
        label: _pathLabel(path),
        backStack: tab.backStack,
        forwardStack: tab.forwardStack,
      );
    }
  }

  /// 把工作态（路径 + 双栈）写回活动标签。切换/关闭/序列化/移交标签前
  /// 必须调用，所有出口集中在此避免历史串档。
  void _flushActiveTab() {
    if (_activeTabIndex >= _tabs.length) return;
    final tab = _tabs[_activeTabIndex];
    tab.backStack
      ..clear()
      ..addAll(_backStack);
    tab.forwardStack
      ..clear()
      ..addAll(_forwardStack);
    if (tab.path != _currentPath) {
      _tabs[_activeTabIndex] = TabInfo(
        path: _currentPath,
        label: _pathLabel(_currentPath),
        backStack: tab.backStack,
        forwardStack: tab.forwardStack,
      );
    }
  }

  /// 把指定标签的状态载入工作态（切换/恢复后调用）。
  void _loadTabState(int index) {
    final tab = _tabs[index];
    _currentPath = tab.path;
    _backStack
      ..clear()
      ..addAll(tab.backStack);
    _forwardStack
      ..clear()
      ..addAll(tab.forwardStack);
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
    final cursor = await _repository.openCursor(path);
    sessionSw.stop();

    // 等 cursor 期间可能已有新 request：只关闭自己拿到的 cursor（§11）。
    if (revision != _revision) {
      cursor?.close();
      return;
    }

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
    final firstPage = await cursor.nextPage(count: 100);
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
      final page = await cursor.nextPage(count: pageSize);
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

  /// Applies known filesystem changes to the visible list without restarting
  /// directory enumeration. Used after a successful local paste operation.
  void applyLocalChanges({
    Iterable<String> addedPaths = const [],
    Iterable<String> removedPaths = const [],
  }) {
    final removed = removedPaths.toSet();
    final added = <FileEntry>[];

    for (final path in addedPaths) {
      if (p.dirname(path) != _currentPath ||
          _entries.any((entry) => entry.path == path)) {
        continue;
      }
      final entry = FileService.inspectEntry(path);
      if (entry != null) added.add(entry);
    }

    final next = _entries
        .where((entry) => !removed.contains(entry.path))
        .toList();
    final existing = next.map((entry) => entry.path).toSet();
    next.addAll(added.where((entry) => existing.add(entry.path)));
    _entries = _sortedEntries(next);

    _selectedPaths.removeAll(removed);
    if (_focusedPath != null && removed.contains(_focusedPath)) {
      _focusedPath = null;
    }
    if (_anchorPath != null && removed.contains(_anchorPath)) {
      _anchorPath = null;
    }
    notifyListeners();
  }

  void addTab([String? path]) {
    _flushActiveTab();
    final tabPath =
        path ?? _newTabPathResolver?.call(_currentPath) ?? _currentPath;
    _tabs.add(TabInfo(path: tabPath, label: _pathLabel(tabPath)));
    _activeTabIndex = _tabs.length - 1;
    _backStack.clear();
    _forwardStack.clear();
    if (tabPath != _currentPath) {
      _currentPath = tabPath;
      _loadEntries(tabPath);
    } else {
      notifyListeners();
    }
  }

  void switchTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeTabIndex) return;
    _flushActiveTab();
    _activeTabIndex = index;
    _loadTabState(index);
    _loadEntries(_currentPath);
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length || _tabs.length <= 1) return;
    _flushActiveTab();
    final removed = _tabs.removeAt(index);
    _reportClosed(removed, index);
    if (_activeTabIndex > index) {
      _activeTabIndex--;
      notifyListeners();
    } else if (_activeTabIndex == index) {
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _loadTabState(_activeTabIndex);
      _loadEntries(_currentPath);
    } else {
      notifyListeners();
    }
  }

  /// 拖动排序：把 [from] 处标签移到原列表的 [insertIndex] 插入位。
  void moveTab(int from, int insertIndex) {
    if (from < 0 || from >= _tabs.length) return;
    final target = insertIndex.clamp(0, _tabs.length);
    if (target == from || target == from + 1) return;
    _flushActiveTab();
    final tab = _tabs.removeAt(from);
    final destination = target > from ? target - 1 : target;
    _tabs.insert(destination, tab);
    if (_activeTabIndex == from) {
      _activeTabIndex = destination;
    } else {
      var active = _activeTabIndex;
      if (from < active) active--;
      if (destination <= active) active++;
      _activeTabIndex = active;
    }
    notifyListeners();
  }

  /// 复制标签（含历史），插入源标签之后并激活。
  void duplicateTab([int? index]) {
    final source = index ?? _activeTabIndex;
    if (source < 0 || source >= _tabs.length) return;
    _flushActiveTab();
    final tab = _tabs[source];
    final clone = TabInfo(
      path: tab.path,
      label: tab.label,
      backStack: List.of(tab.backStack),
      forwardStack: List.of(tab.forwardStack),
    );
    _tabs.insert(source + 1, clone);
    if (_activeTabIndex > source) _activeTabIndex++;
    switchTab(source + 1);
  }

  /// 插入携带历史的标签（恢复最近关闭 / 跨 pane 移入）并激活。
  void insertTab(int index, TabRecord record) {
    _flushActiveTab();
    final at = index.clamp(0, _tabs.length);
    _tabs.insert(
      at,
      TabInfo(
        path: record.path,
        label: _pathLabel(record.path),
        backStack: List.of(record.backStack),
        forwardStack: List.of(record.forwardStack),
      ),
    );
    if (_activeTabIndex >= at) _activeTabIndex++;
    switchTab(at);
  }

  /// 取出标签供跨 pane 移动。pane 至少保留一个标签，否则返回 null。
  TabRecord? takeTab(int index) {
    if (index < 0 || index >= _tabs.length || _tabs.length <= 1) return null;
    _flushActiveTab();
    final removed = _tabs.removeAt(index);
    final record = TabRecord(
      path: removed.path,
      index: index,
      backStack: removed.backStack,
      forwardStack: removed.forwardStack,
    );
    if (_activeTabIndex > index) {
      _activeTabIndex--;
      notifyListeners();
    } else if (_activeTabIndex == index) {
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _loadTabState(_activeTabIndex);
      _loadEntries(_currentPath);
    } else {
      notifyListeners();
    }
    return record;
  }

  /// Ctrl+Tab 环绕切换。
  void cycleTab(int delta) {
    if (_tabs.length < 2 || delta == 0) return;
    switchTab((_activeTabIndex + delta) % _tabs.length);
  }

  void closeOtherTabs(int index) {
    _closeIndexes([
      for (var i = 0; i < _tabs.length; i++)
        if (i != index) i,
    ]);
  }

  void closeTabsToTheLeft(int index) {
    _closeIndexes([for (var i = 0; i < index; i++) i]);
  }

  void closeTabsToTheRight(int index) {
    _closeIndexes([for (var i = index + 1; i < _tabs.length; i++) i]);
  }

  /// 导出全部标签状态（关闭 pane 前由 LayoutState 收集入最近关闭栈）。
  List<TabRecord> collectClosedRecords() {
    _flushActiveTab();
    return [
      for (var i = 0; i < _tabs.length; i++)
        TabRecord(
          path: _tabs[i].path,
          index: i,
          backStack: List.unmodifiable(_tabs[i].backStack),
          forwardStack: List.unmodifiable(_tabs[i].forwardStack),
        ),
    ];
  }

  void _closeIndexes(List<int> indexes) {
    final targets = indexes.where((i) => i >= 0 && i < _tabs.length).toSet();
    if (targets.isEmpty || targets.length >= _tabs.length) return;
    _flushActiveTab();
    final closingActive = targets.contains(_activeTabIndex);
    final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
    for (final index in ordered) {
      final removed = _tabs.removeAt(index);
      _reportClosed(removed, index);
      if (_activeTabIndex > index) _activeTabIndex--;
    }
    if (closingActive) {
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _loadTabState(_activeTabIndex);
      _loadEntries(_currentPath);
    } else {
      notifyListeners();
    }
  }

  void _reportClosed(TabInfo tab, int index) {
    _onTabClosed?.call(
      TabRecord(
        path: tab.path,
        index: index,
        backStack: List.unmodifiable(tab.backStack),
        forwardStack: List.unmodifiable(tab.forwardStack),
      ),
    );
  }

  void selectSingle(String path) {
    _selectedPaths.clear();
    _selectedPaths.add(path);
    _anchorPath = path;
    _focusedPath = path;
    notifyListeners();
  }

  /// 主文件夹选中项镜像（HomeView 持有本地选中态，这里同步路径供
  /// F3 快速查看等全局命令读取）。不触发通知，避免每次点击重读列表。
  void setHomeSelection(String? path) {
    _focusedPath = path;
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

  void invertSelection() {
    final visible = visibleEntries;
    for (final entry in visible) {
      if (!_selectedPaths.remove(entry.path)) {
        _selectedPaths.add(entry.path);
      }
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

  void setGroupBy(FileGroupBy groupBy) {
    if (_groupBy == groupBy) return;
    _groupBy = groupBy;
    notifyListeners();
  }

  void setGroupAscending(bool ascending) {
    if (_groupAscending == ascending) return;
    _groupAscending = ascending;
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
