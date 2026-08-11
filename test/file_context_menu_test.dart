import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_group.dart';
import 'package:inf_dir/services/shell_new_service.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/widgets/file_context_menu.dart';

void main() {
  test('item context menu follows Files structure', () {
    var showMoreInvoked = false;
    final items = buildFileItemContextMenuItems(
      onOpen: () {},
      onOpenWith: () {},
      onQuickView: () {},
      onOpenInNewTab: () {},
      onOpenInNewWindow: () {},
      onOpenInNewPane: (_) {},
      onCut: () {},
      onCopy: () {},
      onRename: () {},
      onDelete: () {},
      onPasteShortcut: () {},
      onCopyPath: () {},
      onCreateFolderWithSelection: () {},
      onCreateShortcut: () {},
      compressName: 'report',
      onCompressZip: () {},
      onSendTo: () {},
      onOpenInTerminal: () {},
      onPinToSidebar: () {},
      onProperties: () {},
      onShowMoreOptions: () => showMoreInvoked = true,
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '打开',
      '打开方式',
      '在新标签页中打开',
      '在新窗口中打开',
      '在新窗格中打开',
      '快速查看',
      '剪切',
      '复制',
      '重命名',
      '删除',
      '粘贴快捷方式',
      '复制路径',
      '使用所选内容创建文件夹',
      '创建快捷方式',
      '压缩到',
      '发送到',
      '在 Windows 终端中打开',
      '固定到侧边栏',
      '属性',
      '显示更多选项',
    ]);

    final compress = items.firstWhere((item) => item.label == '压缩到');
    expect(compress.children!.first.label, '创建 report.zip');
    // 7z / 压缩包暂为占位项。
    expect(compress.children![1].onAction, isNull);
    expect(compress.children![2].onAction, isNull);

    expect(items.last.label, '显示更多选项');
    items.last.onAction!();
    expect(showMoreInvoked, isTrue);
  });

  test('item context menu omits unsupported operations', () {
    final items = buildFileItemContextMenuItems(
      onCopyPath: () {},
      onShowMoreOptions: () {},
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '复制路径',
      '显示更多选项',
    ]);
  });

  test('folder context menu reuses view and sort menus', () {
    final items = buildFolderContextMenuItems(
      sortColumn: SortColumn.name,
      sortAscending: true,
      viewMode: PaneViewMode.details,
      groupBy: FileGroupBy.type,
      groupAscending: false,
      canWrite: true,
      canPaste: false,
      canSelectAll: true,
      onSortColumn: (_) {},
      onSortAscending: (_) {},
      onViewMode: (_) {},
      onGroupBy: (_) {},
      onGroupAscending: (_) {},
      onRefresh: () {},
      onCreateFolder: () {},
      onCreateTextFile: () {},
      onPaste: () {},
      onSelectAll: () {},
      onOpenInTerminal: () {},
      onShowMoreOptions: () {},
      onCreateFromTemplate: (_) {},
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '查看',
      '排序方式',
      '分组依据',
      '刷新',
      '新建',
      '粘贴',
      '全选',
      '在 Windows 终端中打开',
      '显示更多选项',
    ]);
    expect(items.first.children, isNotEmpty);
    expect(items[1].children, isNotEmpty);
    expect(items[2].children, isNotEmpty);
    expect(
      items[2].children!.firstWhere((item) => item.label == '类型').checked,
      isTrue,
    );
    expect(
      items[2].children!.firstWhere((item) => item.label == '降序').checked,
      isTrue,
    );
    expect(items.firstWhere((item) => item.label == '粘贴').enabled, isFalse);
    expect(items.last.label, '显示更多选项');
  });

  test('folder context menu hides write actions for virtual folders', () {
    final items = buildFolderContextMenuItems(
      sortColumn: SortColumn.name,
      sortAscending: true,
      viewMode: PaneViewMode.details,
      groupBy: FileGroupBy.none,
      groupAscending: true,
      canWrite: false,
      canPaste: false,
      canSelectAll: false,
      onSortColumn: (_) {},
      onSortAscending: (_) {},
      onViewMode: (_) {},
      onGroupBy: (_) {},
      onGroupAscending: (_) {},
      onRefresh: () {},
      onCreateFolder: () {},
      onCreateTextFile: () {},
      onPaste: () {},
      onSelectAll: () {},
      onShowMoreOptions: () {},
      onCreateFromTemplate: (_) {},
    );

    final labels = items
        .where((item) => !item.isDivider)
        .map((item) => item.label);
    expect(labels, isNot(contains('新建')));
    expect(labels, isNot(contains('粘贴')));
    expect(labels, isNot(contains('在 Windows 终端中打开')));
    expect(items.last.label, '显示更多选项');
  });

  test('folder context menu lists registry-driven new items', () {
    final items = buildFolderContextMenuItems(
      sortColumn: SortColumn.name,
      sortAscending: true,
      viewMode: PaneViewMode.details,
      groupBy: FileGroupBy.none,
      groupAscending: true,
      canWrite: true,
      canPaste: false,
      canSelectAll: true,
      onSortColumn: (_) {},
      onSortAscending: (_) {},
      onViewMode: (_) {},
      onGroupBy: (_) {},
      onGroupAscending: (_) {},
      onRefresh: () {},
      onCreateFolder: () {},
      onCreateTextFile: () {},
      onPaste: () {},
      onSelectAll: () {},
      onShowMoreOptions: () {},
      onCreateFromTemplate: (_) {},
      shellNewEntries: [
        ShellNewEntry(
          extension: '.docx',
          name: 'Word 文档',
          templatePath: '',
          command: '',
          data: Uint8List(0),
          iconPng: Uint8List(0),
        ),
      ],
    );

    final newItem = items.firstWhere((item) => item.label == '新建');
    expect(newItem.children!.map((item) => item.label), [
      '文件夹',
      '文本文档',
      null, // divider
      'Word 文档',
    ]);
    newItem.children!.last.onAction!();
  });
}
