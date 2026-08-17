/// 节点类型：Workspace / 分割容器 / 文件面板
enum NodeType { workspace, split, pane }

/// 分割方向
enum SplitDirection { horizontal, vertical }

/// 面板拖放到目标面板的相对位置。
enum PaneDropEdge { left, right, top, bottom }

/// 参考 Hyprland Dwindle 的递归分割节点，并扩展为可容纳多个子节点。
///
/// 上游参考：
/// ai_refs/Hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp
///
/// 树结构示例：
///   workspace (horizontal / 左右排列)
///   ├── split (vertical / 上下排列)
///   │   ├── pane (A)
///   │   └── pane (B)
///   └── pane (C)
class LayoutNode {
  final String id;
  NodeType type;
  SplitDirection layout; // split 才有效
  double percent; // 占父容器空间比例 (0.0~1.0)，所有兄弟之和 = 1.0
  String? paneId; // pane 类型时关联的控制器 ID
  String? label; // workspace 名称
  LayoutNode? parent;
  final List<LayoutNode> children;

  LayoutNode({
    required this.id,
    required this.type,
    this.layout = SplitDirection.horizontal,
    this.percent = 0.0,
    this.paneId,
    this.label,
    this.parent,
    List<LayoutNode>? children,
  }) : children = children ?? [];

  bool get isLeaf => children.isEmpty;
  bool get isWorkspace => type == NodeType.workspace;
  bool get isSplit => type == NodeType.split;
  bool get isPane => type == NodeType.pane;

  /// 找最近的 workspace 祖先
  LayoutNode? get workspace {
    LayoutNode? cur = this;
    while (cur != null && cur.type != NodeType.workspace) {
      cur = cur.parent;
    }
    return cur;
  }

  /// 兄弟节点数量
  int get siblingCount => parent?.children.length ?? 0;

  /// 在当前父节点 children 中的索引
  int get indexInParent {
    if (parent == null) return -1;
    return parent!.children.indexOf(this);
  }

  /// 前一个兄弟
  LayoutNode? get prevSibling {
    final idx = indexInParent;
    if (parent == null || idx <= 0) return null;
    return parent!.children[idx - 1];
  }

  /// 后一个兄弟
  LayoutNode? get nextSibling {
    final idx = indexInParent;
    if (parent == null || idx >= parent!.children.length - 1) return null;
    return parent!.children[idx + 1];
  }
}

/// 关闭操作的结果
class CloseResult {
  final List<String> removedPanes;
  final String? nextFocusId; // 建议聚焦的节点 ID，null 则回退到首个 pane

  CloseResult({required this.removedPanes, this.nextFocusId});
}

/// 布局树管理器 — 提供所有操作
class LayoutTree {
  final List<LayoutNode> workspaces;
  int activeWorkspaceIndex;
  int _counter;

  LayoutTree({
    required this.workspaces,
    this.activeWorkspaceIndex = 0,
    int idCounter = 0,
  }) : _counter = idCounter;

  int get idCounter => _counter;

  LayoutNode get activeWorkspace => workspaces[activeWorkspaceIndex];

  // ============================================================
  // 操作 1：新建 workspace
  // ============================================================
  LayoutNode addWorkspace(String name) {
    final ws = LayoutNode(
      id: genId(),
      type: NodeType.workspace,
      layout: SplitDirection.horizontal,
      label: name,
    );
    workspaces.add(ws);
    return ws;
  }

  // ============================================================
  // 操作 2：分割（水平/垂直）—— 参考 CDwindleAlgorithm::addTarget()
  // ============================================================
  void splitNode(LayoutNode node, SplitDirection direction, String newPaneId) {
    final parent = node.parent;

    // 如果父节点只有 1 个孩子且方向相同 → 直接改方向
    if (parent != null &&
        parent.isSplit &&
        parent.children.length == 1 &&
        parent.layout == direction) {
      // 直接加兄弟
      final newPane = LayoutNode(
        id: genId(),
        type: NodeType.pane,
        paneId: newPaneId,
        parent: parent,
      );
      parent.children.add(newPane);
      _fixPercent(parent);
      return;
    }

    // 否则创建新的分割容器包裹 node
    final split = LayoutNode(
      id: genId(),
      type: NodeType.split,
      layout: direction,
      parent: parent,
    );

    if (parent != null) {
      // 在父节点中用 split 替换 node
      final idx = parent.children.indexOf(node);
      parent.children[idx] = split;
    }
    split.percent = node.percent;

    // node 变成 split 的孩子
    node.parent = split;
    node.percent = 0.0;
    split.children.add(node);

    // 新面板作为另一个孩子
    final newPane = LayoutNode(
      id: genId(),
      type: NodeType.pane,
      paneId: newPaneId,
      parent: split,
    );
    split.children.add(newPane);

    _fixPercent(split);
    if (parent != null) _fixPercent(parent);
  }

