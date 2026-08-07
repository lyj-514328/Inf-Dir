import 'package:flutter/material.dart';

import 'app_theme.dart';

class NavToolbar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;
  final bool commandMenuActive;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final VoidCallback onRefresh;
  final ValueChanged<Offset> onCommandMenu;

  const NavToolbar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    this.commandMenuActive = false,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onRefresh,
    required this.onCommandMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavButton(
          icon: Icons.arrow_back,
          tooltip: '后退',
          enabled: canGoBack,
          onPressed: onBack,
        ),
        _NavButton(
          icon: Icons.arrow_forward,
          tooltip: '前进',
          enabled: canGoForward,
          onPressed: onForward,
        ),
        _NavButton(
          icon: Icons.arrow_upward,
          tooltip: '上级',
          enabled: canGoUp,
          onPressed: onUp,
        ),
        _NavButton(
          icon: Icons.refresh,
          tooltip: '刷新',
          enabled: true,
          onPressed: onRefresh,
        ),
        Builder(
          builder: (btnContext) => _NavButton(
            icon: Icons.keyboard_command_key,
            tooltip: '命令',
            enabled: true,
            active: commandMenuActive,
            onPressed: () {
              final box = btnContext.findRenderObject()! as RenderBox;
              onCommandMenu(
                box.localToGlobal(Offset(0, box.size.height + 2)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final bool active;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = !enabled
        ? c.textTertiary
        : active
        ? c.accent
        : c.textSecondary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        hoverColor: c.surfaceHover,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: AppMetrics.iconMd, color: color),
        ),
      ),
    );
  }
}
