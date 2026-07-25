import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/layout_node.dart';
import '../state/layout_state.dart';

/// Alt 键按下时在面板上显示的浮动操作按钮层
///
/// 提供针对当前聚焦 pane 的操作：
/// - 水平/垂直分割
/// - 关闭
/// - 与相邻面板交换
class AltOverlay extends StatefulWidget {
  final LayoutNode node;

  const AltOverlay({super.key, required this.node});

  @override
  State<AltOverlay> createState() => _AltOverlayState();
}

class _AltOverlayState extends State<AltOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black26,
        child: Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _OpButton(
                icon: Icons.vertical_split,
                label: '垂直切分',
                tooltip: '在右侧创建新面板',
                onTap: () => _split(SplitDirection.horizontal),
              ),
              _OpButton(
                icon: Icons.horizontal_split,
                label: '水平切分',
                tooltip: '在下方创建新面板',
                onTap: () => _split(SplitDirection.vertical),
              ),
              _OpButton(
                icon: Icons.close,
                label: '关闭',
                tooltip: '关闭当前面板',
                color: Colors.red,
                onTap: _closePane,
              ),
              _OpButton(
                icon: Icons.swap_horiz,
                label: '交换',
                tooltip: '与相邻面板交换位置',
                onTap: () => _showSwapMenu(context),
              ),
              _OpButton(
                icon: Icons.open_in_full,
                label: '扩大',
                tooltip: '向两侧扩展 5%',
                onTap: _expandRight,
              ),
              _OpButton(
                icon: Icons.close_fullscreen,
                label: '缩小',
                tooltip: '向两侧收缩 5%',
                onTap: _shrinkLeft,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _split(SplitDirection dir) {
    final state = context.read<LayoutState>();
    state.splitPane(widget.node, dir);
  }

  void _closePane() {
    final state = context.read<LayoutState>();
    state.closePane(widget.node);
  }

  void _expandRight() {
    final state = context.read<LayoutState>();
    // 在水平和垂直方向都尝试扩展
    state.resizePane(widget.node, SplitDirection.horizontal, 0.05);
    state.resizePane(widget.node, SplitDirection.vertical, 0.05);
  }

  void _shrinkLeft() {
    final state = context.read<LayoutState>();
    state.resizePane(widget.node, SplitDirection.horizontal, -0.05);
    state.resizePane(widget.node, SplitDirection.vertical, -0.05);
  }

  void _showSwapMenu(BuildContext context) {
    final state = context.read<LayoutState>();
    final allPanes = state.allPaneNodes.where((p) => p.id != widget.node.id).toList();
    if (allPanes.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择交换目标', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 250,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allPanes.length,
            itemBuilder: (_, i) {
              final p = allPanes[i];
              final ctrl = state.controllerFor(p);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.grid_view, size: 20),
                title: Text(
                  ctrl?.displayPath ?? p.id,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  state.swapPanes(widget.node, p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

class _OpButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _OpButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color ?? const Color(0xFF333333)),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color ?? const Color(0xFF555555),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