  // ============================================================
  // 操作 3：关闭节点 —— 参考 CDwindleAlgorithm::removeTarget()
  // ============================================================
  /// 关闭节点，返回 (需清理的 paneId 列表, 建议聚焦节点 ID)
  CloseResult closeNode(LayoutNode node) {
    final removed = <String>[];

    // 在摘除之前记录兄弟和父节点信息，用于确定下一个焦点
    final sibling = node.nextSibling ?? node.prevSibling;
    final parent = node.parent;

    _closeInternal(node, removed);

    // 确定下一个焦点：
    // 1) 优先兄弟（关闭后在原位置的邻居）
    // 2) 父节点被展平后的幸存者
    // 3) null — 由调用方回退
    String? nextFocusId;
    if (sibling != null) {
      nextFocusId = _firstLeafId(sibling);
    } else if (parent != null &&
        parent.isSplit &&
        parent.children.length == 1) {
      // 关闭后父节点只剩一个孩子，展平逻辑会在 _closeInternal 触发
      nextFocusId = _firstLeafId(parent.children.first);
    }

    return CloseResult(removedPanes: removed, nextFocusId: nextFocusId);
  }

  void _closeInternal(LayoutNode node, List<String> removedPanes) {
    // 递归关闭子节点
    final childrenCopy = List<LayoutNode>.from(node.children);
    for (final child in childrenCopy) {
      _closeInternal(child, removedPanes);
    }

    // 记录 paneId
    if (node.isPane && node.paneId != null) {
      removedPanes.add(node.paneId!);
    }

    final parent = node.parent;
    if (parent == null) return;

    // 从父节点摘除
    parent.children.remove(node);

    // 如果父节点是 split 且只剩一个孩子 → 展平到祖父节点
    if (parent.isSplit && parent.children.length == 1) {
      final survivor = parent.children.removeAt(0);
      if (parent.parent != null) {
        final gpIdx = parent.parent!.children.indexOf(parent);
        parent.parent!.children[gpIdx] = survivor;
        survivor.parent = parent.parent;
        survivor.percent = parent.percent;
      }
    }

    if (parent.isSplit && parent.children.isEmpty) {
      parent.parent?.children.remove(parent);
    }

    _fixPercent(parent);
  }

  /// 递归找到节点下的第一个叶子 pane 的 id
  String? _firstLeafId(LayoutNode node) {
    if (node.isPane) return node.id;
    for (final child in node.children) {
      final id = _firstLeafId(child);
      if (id != null) return id;
    }
    return null;
  }

  // ============================================================
  // 操作 4：缩放 —— CDwindleAlgorithm::resizeTarget() 的相邻兄弟简化版
  // ============================================================
  /// first 和 second 是同一父节点的相邻兄弟，delta 是比例变化 (正=first 增大)
  bool resizeNodes(LayoutNode first, LayoutNode second, double deltaPercent) {
    if (first.parent != second.parent) return false;
    final parent = first.parent!;

    final newFirst = first.percent + deltaPercent;
    final newSecond = second.percent - deltaPercent;

    // 保证每个至少有 5% 空间
    if (newFirst < 0.05 || newSecond < 0.05) return false;

    first.percent = newFirst;
    second.percent = newSecond;
    _fixPercent(parent);
    return true;
  }

  // ============================================================
  // 操作 5：交换两个 pane —— 参考 CDwindleAlgorithm::swapTargets()
  // ============================================================
  bool swapPanes(LayoutNode a, LayoutNode b) {
    if (a == b || !a.isPane || !b.isPane) return false;
    if (a.parent == null || b.parent == null) return false;

    // 在同一父节点内交换位置
    if (a.parent == b.parent) {
      final p = a.parent!;
      final ai = p.children.indexOf(a);
      final bi = p.children.indexOf(b);
      p.children[ai] = b;
      p.children[bi] = a;
      // 交换百分比
      final tmp = a.percent;
      a.percent = b.percent;
      b.percent = tmp;
      return true;
    }

    // 跨父节点交换
    final pa = a.parent!;
    final pb = b.parent!;
    final ai = pa.children.indexOf(a);
    final bi = pb.children.indexOf(b);

    pa.children[ai] = b;
    pb.children[bi] = a;
    b.parent = pa;
    a.parent = pb;

    final tmpPercent = a.percent;
    a.percent = b.percent;
    b.percent = tmpPercent;

    _fixPercent(pa);
    _fixPercent(pb);
    return true;
  }

