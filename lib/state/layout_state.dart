import 'package:flutter/foundation.dart';
import '../models/file_group.dart';
import '../models/layout_node.dart';
import '../models/window_layout_snapshot.dart';
import 'pane_controller.dart';
import '../services/directory_repository.dart';
import '../services/file_service.dart';
import '../services/window_layout_store.dart';

class LayoutState extends ChangeNotifier {
  late final LayoutTree _tree;
  final Map<String, PaneController> _controllers = {};
  String _focusedNodeId = '';
  int _nextPaneCounter = 0;
  final DirectoryRepository _repository;
  final WindowLayoutStore? _layoutStore;
  bool _disposed = false;
  double _sidebarWidth = 220;

  /// 焦点 pane 的当前路径（§12）：焦点切换或焦点 pane 导航时更新。
  /// 用独立的 ValueNotifier，避免无关 notify 也触发侧栏同步。
  final ValueNotifier<String> activePanePath = ValueNotifier<String>('');

  LayoutState({DirectoryRepository? repository, WindowLayoutStore? layoutStore})
    : _repository = repository ?? DirectoryRepository(),
      _layoutStore = layoutStore {
    final cached = _layoutStore?.load();
    debugPrint(
      '[LayoutCache] load -> ${cached == null ? 'null' : '${cached.panes.length} panes, ${cached.workspaces.length} workspaces'}',
    );
    if (cached != null &&
        !_isLegacySinglePaneDefault(cached) &&
        _restoreSnapshot(cached)) {
      debugPrint('[LayoutCache] restored snapshot');
      _updateActivePanePath();
      return;
    }

    debugPrint('[LayoutCache] using default layout');
    _initializeDefault();
    _updateActivePanePath();
  }

