import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';

/// 无边框窗口的自定义标题栏按钮：最小化 / 最大化-还原 / 关闭。
/// 通过 [WindowListener] 跟踪最大化状态以切换还原图标。
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted && value != _isMaximized) {
        setState(() => _isMaximized = value);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: Icons.remove,
          tooltip: '最小化',
          onTap: windowManager.minimize,
        ),
        _CaptionButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          tooltip: _isMaximized ? '还原' : '最大化',
          onTap: () => _isMaximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        _CaptionButton(
          icon: Icons.close,
          tooltip: '关闭',
          danger: true,
          onTap: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// 关闭按钮：hover 时 danger 底 + onAccent 图标。
  final bool danger;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = _hovering
        ? (widget.danger ? c.danger : c.surfaceHover)
        : Colors.transparent;
    final iconColor = widget.danger && _hovering
        ? c.onAccent
        : c.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            // 直角贴边：最大化时按钮命中区域须触达屏幕边缘。
            width: 46,
            height: AppMetrics.topBarHeight,
            color: bg,
            child: Icon(widget.icon, size: AppMetrics.iconMd, color: iconColor),
          ),
        ),
      ),
    );
  }
}