  // ============================================================
  // 操作 6：移动 pane 到目标 pane 的一侧
  // ============================================================
  bool movePaneBeside(LayoutNode source, LayoutNode target, PaneDropEdge edge) {
    if (source == target || !source.isPane || !target.isPane) return false;
    if (source.parent == null || target.parent == null) return false;
    if (source.workspace != target.workspace) return false;

    final direction = switch (edge) {
      PaneDropEdge.left || PaneDropEdge.right => SplitDirection.horizontal,
      PaneDropEdge.top || PaneDropEdge.bottom => SplitDirection.vertical,
    };
    final sourceFirst = edge == PaneDropEdge.left || edge == PaneDropEdge.top;

    // 已经是目标的直接二叉兄弟时，保持原有分割比例和节点层级。
    final sharedParent = source.parent == target.parent ? source.parent : null;
    if (sharedParent != null &&
        sharedParent.isSplit &&
        sharedParent.children.length == 2 &&
        sharedParent.layout == direction) {
      final expectedFirst = sourceFirst ? source : target;
      if (sharedParent.children.first == expectedFirst) return false;
      return swapPanes(source, target);
    }

    _detachForMove(source);

    final targetParent = target.parent;
    if (targetParent == null) return false;
    final targetIndex = targetParent.children.indexOf(target);
    if (targetIndex < 0) return false;

    final split = LayoutNode(
      id: genId(),
      type: NodeType.split,
      layout: direction,
      percent: target.percent,
      parent: targetParent,
    );
    targetParent.children[targetIndex] = split;

    target.parent = split;
    source.parent = split;
    target.percent = 0.5;
    source.percent = 0.5;
    split.children.addAll(sourceFirst ? [source, target] : [target, source]);

    _fixPercent(targetParent);
    return true;
  }

  void _detachForMove(LayoutNode node) {
    final parent = node.parent!;
    parent.children.remove(node);
    node.parent = null;
    node.percent = 0.0;
    _repairAfterDetach(parent);
  }

  void _repairAfterDetach(LayoutNode container) {
    if (!container.isSplit || container.children.length > 1) {
      _fixPercent(container);
      return;
    }

    final grandparent = container.parent;
    if (grandparent == null) {
      _fixPercent(container);
      return;
    }

    final containerIndex = grandparent.children.indexOf(container);
    if (containerIndex < 0) return;

    if (container.children.length == 1) {
      final survivor = container.children.removeAt(0);
      grandparent.children[containerIndex] = survivor;
      survivor.parent = grandparent;
      survivor.percent = container.percent;
    } else {
      grandparent.children.removeAt(containerIndex);
    }

    container.parent = null;
    container.percent = 0.0;
    _repairAfterDetach(grandparent);
  }

  // ============================================================
  // 百分比归一化 —— 维护本项目多子节点扩展的比例不变量
  // ============================================================
  void _fixPercent(LayoutNode parent) {
    final n = parent.children.length;
    if (n == 0) return;

    double total = 0.0;
    int withPercent = 0;
    for (final c in parent.children) {
      if (c.percent > 0.0) {
        total += c.percent;
        withPercent++;
      }
    }

    // 没有设置百分比的给默认值
    if (withPercent != n) {
      for (final c in parent.children) {
        if (c.percent <= 0.0) {
          c.percent = withPercent == 0 ? 1.0 : total / withPercent;
          total += c.percent;
          withPercent++;
        }
      }
    }

    // 归一化到 1.0
    if (total == 0.0) {
      final avg = 1.0 / n;
      for (final c in parent.children) {
        c.percent = avg;
      }
    } else if (total != 1.0) {
      for (final c in parent.children) {
        c.percent /= total;
      }
    }
  }

  String genId() => 'n${++_counter}';
}

/// 构建默认的 4 宫格布局
LayoutTree createDefaultLayout(
  List<String> paneIds, {
  String workspaceLabel = 'Workspace 1',
}) {
  final ws = LayoutNode(
    id: 'ws0',
    type: NodeType.workspace,
    layout: SplitDirection.vertical,
    label: workspaceLabel,
  );

  if (paneIds.length == 1) {
    final pane = LayoutNode(
      id: 'p0',
      type: NodeType.pane,
      paneId: paneIds.first,
      parent: ws,
    );
    ws.children.add(pane);
    final tree = LayoutTree(workspaces: [ws]);
    tree._fixPercent(ws);
    return tree;
  }

  // 上排 (水平分割)
  final topRow = LayoutNode(
    id: 'split_top',
    type: NodeType.split,
    layout: SplitDirection.horizontal,
    parent: ws,
  );
  topRow.children.addAll([
    LayoutNode(
      id: 'p0',
      type: NodeType.pane,
      paneId: paneIds[0],
      parent: topRow,
    ),
    LayoutNode(
      id: 'p1',
      type: NodeType.pane,
      paneId: paneIds[1],
      parent: topRow,
    ),
  ]);

  // 下排 (水平分割)
  final bottomRow = LayoutNode(
    id: 'split_bottom',
    type: NodeType.split,
    layout: SplitDirection.horizontal,
    parent: ws,
  );
  bottomRow.children.addAll([
    LayoutNode(
      id: 'p2',
      type: NodeType.pane,
      paneId: paneIds[2],
      parent: bottomRow,
    ),
    LayoutNode(
      id: 'p3',
      type: NodeType.pane,
      paneId: paneIds[3],
      parent: bottomRow,
    ),
  ]);

  ws.children.addAll([topRow, bottomRow]);

  final tree = LayoutTree(workspaces: [ws]);
  tree._fixPercent(ws);
  // 修复子节点
  tree._fixPercent(topRow);
  tree._fixPercent(bottomRow);

  return tree;
}
