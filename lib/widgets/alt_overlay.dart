import 'package:flutter/material.dart';
import '../models/layout_node.dart';

/// Alt 键按下时在每个面板上显示的浮动操作层
///
/// - 右上角：关闭图标
/// - 中央微弱的十字分割线 + 分割按钮（1/4 位置）
/// - 中央：交换图标（带选中反馈）
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

  // 水平分割（蓝色系）
  static const _splitHLine = Color(0xFF5B9BD5);
  static const _splitHBorder = Color(0xFF4A8AC4);
  static const _splitHIcon = Color(0xFF3A7AB4);

  // 垂直分割（琥珀色系）
  static const _splitVLine = Color(0xFFE8A44A);
  static const _splitVBorder = Color(0xFFD89338);
  static const _splitVIcon = Color(0xFFC88228);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          // 半透明遮罩
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.10)),
          ),

          // ── 十字分割线 ──
          // 水平线（蓝色，2px）
          Positioned(
            left: 0, right: 0,
            top: 0, bottom: 0,
            child: Center(
              child: Container(
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: _splitHLine,
              ),
            ),
          ),
          // 竖直线（琥珀色，2px）
          Positioned(
            left: 0, right: 0,
            top: 0, bottom: 0,
            child: Center(
              child: Container(
                width: 1.5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                color: _splitVLine,
              ),
            ),
          ),

          // ── 水平分割按钮（蓝色，十字线右侧 1/4 处：上下切分）──
          Align(
            alignment: const Alignment(0.45, 0),
            child: _SplitBtn(
              icon: Icons.horizontal_split,
              tooltip: '水平切分',
              borderColor: _splitHBorder,
              iconColor: _splitHIcon,
              onTap: () => onSplit(SplitDirection.vertical),
            ),
          ),

          // ── 垂直分割按钮（琥珀色，十字线下侧 1/4 处：左右切分）──
          Align(
            alignment: const Alignment(0, 0.45),
            child: _SplitBtn(
              icon: Icons.vertical_split,
              tooltip: '垂直切分',
              borderColor: _splitVBorder,
              iconColor: _splitVIcon,
              onTap: () => onSplit(SplitDirection.horizontal),
            ),
          ),

          // ── 右上角关闭 ──
          Positioned(
            top: 2,
            right: 2,
            child: _MiniIconBtn(
              icon: Icons.cancel,
              color: Colors.red.shade400,
              tooltip: '关闭面板',
              onTap: onClose,
            ),
          ),

          // ── 中央交换 ──
          Center(
            child: GestureDetector(
              onTap: onSwap,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSwapSelected
                      ? const Color(0xFF3A8094).withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSwapSelected
                        ? const Color(0xFF3A8094)
                        : const Color(0xFF5A8A9E),
                    width: isSwapSelected ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.swap_horizontal_circle,
                  size: 20,
                  color: isSwapSelected
                      ? const Color(0xFF3A8094)
                      : const Color(0xFF4A8098),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 十字线上的分割按钮
class _SplitBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color borderColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _SplitBtn({
    required this.icon,
    required this.tooltip,
    required this.borderColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
      ),
    );
  }
}

/// 迷你图标按钮（关闭）
class _MiniIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
