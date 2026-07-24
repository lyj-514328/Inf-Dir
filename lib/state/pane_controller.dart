import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../services/directory_service.dart';

enum SortColumn { name, dateModified, type, size }

class TabInfo {
  String path;
  String label;
  TabInfo({required this.path, required this.label});
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
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;

  PaneController(String initialPath) : _currentPath = initialPath {
    _tabs.add(TabInfo(path: initialPath, label: _pathLabel(initialPath)));
    _loadEntries(initialPath);
  }

  String get currentPath => _currentPath;
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

  String _pathLabel(String path) {
    if (path.length <= 3) return path;
    return p.basename(path);
  }

  Future<void> _loadEntries(String path) async {
    _loading = true;
    notifyListeners();
    _entries = DirectoryService.listDirectory(path);
    _applySort();
    _loading = false;
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();
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

  void refresh() => _loadEntries(_currentPath);

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
