import 'package:flutter/material.dart';
import '../models/layout_node.dart';
import 'app_theme.dart';

/// Alt 键按下时在每个面板上显示的浮动操作层。
///
/// 设计：操作层是"浮在面板上的一张玻璃片"——
/// - 面板中央一条收敛的细十字线（仅作分割方向暗示，两端渐隐）
/// - 中央三个浮动操作 chip：水平切分 / 交换 / 垂直切分
///   （surface 底 + 1px 边框 + 柔和投影，hover 显 surfaceHover）
/// - 左下角一行低调提示文字（tertiary），弥补顶栏移除的 Alt 提示
/// - 右上角关闭按钮（hover 显红，Win11 语义）
///
/// 颜色全部走 [AppColors] token，单一 accent 语义色。
class AltOverlay extends StatelessWidget {
  final LayoutNode node;
  final bool isSwapSelected;
  final VoidCallback onClose;
  final ValueChanged<SplitDirection> onSplit;
  final VoidCallback onSwap;

  const AltOverlay({
    super.key,
    required this.node,
    required this.isSwapSelected,
    required this.onClose,
    required this.onSplit,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Stack(
      children: [
        // 半透明压暗遮罩
        Positioned.fill(child: Container(color: c.scrim)),

        // ── 中央细十字线（60% 长度，两端渐隐）──
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.6,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  c.border.withValues(alpha: 0),
                  c.border,
                  c.border.withValues(alpha: 0),
                ]),
              ),
            ),
          ),
        ),
        Center(
          child: FractionallySizedBox(
            heightFactor: 0.6,
            child: Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.border.withValues(alpha: 0),
                    c.border,
                    c.border.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── 中央浮动操作 chips ──
        Center(
          child: FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionChip(
                  icon: Icons.horizontal_split,
                  label: '水平切分',
                  tooltip: '水平切分',
                  onTap: () => onSplit(SplitDirection.vertical),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.swap_horiz,
                  label: '交换',
                  tooltip: '与其他面板交换',
                  selected: isSwapSelected,
                  onTap: onSwap,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.vertical_split,
                  label: '垂直切分',
                  tooltip: '垂直切分',
                  onTap: () => onSplit(SplitDirection.horizontal),
                ),
              ],
            ),
          ),
        ),

        // ── 左下角提示（低调，不可点击）──
        Positioned(
          left: 8,
          bottom: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
              child: Text(
                '按住 Alt 显示面板操作',
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
        ),

        // ── 右上角关闭 ──
        Positioned(
          top: 4,
          right: 4,
          child: _CloseBtn(onTap: onClose),
        ),
      ],
    );
  }
}

/// 浮动操作 chip：surface 底 + 细边框 + 柔和投影，hover 显 surfaceHover，
/// 交换选中态为 accent 实底
class _ActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;

    final bg = selected
        ? c.accent
        : _hovering
            ? c.surfaceHover
            : c.surface.withValues(alpha: 0.95);
    final fg = selected ? c.onAccent : c.textPrimary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              border: Border.all(color: selected ? c.accent : c.border),
              boxShadow: [
                BoxShadow(
                  color: c.scrim,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: AppMetrics.iconSm, color: fg),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: fg,
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

/// 关闭按钮：默认低调，hover 显 danger 实底（Win11 关闭语义）
class _CloseBtn extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseBtn({required this.onTap});

  @override
  State<_CloseBtn> createState() => _CloseBtnState();
}

class _CloseBtnState extends State<_CloseBtn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: '关闭面板',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _hovering
                  ? c.danger
                  : c.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              border: Border.all(color: _hovering ? c.danger : c.border),
              boxShadow: [
                BoxShadow(
                  color: c.scrim,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.close,
              size: 13,
              color: _hovering ? c.onAccent : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