  void _initializeDefault() {
    final initialPaths = [
      FileService.desktopPath,
      FileService.homeDirectory,
      FileService.documentsPath,
      FileService.downloadsPath,
    ];
    final paneIds = <String>[];
    for (final path in initialPaths) {
      final id = _nextPaneId();
      _addController(id, PaneController(path, repository: _repository));
      paneIds.add(id);
    }

    _tree = createDefaultLayout(paneIds);

    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) {
      _focusedNodeId = firstPane.id;
    }
  }

  // Do not let the single-pane default from b30ea08 mask the restored grid.
  bool _isLegacySinglePaneDefault(WindowLayoutSnapshot snapshot) {
    if (snapshot.workspaces.length != 1 ||
        snapshot.activeWorkspaceIndex != 0 ||
        snapshot.panes.length != 1) {
      return false;
    }

    final workspace = snapshot.workspaces.single;
    if (workspace.type != NodeType.workspace ||
        workspace.children.length != 1) {
      return false;
    }

    final paneNode = workspace.children.single;
    final paneId = paneNode.paneId;
    if (paneNode.type != NodeType.pane ||
        paneId == null ||
        snapshot.focusedNodeId != paneNode.id) {
      return false;
    }

    final pane = snapshot.panes[paneId];
    return pane != null &&
        pane.currentPath == FileService.homeViewPath &&
        pane.tabs.length == 1 &&
        pane.tabs.first == FileService.homeViewPath &&
        pane.activeTabIndex == 0 &&
        pane.backStack.isEmpty &&
        pane.forwardStack.isEmpty &&
        pane.sortColumn == SortColumn.name.name &&
        pane.sortAscending &&
        pane.groupBy == FileGroupBy.none.name &&
        pane.groupAscending &&
        pane.filterQuery.isEmpty &&
        pane.entryFilter == EntryFilter.all.name &&
        pane.viewMode == PaneViewMode.content.name &&
        !pane.showDetailsPane &&
        !pane.showPreviewPane &&
        pane.columnWidths.length == 4 &&
        pane.columnWidths[0] == 300 &&
        pane.columnWidths[1] == 140 &&
        pane.columnWidths[2] == 100 &&
        pane.columnWidths[3] == 80;
  }

  bool _restoreSnapshot(WindowLayoutSnapshot snapshot) {
    final restoredControllers = <String, PaneController>{};
    try {
      final roots = snapshot.workspaces
          .map((workspace) => _restoreNode(workspace))
          .toList(growable: false);
      final restoredTree = LayoutTree(
        workspaces: roots,
        activeWorkspaceIndex: snapshot.activeWorkspaceIndex,
        idCounter: snapshot.nodeIdCounter,
      );
      for (final entry in snapshot.panes.entries) {
        restoredControllers[entry.key] = PaneController.fromSnapshot(
          entry.value,
          repository: _repository,
        );
      }
      _tree = restoredTree;
      _nextPaneCounter = snapshot.nextPaneCounter;
      _sidebarWidth = snapshot.sidebarWidth;
      _focusedNodeId = snapshot.focusedNodeId;
      for (final entry in restoredControllers.entries) {
        _addController(entry.key, entry.value);
      }
      return true;
    } on Object {
      for (final controller in restoredControllers.values) {
        controller.dispose();
      }
      return false;
    }
  }

  LayoutNode _restoreNode(LayoutNodeSnapshot snapshot, [LayoutNode? parent]) {
    final node = LayoutNode(
      id: snapshot.id,
      type: snapshot.type,
      layout: snapshot.layout,
      percent: snapshot.percent,
      paneId: snapshot.paneId,
      label: snapshot.label,
      parent: parent,
    );
    for (final childSnapshot in snapshot.children) {
      node.children.add(_restoreNode(childSnapshot, node));
    }
    return node;
  }

  // ── Controller factory (bubbles pane changes up to LayoutState) ──
  void _addController(String id, PaneController ctrl) {
    ctrl.addListener(_onPaneChanged);
    _controllers[id] = ctrl;
  }

  void _removeController(String id) {
    final ctrl = _controllers.remove(id);
    if (ctrl != null) {
      ctrl.removeListener(_onPaneChanged);
      ctrl.dispose();
    }
  }

  void _onPaneChanged() {
    if (_disposed) return;
    _updateActivePanePath();
    notifyListeners();
  }

  void _saveLayoutNow() {
    if (_layoutStore == null || _disposed) return;
    debugPrint(
      '[LayoutCache] _saveLayoutNow (disposed=$_disposed, panes=${_controllers.length})',
    );
    try {
      _layoutStore.save(toLayoutSnapshot());
      debugPrint('[LayoutCache] save OK');
    } on Object catch (error) {
      debugPrint('[LayoutCache] save failed: $error');
    }
  }

  /// Writes the latest session snapshot during coordinated application exit.
  void saveSession() {
    debugPrint(
      '[LayoutCache] saveSession (disposed=$_disposed, store=$_layoutStore)',
    );
    _saveLayoutNow();
  }

  void _updateActivePanePath() {
    final node = _findNodeById(_focusedNodeId);
    final path = node != null ? (controllerFor(node)?.currentPath ?? '') : '';
    if (activePanePath.value != path) {
      activePanePath.value = path;
    }
  }

  @override
  void dispose() {
    debugPrint('[LayoutCache] LayoutState.dispose (disposed=$_disposed)');
    if (_disposed) return;
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.removeListener(_onPaneChanged);
      controller.dispose();
    }
    _controllers.clear();
    activePanePath.dispose();
    super.dispose();
  }

  // ============================================================
  // 只读属性
  // ============================================================
  LayoutTree get tree => _tree;
  String get focusedNodeId => _focusedNodeId;

  LayoutNode get focusedNode => _findNodeById(_focusedNodeId)!;
  List<LayoutNode> get workspaces => _tree.workspaces;
  LayoutNode get activeWorkspace => _tree.activeWorkspace;
  int get activeWorkspaceIndex => _tree.activeWorkspaceIndex;
  double get sidebarWidth => _sidebarWidth;

  void setSidebarWidth(double width) {
    final normalized = width.clamp(150, double.infinity).toDouble();
    if (_sidebarWidth == normalized) return;
    _sidebarWidth = normalized;
    notifyListeners();
  }

  WindowLayoutSnapshot toLayoutSnapshot() => WindowLayoutSnapshot(
    workspaces: _tree.workspaces.map(_snapshotNode).toList(growable: false),
    activeWorkspaceIndex: _tree.activeWorkspaceIndex,
    focusedNodeId: _focusedNodeId,
    nodeIdCounter: _tree.idCounter,
    nextPaneCounter: _nextPaneCounter,
    sidebarWidth: _sidebarWidth,
    panes: Map.unmodifiable({
      for (final entry in _controllers.entries)
        entry.key: entry.value.toLayoutSnapshot(),
    }),
  );

  LayoutNodeSnapshot _snapshotNode(LayoutNode node) => LayoutNodeSnapshot(
    id: node.id,
    type: node.type,
    layout: node.layout,
    percent: node.percent,
    paneId: node.paneId,
    label: node.label,
    children: node.children.map(_snapshotNode).toList(growable: false),
  );

  /// 获取所有 pane 节点
  List<LayoutNode> get allPaneNodes {
    final result = <LayoutNode>[];
    _collectPaneNodes(_tree.activeWorkspace, result);
    return result;
  }

  /// Reloads every live pane after a global directory-enumeration setting
  /// changes (for example, toggling hidden/system files).
  void refreshAllPanes() {
    for (final controller in _controllers.values) {
      controller.refresh();
    }
  }

  void refreshPanesWhere(bool Function(String path) predicate) {
    for (final controller in _controllers.values) {
      if (predicate(controller.currentPath)) controller.refresh();
    }
  }

  /// Removes entries moved away by a cut-and-paste from every pane that
  /// currently shows their source directory. Idempotent: panes not showing
  /// the affected directory simply match nothing.
  void applyLocalRemovals(Iterable<String> removedPaths) {
    final removed = removedPaths.toSet();
    if (removed.isEmpty) return;
    for (final controller in _controllers.values) {
      controller.applyLocalChanges(removedPaths: removed);
    }
  }

  void _collectPaneNodes(LayoutNode node, List<LayoutNode> out) {
    if (node.isPane) {
      out.add(node);
    }
    for (final child in node.children) {
      _collectPaneNodes(child, out);
    }
  }

  /// 根据 nodeId 获取对应的 PaneController
  PaneController? controllerFor(LayoutNode node) {
    if (!node.isPane || node.paneId == null) return null;
    return _controllers[node.paneId];
  }

  // ============================================================
  // 聚焦管理
  // ============================================================
  void focusNode(LayoutNode node) {
    if (_focusedNodeId != node.id) {
      _focusedNodeId = node.id;
      _updateActivePanePath();
      notifyListeners();
    }
  }

  // ============================================================
  // Workspace 操作
  // ============================================================
  void addWorkspace() {
    final name = 'Workspace ${_tree.workspaces.length + 1}';
    final ws = _tree.addWorkspace(name);
    // 加一个默认 pane
    final paneId = _nextPaneId();
    _addController(
      paneId,
      PaneController(FileService.homeViewPath, repository: _repository),
    );
    final pane = LayoutNode(
      id: _tree.genId(),
      type: NodeType.pane,
      paneId: paneId,
      parent: ws,
    );
    ws.children.add(pane);
    _tree.activeWorkspaceIndex = _tree.workspaces.length - 1;
    _focusedNodeId = pane.id;
    _updateActivePanePath();
    notifyListeners();
  }

  void switchWorkspace(int index) {
    if (index < 0 || index >= _tree.workspaces.length) return;
    if (_tree.activeWorkspaceIndex == index) return;
    _tree.activeWorkspaceIndex = index;
    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) _focusedNodeId = firstPane.id;
    _updateActivePanePath();
    notifyListeners();
  }

  void removeWorkspace(int index) {
    if (_tree.workspaces.length <= 1) return;
    final ws = _tree.workspaces[index];
    final result = _tree.closeNode(ws);
    for (final id in result.removedPanes) {
      _removeController(id);
    }
    _clearMaximizedIfRemoved(result.removedPanes);
    _tree.workspaces.removeAt(index);
    if (_tree.activeWorkspaceIndex >= _tree.workspaces.length) {
      _tree.activeWorkspaceIndex = _tree.workspaces.length - 1;
    }
    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) _focusedNodeId = firstPane.id;
    _updateActivePanePath();
    notifyListeners();
  }

  // ============================================================
  // Split 操作
  // ============================================================
  PaneController? splitPane(LayoutNode node, SplitDirection direction) {
    if (!node.isPane) return null;
    final newPaneId = _nextPaneId();
    final controller = PaneController(
      controllerFor(node)?.currentPath ?? FileService.desktopPath,
      repository: _repository,
    );
    _addController(newPaneId, controller);
    _tree.splitNode(node, direction, newPaneId);
    notifyListeners();
    return controller;
  }

  // ============================================================
  // 关闭操作
  // ============================================================
  void closePane(LayoutNode node) {
    if (!node.isPane) return;

    // 检查是否是最后一个 pane
    if (allPaneNodes.length <= 1) return;

    final result = _tree.closeNode(node);
    for (final id in result.removedPanes) {
      _removeController(id);
    }
    _clearMaximizedIfRemoved(result.removedPanes);

    // 焦点转移：优先兄弟 → 展平幸存者 → 首个 pane
    final nextFocusNode = result.nextFocusId != null
        ? _findNodeById(result.nextFocusId!)
        : null;
    if (nextFocusNode != null && nextFocusNode.isPane) {
      _focusedNodeId = nextFocusNode.id;
    } else {
      final firstPane = _findFirstPane(_tree.activeWorkspace);
      if (firstPane != null) _focusedNodeId = firstPane.id;
    }

    _updateActivePanePath();
    notifyListeners();
  }

  // ============================================================
  // 缩放操作（拖拽分割线）
  // ============================================================
  bool resizePane(LayoutNode node, SplitDirection direction, double delta) {
    // 在对应方向上找兄弟（delta 正负只决定找哪个兄弟）
    final sibling = direction == SplitDirection.horizontal
        ? (delta > 0 ? node.nextSibling : node.prevSibling)
        : (delta > 0 ? node.nextSibling : node.prevSibling);

    if (sibling == null || sibling.parent != node.parent) return false;

    // node 总是增长的一方，sibling 收缩
    final result = _tree.resizeNodes(node, sibling, delta.abs());
    if (result) notifyListeners();
    return result;
  }

  // ============================================================
  // 交换操作
  // ============================================================
  bool swapPanes(LayoutNode a, LayoutNode b) {
    final result = _tree.swapPanes(a, b);
    if (result) notifyListeners();
    return result;
  }

  // ============================================================
  // 浮动/覆盖层
  // ============================================================
  bool _altOverlayVisible = false;
  bool get altOverlayVisible => _altOverlayVisible;

  /// 最大化（浮于所有面板之上）的 pane id，null 表示无。
  String? _maximizedPaneId;
  String? get maximizedPaneId => _maximizedPaneId;

  void toggleMaximize(String paneId) {
    _maximizedPaneId = _maximizedPaneId == paneId ? null : paneId;
    if (_maximizedPaneId != null) {
      _altOverlayVisible = false;
      _swapPendingIds.clear();
    }
    notifyListeners();
  }

  void _clearMaximizedIfRemoved(Iterable<String> removedPaneIds) {
    final id = _maximizedPaneId;
    if (id != null && removedPaneIds.contains(id)) _maximizedPaneId = null;
  }

  void showAltOverlay() {
    if (!_altOverlayVisible) {
      _altOverlayVisible = true;
      notifyListeners();
    }
  }

  void hideAltOverlay() {
    if (_altOverlayVisible) {
      _altOverlayVisible = false;
      _swapPendingIds.clear();
      notifyListeners();
    }
  }

  void toggleAltOverlay() {
    _altOverlayVisible = !_altOverlayVisible;
    if (!_altOverlayVisible) _swapPendingIds.clear();
    notifyListeners();
  }

  // ============================================================
  // Swap 选中状态（Alt 模式下）
  // ============================================================
  final Set<String> _swapPendingIds = {};
  Set<String> get swapPendingIds => _swapPendingIds;

  void toggleSwapSelect(LayoutNode node) {
    if (!node.isPane) return;
    if (_swapPendingIds.contains(node.id)) {
      _swapPendingIds.remove(node.id);
    } else {
      _swapPendingIds.add(node.id);
      if (_swapPendingIds.length == 2) {
        final ids = _swapPendingIds.toList();
        final a = _findNodeById(ids[0]);
        final b = _findNodeById(ids[1]);
        _swapPendingIds.clear();
        if (a != null && b != null) swapPanes(a, b);
      }
    }
    notifyListeners();
  }

  // ============================================================
  // 内部辅助
  // ============================================================
  String _nextPaneId() => 'pane_${_nextPaneCounter++}';

  LayoutNode? _findNodeById(String id) {
    return _findById(_tree.activeWorkspace, id);
  }

  LayoutNode? _findById(LayoutNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findById(child, id);
      if (found != null) return found;
    }
    return null;
  }

  LayoutNode? _findFirstPane(LayoutNode node) {
    if (node.isPane) return node;
    for (final child in node.children) {
      final found = _findFirstPane(child);
      if (found != null) return found;
    }
    return null;
  }
}
