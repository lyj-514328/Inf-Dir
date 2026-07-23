import 'package:flutter/material.dart';

class NavToolbar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final VoidCallback onHome;
  final VoidCallback onRefresh;

  const NavToolbar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onHome,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
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
            icon: Icons.home,
            tooltip: '主页',
            enabled: true,
            onPressed: onHome,
          ),
          _NavButton(
            icon: Icons.refresh,
            tooltip: '刷新',
            enabled: true,
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? const Color(0xFF444444) : const Color(0xFFBBBBBB),
          ),
        ),
      ),
    );
  }
}
