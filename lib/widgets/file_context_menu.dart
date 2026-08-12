import 'package:flutter/material.dart';

import '../models/file_group.dart';
import '../models/layout_node.dart';
import '../services/shell_new_service.dart';
import '../state/pane_controller.dart';
import 'command_menu.dart';

List<CommandMenuItem> _joinSections(List<List<CommandMenuItem>> sections) {
  final result = <CommandMenuItem>[];
  for (final section in sections) {
    if (section.isEmpty) continue;
    if (result.isNotEmpty) result.add(const CommandMenuItem.divider());
    result.addAll(section);
  }
  return result;
}

List<CommandMenuItem> buildFileItemContextMenuItems({
  VoidCallback? onOpen,
  ImageProvider<Object>? openImage,
  VoidCallback? onOpenWith,
  List<CommandMenuItem>? openWithChildren,
  VoidCallback? onQuickView,
  VoidCallback? onOpenInNewTab,
  VoidCallback? onOpenInNewWindow,
  ValueChanged<SplitDirection>? onOpenInNewPane,
  VoidCallback? onCut,
  VoidCallback? onCopy,
  VoidCallback? onRename,
  VoidCallback? onDelete,
  VoidCallback? onPasteShortcut,
  required VoidCallback onCopyPath,
  VoidCallback? onCreateFolderWithSelection,
  VoidCallback? onCreateShortcut,
  String? compressName,
  VoidCallback? onCompressZip,
  VoidCallback? onSendTo,
  VoidCallback? onOpenInTerminal,
  VoidCallback? onPinToSidebar,
  VoidCallback? onProperties,
  required VoidCallback onShowMoreOptions,
}) {
  final openItems = <CommandMenuItem>[
    if (onOpen != null)
      CommandMenuItem(
        icon: openImage == null ? Icons.launch : null,
        image: openImage,
        label: '打开',
        shortcut: 'Enter',
        onAction: onOpen,
      ),
    if (onOpenWith != null)
      CommandMenuItem(
        icon: Icons.open_with,
        label: '打开方式',
        children: openWithChildren,
        onAction: onOpenWith,
      ),
    if (onOpenInNewTab != null)
      CommandMenuItem(
        icon: Icons.tab,
        label: '在新标签页中打开',
        onAction: onOpenInNewTab,
      ),
    if (onOpenInNewWindow != null)
      CommandMenuItem(
        icon: Icons.open_in_new,
        label: '在新窗口中打开',
        onAction: onOpenInNewWindow,
      ),
    if (onOpenInNewPane != null)
      CommandMenuItem(
        icon: Icons.splitscreen,
        label: '在新窗格中打开',
        children: [
          CommandMenuItem(
            label: '垂直分割',
            onAction: () => onOpenInNewPane(SplitDirection.vertical),
          ),
          CommandMenuItem(
            label: '水平分割',
            onAction: () => onOpenInNewPane(SplitDirection.horizontal),
          ),
        ],
      ),
    if (onQuickView != null)
      CommandMenuItem(
        icon: Icons.visibility_outlined,
        label: '快速查看',
        shortcut: 'F3',
        onAction: onQuickView,
      ),
  ];

  final editItems = <CommandMenuItem>[
    if (onCut != null)
      CommandMenuItem(
        icon: Icons.content_cut,
        label: '剪切',
        shortcut: 'Ctrl+X',
        onAction: onCut,
      ),
    if (onCopy != null)
      CommandMenuItem(
        icon: Icons.content_copy,
        label: '复制',
        shortcut: 'Ctrl+C',
        onAction: onCopy,
      ),
    if (onRename != null)
      CommandMenuItem(
        icon: Icons.drive_file_rename_outline,
        label: '重命名',
        shortcut: 'F2',
        onAction: onRename,
      ),
    if (onDelete != null)
      CommandMenuItem(
        icon: Icons.delete_outline,
        label: '删除',
        shortcut: 'Delete',
        onAction: onDelete,
      ),
  ];

  final extraItems = <CommandMenuItem>[
    if (onPasteShortcut != null)
      CommandMenuItem(
        icon: Icons.content_paste,
        label: '粘贴快捷方式',
        onAction: onPasteShortcut,
      ),
    CommandMenuItem(
      icon: Icons.link,
      label: '复制路径',
      shortcut: 'Ctrl+Shift+C',
      onAction: onCopyPath,
    ),
    if (onCreateFolderWithSelection != null)
      CommandMenuItem(
        icon: Icons.create_new_folder_outlined,
        label: '使用所选内容创建文件夹',
        onAction: onCreateFolderWithSelection,
      ),
    if (onCreateShortcut != null)
      CommandMenuItem(
        icon: Icons.add_link,
        label: '创建快捷方式',
        onAction: onCreateShortcut,
      ),
    if (compressName != null)
      CommandMenuItem(
        icon: Icons.folder_zip_outlined,
        label: '压缩到',
        children: [
          CommandMenuItem(
            label: '创建 $compressName.zip',
            onAction: onCompressZip,
          ),
          CommandMenuItem(label: '创建 $compressName.7z'),
          CommandMenuItem(label: '创建压缩包'),
        ],
      ),
    if (onSendTo != null)
      CommandMenuItem(
        icon: Icons.send_outlined,
        label: '发送到',
        onAction: onSendTo,
      ),
  ];

  final tailItems = <CommandMenuItem>[
    if (onOpenInTerminal != null)
      CommandMenuItem(
        icon: Icons.terminal,
        label: '在 Windows 终端中打开',
        onAction: onOpenInTerminal,
      ),
    if (onPinToSidebar != null)
      CommandMenuItem(
        icon: Icons.push_pin_outlined,
        label: '固定到侧边栏',
        onAction: onPinToSidebar,
      ),
    if (onProperties != null)
      CommandMenuItem(
        icon: Icons.info_outline,
        label: '属性',
        onAction: onProperties,
      ),
  ];

  return _joinSections([
    openItems,
    editItems,
    extraItems,
    tailItems,
    [
      CommandMenuItem(
        icon: Icons.more_horiz,
        label: '显示更多选项',
        shortcut: 'Shift+F10',
        onAction: onShowMoreOptions,
      ),
    ],
  ]);
}

