import 'package:flutter/foundation.dart';
import '../models/layout_node.dart';
import 'pane_controller.dart';
import '../services/file_service.dart';

class LayoutState extends ChangeNotifier {
  late final LayoutTree _tree;
  final Map<String, PaneController> _controllers = {};
  String _focusedNodeId = '';
  int _nextPaneCounter = 0;

  LayoutState() {
    // 创建 4 个初始面板控制器
    final initialPaths = [
      FileService.desktopPath,
      FileService.homeDirectory,
      FileService.documentsPath,
      FileService.downloadsPath,
    ];
    final paneIds = <String>[];
    for (final path in initialPaths) {
      final id = _nextPaneId();
      _controllers[id] = PaneController(path);
      paneIds.add(id);
    }

    _tree = createDefaultLayout(paneIds);

    // 默认聚焦第一个 pane
    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) {
      _focusedNodeId = firstPane.id;
    }
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

  /// 获取所有 pane 节点
  List<LayoutNode> get allPaneNodes {
    final result = <LayoutNode>[];
    _collectPaneNodes(_tree.activeWorkspace, result);
    return result;
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
    _controllers[paneId] = PaneController(FileService.desktopPath);
    final pane = LayoutNode(
      id: _tree.genId(),
      type: NodeType.pane,
      paneId: paneId,
      parent: ws,
    );
    ws.children.add(pane);
    _tree.activeWorkspaceIndex = _tree.workspaces.length - 1;
    _focusedNodeId = pane.id;
    notifyListeners();
  }

  void switchWorkspace(int index) {
    if (index < 0 || index >= _tree.workspaces.length) return;
    if (_tree.activeWorkspaceIndex == index) return;
    _tree.activeWorkspaceIndex = index;
    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) _focusedNodeId = firstPane.id;
    notifyListeners();
  }

  void removeWorkspace(int index) {
    if (_tree.workspaces.length <= 1) return;
    final ws = _tree.workspaces[index];
    final result = _tree.closeNode(ws);
    for (final id in result.removedPanes) {
      _controllers.remove(id);
    }
    _tree.workspaces.removeAt(index);
    if (_tree.activeWorkspaceIndex >= _tree.workspaces.length) {
      _tree.activeWorkspaceIndex = _tree.workspaces.length - 1;
    }
    final firstPane = _findFirstPane(_tree.activeWorkspace);
    if (firstPane != null) _focusedNodeId = firstPane.id;
    notifyListeners();
  }

  // ============================================================
  // Split 操作
  // ============================================================
  void splitPane(LayoutNode node, SplitDirection direction) {
    if (!node.isPane) return;
    final newPaneId = _nextPaneId();
    _controllers[newPaneId] = PaneController(
      controllerFor(node)?.currentPath ?? FileService.desktopPath,
    );
    _tree.splitNode(node, direction, newPaneId);
    notifyListeners();
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
      _controllers.remove(id);
    }

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
