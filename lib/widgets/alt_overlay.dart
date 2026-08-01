import 'package:flutter/material.dart';
import '../models/layout_node.dart';
import 'app_theme.dart';

/// Alt 键按下时在每个面板上显示的浮动操作层。
///
/// 设计：操作层是"浮在面板上的一张玻璃片"——
/// - 面板中央一条收敛的细十字线（仅作分割方向暗示，两端渐隐）
/// - 中央胶囊操作簇：水平切分 | 交换 | 垂直切分
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

        // ── 中央胶囊操作簇 ──
        Center(
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
              border: Border.all(color: c.border),
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
                _OverlayBtn(
                  icon: Icons.horizontal_split,
                  tooltip: '水平切分',
                  onTap: () => onSplit(SplitDirection.vertical),
                ),
                _BtnDivider(),
                _OverlayBtn(
                  icon: Icons.swap_horiz,
                  tooltip: '与其他面板交换',
                  selected: isSwapSelected,
                  onTap: onSwap,
                ),
                _BtnDivider(),
                _OverlayBtn(
                  icon: Icons.vertical_split,
                  tooltip: '垂直切分',
                  onTap: () => onSplit(SplitDirection.horizontal),
                ),
              ],
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

class _BtnDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      color: context.colors.border,
    );
  }
}

/// 操作簇内的图标按钮：hover 显 accent，交换选中态为 accent 实底
class _OverlayBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _OverlayBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  State<_OverlayBtn> createState() => _OverlayBtnState();
}

class _OverlayBtnState extends State<_OverlayBtn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.selected || _hovering;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.selected
                  ? c.accent
                  : _hovering
                      ? c.surfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: widget.selected
                  ? Colors.white
                  : active
                      ? c.accent
                      : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 关闭按钮：默认低调，hover 显 danger 实底白图标（Win11 关闭语义）
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
            ),
            child: Icon(
              Icons.close,
              size: 13,
              color: _hovering ? Colors.white : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