List<CommandMenuItem> buildFolderContextMenuItems({
  required SortColumn sortColumn,
  required bool sortAscending,
  required PaneViewMode viewMode,
  required FileGroupBy groupBy,
  required bool groupAscending,
  required bool canWrite,
  required bool canPaste,
  required bool canSelectAll,
  required ValueChanged<SortColumn> onSortColumn,
  required ValueChanged<bool> onSortAscending,
  required ValueChanged<PaneViewMode> onViewMode,
  required ValueChanged<FileGroupBy> onGroupBy,
  required ValueChanged<bool> onGroupAscending,
  required VoidCallback onRefresh,
  required VoidCallback onCreateFolder,
  required VoidCallback onCreateFile,
  required VoidCallback onCreateShortcut,
  required VoidCallback onPaste,
  required VoidCallback onSelectAll,
  VoidCallback? onOpenInTerminal,
  required VoidCallback onShowMoreOptions,
  List<ShellNewEntry> shellNewEntries = const [],
  required ValueChanged<ShellNewEntry> onCreateFromTemplate,
}) {
  final sharedConfig = ViewSortMenuConfig(
    sortColumn: sortColumn,
    sortAscending: sortAscending,
    viewMode: viewMode,
    onSortColumn: onSortColumn,
    onSortAscending: onSortAscending,
    onViewMode: onViewMode,
  );

  final writeItems = <CommandMenuItem>[
    if (canWrite) ...[
      CommandMenuItem(
        icon: Icons.add,
        label: '新建',
        children: buildNewItemMenuItems(
          onCreateFolder: onCreateFolder,
          onCreateFile: onCreateFile,
          onCreateShortcut: onCreateShortcut,
          shellNewEntries: shellNewEntries,
          onCreateFromTemplate: onCreateFromTemplate,
        ),
      ),
      CommandMenuItem(
        icon: Icons.content_paste,
        label: '粘贴',
        shortcut: 'Ctrl+V',
        enabled: canPaste,
        onAction: onPaste,
      ),
    ],
  ];

  final selectionItems = <CommandMenuItem>[
    CommandMenuItem(
      icon: Icons.select_all,
      label: '全选',
      shortcut: 'Ctrl+A',
      enabled: canSelectAll,
      onAction: onSelectAll,
    ),
    if (onOpenInTerminal != null)
      CommandMenuItem(
        icon: Icons.terminal,
        label: '在 Windows 终端中打开',
        onAction: onOpenInTerminal,
      ),
  ];

  return _joinSections([
    [
      buildViewCommandMenuItem(sharedConfig),
      buildSortCommandMenuItem(sharedConfig, label: '排序方式'),
      _buildGroupByMenuItem(
        groupBy: groupBy,
        groupAscending: groupAscending,
        onGroupBy: onGroupBy,
        onGroupAscending: onGroupAscending,
      ),
      CommandMenuItem(
        icon: Icons.refresh,
        label: '刷新',
        shortcut: 'F5',
        onAction: onRefresh,
      ),
    ],
    writeItems,
    selectionItems,
    [
      CommandMenuItem(
        icon: Icons.more_horiz,
        label: '显示更多选项',
        shortcut: 'Shift+F10',
        onAction: onShowMoreOptions,
      ),
    ],
  ]);
}

CommandMenuItem _buildGroupByMenuItem({
  required FileGroupBy groupBy,
  required bool groupAscending,
  required ValueChanged<FileGroupBy> onGroupBy,
  required ValueChanged<bool> onGroupAscending,
}) {
  CommandMenuItem option(String label, FileGroupBy value) {
    return CommandMenuItem(
      label: label,
      checked: groupBy == value,
      onAction: () => onGroupBy(value),
    );
  }

  final groupingEnabled = groupBy != FileGroupBy.none;
  return CommandMenuItem(
    icon: Icons.view_agenda_outlined,
    label: '分组依据',
    children: [
      option('无', FileGroupBy.none),
      const CommandMenuItem.divider(),
      option('名称', FileGroupBy.name),
      option('修改日期', FileGroupBy.dateModified),
      option('类型', FileGroupBy.type),
      option('大小', FileGroupBy.size),
      const CommandMenuItem.divider(),
      CommandMenuItem(
        label: '升序',
        checked: groupingEnabled && groupAscending,
        enabled: groupingEnabled,
        onAction: () => onGroupAscending(true),
      ),
      CommandMenuItem(
        label: '降序',
        checked: groupingEnabled && !groupAscending,
        enabled: groupingEnabled,
        onAction: () => onGroupAscending(false),
      ),
    ],
  );
}
