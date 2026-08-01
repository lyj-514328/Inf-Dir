import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layout_node.dart';
import '../state/layout_state.dart';
import 'app_theme.dart';
import 'file_pane.dart';
import 'alt_overlay.dart';

/// 递归渲染布局树 — 仿 i3 render_con()
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        return isHorizontal
            ? Row(
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      _Splitter(
                        direction: SplitDirection.horizontal,
                        left: children[i - 1],
                        right: children[i],
                        totalSize: totalSize,
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
                    if (i > 0)
                      _Splitter(
                        direction: SplitDirection.vertical,
                        top: children[i - 1],
                        bottom: children[i],
                        totalSize: totalSize,
                      ),
                    Expanded(
                      flex: _flexFromPercent(children[i].percent, node),
                      child: LayoutView(node: children[i]),
                    ),
                  ],
                ],
              );
      },
    );
  }

  int _flexFromPercent(double percent, LayoutNode parent) {
    if (percent <= 0) {
      return (1.0 / parent.children.length * 500).round();
    }
    return (percent * 500).round().clamp(1, 5000);
  }
}

class _PaneWrapper extends StatelessWidget {
  final LayoutNode node;

  const _PaneWrapper({required this.node});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layoutState = context.watch<LayoutState>();
    final controller = layoutState.controllerFor(node);
    final isFocused = layoutState.focusedNodeId == node.id;

    if (controller == null) return const SizedBox.shrink();

    return Listener(
      onPointerDown: (_) => layoutState.focusNode(node),
      child: Container(
        margin: const EdgeInsets.all(AppMetrics.paneGap / 2),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
          border: Border.all(
            color: isFocused ? c.accent : c.border,
            width: 1.5,
          ),
          color: c.surface,
        ),
        child: Stack(
          children: [
            FilePane(paneId: node.paneId!),
            if (layoutState.altOverlayVisible)
              _buildAltOverlay(layoutState),
          ],
        ),
      ),
    );
  }

  Widget _buildAltOverlay(LayoutState layoutState) {
    return AltOverlay(
      node: node,
      isSwapSelected: layoutState.swapPendingIds.contains(node.id),
      onClose: () => layoutState.closePane(node),
      onSplit: (dir) => layoutState.splitPane(node, dir),
      onSwap: () => layoutState.toggleSwapSelect(node),
    );
  }
}

class _Splitter extends StatefulWidget {
  final SplitDirection direction;
  final LayoutNode? left;
  final LayoutNode? right;
  final LayoutNode? top;
  final LayoutNode? bottom;
  final double totalSize;

  const _Splitter({
    required this.direction,
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.totalSize,
  });

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hovering = false;
  bool _dragging = false;
  double _startPos = 0;   // 拖拽起点（全局坐标）
  double _startPct = 0;   // 拖拽起点时 left/top 的 percent

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isH = widget.direction == SplitDirection.horizontal;
    final altVisible = context.watch<LayoutState>().altOverlayVisible;

    return MouseRegion(
      cursor: isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onPanStart: (details) {
          setState(() => _dragging = true);
          _startPos = isH ? details.globalPosition.dx : details.globalPosition.dy;
          _startPct = isH ? widget.left!.percent : widget.top!.percent;
        },
        onPanUpdate: (details) {
          final pos = isH ? details.globalPosition.dx : details.globalPosition.dy;
          final diff = pos - _startPos;
          final targetPct = _startPct + (diff / widget.totalSize);

          final state = context.read<LayoutState>();
          final first = isH ? widget.left! : widget.top!;
          final second = isH ? widget.right! : widget.bottom!;
          final total = first.percent + second.percent;
          final clamped = targetPct.clamp(0.05, total - 0.05);

          if ((clamped - first.percent).abs() < 0.0001) return;
          first.percent = clamped;
          second.percent = total - clamped;
          state.notifyListeners();
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
        },
        child: Container(
          width: isH ? 3 : double.infinity,
          height: isH ? double.infinity : 3,
          color: _dragging
              ? c.accent
              : _hovering
                  ? c.accent.withValues(alpha: 0.35)
                  : altVisible
                      ? c.border
                      : Colors.transparent,
        ),
      ),
    );
  }
}
