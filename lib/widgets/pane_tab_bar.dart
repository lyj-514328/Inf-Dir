import 'package:flutter/material.dart';
import '../state/pane_controller.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import 'app_theme.dart';

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
    final c = context.colors;
    return Container(
      height: AppMetrics.paneTabBarHeight,
      color: c.surfaceSubtle,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length + 1,
              itemExtent: null,
              itemBuilder: (context, index) {
                if (index == tabs.length) {
                  return InkWell(
                    onTap: onAddTab,
                    child: SizedBox(
                      width: 24,
                      height: AppMetrics.paneTabBarHeight,
                      child: Icon(
                        Icons.add,
                        size: AppMetrics.iconSm,
                        color: c.textSecondary,
                      ),
                    ),
                  );
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
    final iconBytes = FileService.isHomePath(widget.path)
        ? null
        : IconService.getFileIconPng(widget.path, true, 16);
    final iconWidget = FileService.isHomePath(widget.path)
        ? Icon(Icons.home, size: AppMetrics.iconSm, color: c.textSecondary)
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

    final BoxDecoration decoration;
    if (isActive) {
      decoration = BoxDecoration(
        color: bgColor,
        border: Border.all(color: c.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(AppMetrics.tabRadius),
      );
    } else {
      decoration = BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: c.border, width: 0.5)),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveringTab = true),
      onExit: (_) => setState(() => _hoveringTab = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
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
                MouseRegion(
                  onEnter: (_) => setState(() => _hoveringClose = true),
                  onExit: (_) => setState(() => _hoveringClose = false),
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: _hoveringClose ? c.danger : c.textTertiary,
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
