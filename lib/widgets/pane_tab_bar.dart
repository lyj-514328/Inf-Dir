import 'package:flutter/material.dart';
import '../state/pane_controller.dart';
import '../services/icon_service.dart';

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
    return Container(
      height: 26,
      color: const Color(0xFFE8E8E8),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemExtent: null,
              itemBuilder: (context, index) {
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
          InkWell(
            onTap: onAddTab,
            child: const SizedBox(
              width: 24,
              height: 26,
              child: Icon(Icons.add, size: 14, color: Color(0xFF666666)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final iconBytes = IconService.getFileIconPng(path, true, 16);
    final iconWidget = iconBytes != null
        ? Image.memory(iconBytes, width: 14, height: 14, gaplessPlayback: true)
        : Icon(Icons.folder, size: 14, color: Colors.amber.shade700);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xFFE8E8E8),
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.white : const Color(0xFFD0D0D0),
              width: 1,
            ),
            right: const BorderSide(color: Color(0xFFD0D0D0), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: iconWidget),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? const Color(0xFF1A1A1A) : const Color(0xFF666666),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showClose) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 12, color: Color(0xFF999999)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
