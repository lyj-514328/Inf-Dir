import 'package:flutter/material.dart';
import '../state/pane_controller.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import 'app_theme.dart';
import 'home_icon.dart';

class PaneTabBar extends StatelessWidget {
  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onAddTab;

  const PaneTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSwitchTab,
    required this.onCloseTab,
    required this.onAddTab,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.paneTabBarHeight,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(3, 0, 4, 0),
              itemCount: tabs.length + 1,
              itemExtent: null,
              itemBuilder: (context, index) {
                if (index == tabs.length) {
                  return _AddTabButton(onTap: onAddTab);
                }
                final isActive = index == activeIndex;
                return _TabItem(
                  label: tabs[index].label,
                  path: tabs[index].path,
                  isActive: isActive,
                  onTap: () => onSwitchTab(index),
                  onClose: () => onCloseTab(index),
                  showClose: tabs.length > 1,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTabButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddTabButton({required this.onTap});

  @override
  State<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<_AddTabButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 24,
          height: 22,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: _hovering ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: Icon(
            Icons.add,
            size: AppMetrics.iconSm,
            color: c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final String path;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final bool showClose;

  const _TabItem({
    required this.label,
    required this.path,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.showClose,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hoveringTab = false;
  bool _hoveringClose = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sourceSize =
        (AppMetrics.iconSm * View.of(context).devicePixelRatio).ceil();
    final iconBytes = FileService.isHomePath(widget.path)
        ? null
        : IconService.getFileIconPng(widget.path, true, sourceSize);
    final iconWidget = FileService.isHomePath(widget.path)
        ? const HomeIcon(size: AppMetrics.iconSm)
        : iconBytes != null
        ? Image.memory(
            iconBytes,
            width: AppMetrics.iconSm,
            height: AppMetrics.iconSm,
            gaplessPlayback: true,
          )
        : Icon(Icons.folder, size: AppMetrics.iconSm, color: c.iconFolder);

    final isActive = widget.isActive;
    final Color bgColor = isActive
        ? c.surface
        : _hoveringTab
        ? c.surfaceHover
        : Colors.transparent;

    final decoration = BoxDecoration(
      color: bgColor,
      border: isActive ? Border.all(color: c.border, width: 1) : null,
      borderRadius: BorderRadius.circular(AppMetrics.tabRadius),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveringTab = true),
      onExit: (_) => setState(() => _hoveringTab = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: decoration,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: AppMetrics.iconSm,
                height: AppMetrics.iconSm,
                child: iconWidget,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: isActive ? c.textPrimary : c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.showClose) ...[
                const SizedBox(width: 4),
                Opacity(
                  // 关闭按钮仅 hover 时可见，占位避免布局抖动
                  opacity: _hoveringTab ? 1 : 0,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hoveringClose = true),
                    onExit: (_) => setState(() => _hoveringClose = false),
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Icon(
                        Icons.close,
                        size: AppMetrics.iconSm,
                        color: _hoveringClose ? c.danger : c.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
