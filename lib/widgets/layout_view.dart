import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layout_node.dart';
import '../state/layout_state.dart';
import 'file_pane.dart';
import 'alt_overlay.dart';

/// 递归渲染布局树 — 仿 i3 render_con()
///
/// 每个非叶子节点根据 layout (horizontal/vertical) 把空间按 percent 分给子节点，
/// 叶子节点 (pane) 渲染为 FilePane。
class LayoutView extends StatelessWidget {
  final LayoutNode node;

  const LayoutView({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    if (node.isPane) {
      return _PaneWrapper(node: node);
    }

    if (node.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final isHorizontal = node.layout == SplitDirection.horizontal;
    final children = node.children;

    return isHorizontal
        ? Row(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) _Splitter(
                  direction: SplitDirection.horizontal,
                  left: children[i - 1],
                  right: children[i],
                ),
                Expanded(
                  flex: _flexFromPercent(children[i].percent, node),
                  child: LayoutView(node: children[i]),
                ),
              ],
            ],
          )
        : Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) _Splitter(
                  direction: SplitDirection.vertical,
                  top: children[i - 1],
                  bottom: children[i],
                ),
                Expanded(
                  flex: _flexFromPercent(children[i].percent, node),
                  child: LayoutView(node: children[i]),
                ),
              ],
            ],
          );
  }

  /// 将 percent 转为整数的 flex 值（用于 Expanded）
  int _flexFromPercent(double percent, LayoutNode parent) {
    if (percent <= 0) {
      return (1.0 / parent.children.length * 1000).round();
    }
    return (percent * 1000).round().clamp(1, 10000);
  }
}

/// Pane 包装器 — 负责聚焦、Alt 浮层、圆角边框
class _PaneWrapper extends StatelessWidget {
  final LayoutNode node;

  const _PaneWrapper({required this.node});

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutState>();
    final controller = layoutState.controllerFor(node);
    final isFocused = layoutState.focusedNodeId == node.id;

    if (controller == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => layoutState.focusNode(node),
      child: Container(
        margin: const EdgeInsets.all(2),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFocused ? const Color(0xFF0078D4) : const Color(0xFFC0C0C0),
            width: isFocused ? 2 : 1,
          ),
          color: Colors.white,
        ),
        child: Stack(
          children: [
            FilePane(paneId: node.paneId!),
            if (isFocused && layoutState.altOverlayVisible)
              AltOverlay(node: node),
          ],
        ),
      ),
    );
  }
}

/// 可拖拽的分割线
class _Splitter extends StatefulWidget {
  final SplitDirection direction;
  final LayoutNode? left;
  final LayoutNode? right;
  final LayoutNode? top;
  final LayoutNode? bottom;

  const _Splitter({
    required this.direction,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final isH = widget.direction == SplitDirection.horizontal;

    return MouseRegion(
      cursor: isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          final state = context.read<LayoutState>();
          final deltaPixels = isH ? details.delta.dx : details.delta.dy;
          // 假设父容器大约 800px 宽/高，delta / 800 = 百分比变化
          const approxSize = 800.0;
          final deltaPercent = deltaPixels / approxSize;

          if (isH && widget.left != null && widget.right != null) {
            state.resizePane(widget.left!, widget.direction, deltaPercent);
          } else if (!isH && widget.top != null && widget.bottom != null) {
            state.resizePane(widget.top!, widget.direction, deltaPercent);
          }
        },
        onPanEnd: (_) => setState(() => _dragging = false),
        child: Container(
          width: isH ? 5 : double.infinity,
          height: isH ? double.infinity : 5,
          color: _dragging
              ? const Color(0xFF0078D4)
              : _hovering
                  ? const Color(0xFFA0A0A0)
                  : const Color(0xFFD8D8D8),
        ),
      ),
    );
  }
}
