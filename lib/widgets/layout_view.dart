import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layout_node.dart';
import '../models/pane_drag_payload.dart';
import '../state/layout_state.dart';
import 'app_theme.dart';
import 'file_pane.dart';
import 'alt_overlay.dart';

PaneDropEdge paneDropEdgeForPosition(Offset position, Size size) {
  final dx = (position.dx - size.width / 2) / size.width;
  final dy = (position.dy - size.height / 2) / size.height;
  if (dx.abs() >= dy.abs()) {
    return dx < 0 ? PaneDropEdge.left : PaneDropEdge.right;
  }
  return dy < 0 ? PaneDropEdge.top : PaneDropEdge.bottom;
}

/// 递归渲染布局树，参考 SDwindleNodeData::recalcSizePosRecursive()。
class LayoutView extends StatelessWidget {
  final LayoutNode node;
  final bool Function(String path)? cloudZoneResolver;

  const LayoutView({super.key, required this.node, this.cloudZoneResolver});

  @override
  Widget build(BuildContext context) {
    if (node.isPane) {
      return _PaneWrapper(node: node, cloudZoneResolver: cloudZoneResolver);
    }
    if (node.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final isHorizontal = node.layout == SplitDirection.horizontal;
    final children = node.children;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
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
                      child: LayoutView(
                        node: children[i],
                        cloudZoneResolver: cloudZoneResolver,
                      ),
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
                      child: LayoutView(
                        node: children[i],
                        cloudZoneResolver: cloudZoneResolver,
                      ),
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

class _PaneWrapper extends StatefulWidget {
  final LayoutNode node;
  final bool Function(String path)? cloudZoneResolver;

  const _PaneWrapper({required this.node, required this.cloudZoneResolver});

  @override
  State<_PaneWrapper> createState() => _PaneWrapperState();
}

class _PaneWrapperState extends State<_PaneWrapper> {
  final GlobalKey _dropSurfaceKey = GlobalKey();
  PaneDropEdge? _dropEdge;

  LayoutNode get node => widget.node;

  bool _canAccept(PaneDragPayload payload) {
    return payload.source != node && payload.source.workspace == node.workspace;
  }

  PaneDropEdge? _edgeForGlobalPosition(Offset globalPosition) {
    final renderObject = _dropSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return paneDropEdgeForPosition(
      renderObject.globalToLocal(globalPosition),
      renderObject.size,
    );
  }

  void _updateDropEdge(Offset globalPosition) {
    final edge = _edgeForGlobalPosition(globalPosition);
    if (edge == null || edge == _dropEdge) return;
    setState(() => _dropEdge = edge);
  }

  void _clearDropEdge() {
    if (_dropEdge == null) return;
    setState(() => _dropEdge = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layoutState = context.watch<LayoutState>();
    final controller = layoutState.controllerFor(node);
    final isFocused = layoutState.focusedNodeId == node.id;

    if (controller == null) return const SizedBox.shrink();

    return DragTarget<PaneDragPayload>(
      key: ValueKey('pane-drop-target-${node.id}'),
      onWillAcceptWithDetails: (details) {
        if (!_canAccept(details.data)) return false;
        _updateDropEdge(details.offset);
        return true;
      },
      onMove: (details) {
        if (_canAccept(details.data)) _updateDropEdge(details.offset);
      },
      onLeave: (_) => _clearDropEdge(),
      onAcceptWithDetails: (details) {
        final edge = _dropEdge ?? _edgeForGlobalPosition(details.offset);
        _clearDropEdge();
        if (edge != null) {
          layoutState.movePaneBeside(details.data.source, node, edge);
        }
      },
      builder: (context, _, _) => SizedBox.expand(
        key: _dropSurfaceKey,
        child: Listener(
          onPointerDown: (_) => layoutState.focusNode(node),
          child: Container(
            margin: const EdgeInsets.all(AppMetrics.paneGap / 2),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
              color: c.surface,
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: c.scrim,
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
              border: Border.all(
                color: isFocused ? c.accent.withValues(alpha: 0.6) : c.border,
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                FilePane(
                  paneId: node.paneId!,
                  cloudZoneResolver: widget.cloudZoneResolver,
                ),
                if (layoutState.paneDragActive &&
                    layoutState.draggedPaneNodeId != node.id)
                  _PaneDropOverlay(nodeId: node.id, edge: _dropEdge)
                else if (layoutState.altOverlayVisible ||
                    layoutState.draggedPaneNodeId == node.id)
                  _buildAltOverlay(layoutState, controller.currentPath),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAltOverlay(LayoutState layoutState, String dragLabel) {
    return AltOverlay(
      node: node,
      isSwapSelected: layoutState.swapPendingIds.contains(node.id),
      onClose: () => layoutState.closePane(node),
      onSplit: (dir) => layoutState.splitPane(node, dir),
      onSwap: () => layoutState.toggleSwapSelect(node),
      dragLabel: dragLabel,
      isDragging: layoutState.draggedPaneNodeId == node.id,
      onDragStarted: () => layoutState.beginPaneDrag(node),
      onDragEnded: layoutState.endPaneDrag,
    );
  }
}

class _PaneDropOverlay extends StatelessWidget {
  const _PaneDropOverlay({required this.nodeId, required this.edge});

  final String nodeId;
  final PaneDropEdge? edge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: Stack(
        key: ValueKey('pane-drop-overlay-$nodeId'),
        children: [
          Positioned.fill(child: Container(color: c.scrim)),
          Positioned.fill(
            child: CustomPaint(painter: _PaneDropGuidePainter(c.borderStrong)),
          ),
          if (edge != null) _buildPreview(c),
        ],
      ),
    );
  }

  Widget _buildPreview(AppColors c) {
    final isHorizontal =
        edge == PaneDropEdge.left || edge == PaneDropEdge.right;
    final alignment = switch (edge!) {
      PaneDropEdge.left => Alignment.centerLeft,
      PaneDropEdge.right => Alignment.centerRight,
      PaneDropEdge.top => Alignment.topCenter,
      PaneDropEdge.bottom => Alignment.bottomCenter,
    };
    final icon = switch (edge!) {
      PaneDropEdge.left => Icons.arrow_back,
      PaneDropEdge.right => Icons.arrow_forward,
      PaneDropEdge.top => Icons.arrow_upward,
      PaneDropEdge.bottom => Icons.arrow_downward,
    };

    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: isHorizontal ? 0.5 : 1,
          heightFactor: isHorizontal ? 1 : 0.5,
          child: Container(
            key: ValueKey('pane-drop-preview-${edge!.name}'),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.22),
              border: Border.all(color: c.accent, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 24, color: c.accent),
          ),
        ),
      ),
    );
  }
}

class _PaneDropGuidePainter extends CustomPainter {
  const _PaneDropGuidePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_PaneDropGuidePainter oldDelegate) {
    return oldDelegate.color != color;
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
  double _startPos = 0; // 拖拽起点（全局坐标）
  double _startPct = 0; // 拖拽起点时 left/top 的 percent

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isH = widget.direction == SplitDirection.horizontal;
    final altVisible = context.watch<LayoutState>().altOverlayVisible;

    return MouseRegion(
      cursor: isH
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onPanStart: (details) {
          setState(() => _dragging = true);
          _startPos = isH
              ? details.globalPosition.dx
              : details.globalPosition.dy;
          _startPct = isH ? widget.left!.percent : widget.top!.percent;
        },
        onPanUpdate: (details) {
          final pos = isH
              ? details.globalPosition.dx
              : details.globalPosition.dy;
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
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          state.notifyListeners();
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
        },
        child: Container(
          width: isH ? 8 : double.infinity,
          height: isH ? double.infinity : 8,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: isH ? 1 : double.infinity,
            height: isH ? double.infinity : 1,
            color: _dragging
                ? c.accent
                : _hovering
                ? c.border
                : altVisible
                ? c.border
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
