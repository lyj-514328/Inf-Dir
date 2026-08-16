import 'package:flutter/material.dart';

import 'command_menu.dart';

/// 标签页右键菜单。「关闭全部」的语义由调用方决定（pane 数大于 1 时
/// 关整个 pane，否则降级为关闭其他），此处只消费回调。
List<CommandMenuItem> buildTabContextMenuItems({
  required VoidCallback onNewTab,
  required VoidCallback onDuplicateTab,
  required bool canClose,
  required VoidCallback onCloseTab,
  required VoidCallback onCloseOtherTabs,
  required VoidCallback onCloseTabsToTheLeft,
  required VoidCallback onCloseTabsToTheRight,
  required VoidCallback onCloseAllTabs,
  required bool canRestoreClosedTab,
  required VoidCallback onRestoreClosedTab,
}) {
  return [
    CommandMenuItem(
      icon: Icons.add,
      label: '新建标签页',
      shortcut: 'Ctrl+T',
      onAction: onNewTab,
    ),
    CommandMenuItem(
      icon: Icons.copy_all_outlined,
      label: '复制标签页',
      onAction: onDuplicateTab,
    ),
    const CommandMenuItem.divider(),
    CommandMenuItem(
      icon: Icons.close,
      label: '关闭',
      shortcut: 'Ctrl+W',
      enabled: canClose,
      onAction: canClose ? onCloseTab : null,
    ),
    CommandMenuItem(
      label: '关闭其他标签页',
      enabled: canClose,
      onAction: canClose ? onCloseOtherTabs : null,
    ),
    CommandMenuItem(
      label: '关闭左侧标签页',
      enabled: canClose,
      onAction: canClose ? onCloseTabsToTheLeft : null,
    ),
    CommandMenuItem(
      label: '关闭右侧标签页',
      enabled: canClose,
      onAction: canClose ? onCloseTabsToTheRight : null,
    ),
    CommandMenuItem(
      label: '关闭全部标签页',
      enabled: canClose,
      onAction: canClose ? onCloseAllTabs : null,
    ),
    const CommandMenuItem.divider(),
    CommandMenuItem(
      icon: Icons.history,
      label: '恢复最近关闭的标签页',
      shortcut: 'Ctrl+Shift+T',
      enabled: canRestoreClosedTab,
      onAction: canRestoreClosedTab ? onRestoreClosedTab : null,
    ),
  ];
}
