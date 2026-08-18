import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_group.dart';
import 'package:inf_dir/services/shell_new_service.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/widgets/file_context_menu.dart';
import 'package:inf_dir/widgets/command_menu.dart';

void main() {
  test('item context menu follows implemented Files structure', () {
    var showMoreInvoked = false;
    final openImage = MemoryImage(Uint8List.fromList([1, 2, 3]));
    final items = buildFileItemContextMenuItems(
      onOpen: () {},
      openImage: openImage,
      onOpenWith: () {},
      openWithChildren: [CommandMenuItem(label: 'Notepad', onAction: () {})],
      onQuickView: () {},
      onOpenInNewTab: () {},
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
      onCompress7z: () {},
      onProperties: () {},
      onShowMoreOptions: () => showMoreInvoked = true,
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '打开',
      '打开方式',
      '在新标签页中打开',
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
      '压缩',
      '属性',
      '显示更多选项',
    ]);

    final compress = items.firstWhere((item) => item.label == '压缩');
    expect(compress.children!.map((item) => item.label), [
      '创建 report.zip',
      '创建 report.7z',
    ]);
    expect(
      _enabledLeaves(items).every((item) => item.onAction != null),
      isTrue,
    );

    final openWith = items.firstWhere((item) => item.label == '打开方式');
    expect(openWith.children!.single.label, 'Notepad');

    final open = items.firstWhere((item) => item.label == '打开');
    expect(open.image, same(openImage));
    expect(open.icon, isNull);

    expect(items.last.label, '显示更多选项');
    items.last.onAction!();
    expect(showMoreInvoked, isTrue);
  });

  test('directory opener items lead the open section', () {
    var opened = false;
    final items = buildFileItemContextMenuItems(
      directoryOpenerItems: [
        CommandMenuItem(
          label: '用 Visual Studio Code 打开',
          onAction: () => opened = true,
        ),
      ],
      onOpenInNewTab: () {},
      onCopyPath: () {},
      onShowMoreOptions: () {},
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '用 Visual Studio Code 打开',
      '在新标签页中打开',
      '复制路径',
      '显示更多选项',
    ]);
    items.first.onAction!();
    expect(opened, isTrue);
  });

  test('folder background menu lists directory openers first', () {
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
      onCreateFile: () {},
      onCreateShortcut: () {},
      onPaste: () {},
      onSelectAll: () {},
      onShowMoreOptions: () {},
      onCreateFromTemplate: (_) {},
      directoryOpenerItems: [
        CommandMenuItem(label: '用 Visual Studio Code 打开', onAction: () {}),
      ],
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '用 Visual Studio Code 打开',
      '查看',
      '排序方式',
      '分组依据',
      '刷新',
      '新建',
      '粘贴',
      '全选',
      '显示更多选项',
    ]);
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

  test('item context menu hides compression without an implementation', () {
    final items = buildFileItemContextMenuItems(
      onCopyPath: () {},
      compressName: 'report',
      onShowMoreOptions: () {},
    );

    expect(items.map((item) => item.label), isNot(contains('压缩')));
  });

  test('item context menu exposes archive dialog and extract actions', () {
    final items = buildFileItemContextMenuItems(
      onCopyPath: () {},
      compressName: 'report',
      onCompressZip: () {},
      onCompress7z: () {},
      onCompressDialog: () {},
      onExtractFiles: () {},
      onExtractHere: () {},
      onExtractToFolder: () {},
      extractName: 'report',
      onShowMoreOptions: () {},
    );

    final compress = items.firstWhere((item) => item.label == '压缩');
    expect(compress.children!.map((item) => item.label), [
      '创建压缩包…',
      '创建 report.zip',
      '创建 report.7z',
    ]);

    final extract = items.firstWhere((item) => item.label == '解压');
    expect(extract.children!.map((item) => item.label), [
      '解压文件…',
      '解压到当前文件夹',
      '解压到 report',
    ]);

    final noExtract = buildFileItemContextMenuItems(
      onCopyPath: () {},
      compressName: 'report',
      onCompressZip: () {},
      onShowMoreOptions: () {},
    );
    expect(noExtract.map((item) => item.label), isNot(contains('解压')));
  });

  test('recycle bin item menu exposes only supported operations', () {
    var restored = false;
    var deleted = false;
    final items = buildRecycleBinItemContextMenuItems(
      onRestore: () => restored = true,
      onDeletePermanently: () => deleted = true,
      onProperties: () {},
      onShowMoreOptions: () {},
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '还原',
      '永久删除',
      '属性',
      '显示更多选项',
    ]);

    items.firstWhere((item) => item.label == '还原').onAction!();
    items.firstWhere((item) => item.label == '永久删除').onAction!();
    expect(restored, isTrue);
    expect(deleted, isTrue);
  });

  test('recycle bin folder menu disables empty action when empty', () {
    final items = buildRecycleBinFolderContextMenuItems(
      sortColumn: SortColumn.name,
      sortAscending: true,
      viewMode: PaneViewMode.details,
      groupBy: FileGroupBy.none,
      groupAscending: true,
      canSelectAll: false,
      canEmpty: false,
      canRestoreAll: false,
      onSortColumn: (_) {},
      onSortAscending: (_) {},
      onViewMode: (_) {},
      onGroupBy: (_) {},
      onGroupAscending: (_) {},
      onRefresh: () {},
      onRestoreAll: () {},
      onEmptyRecycleBin: () {},
      onSelectAll: () {},
      onShowMoreOptions: () {},
    );

    expect(items.where((item) => !item.isDivider).map((item) => item.label), [
      '查看',
      '排序方式',
      '分组依据',
      '刷新',
      '全部还原',
      '全选',
      '清空回收站',
      '显示更多选项',
    ]);
    expect(items.firstWhere((item) => item.label == '清空回收站').enabled, isFalse);
    expect(items.firstWhere((item) => item.label == '全选').enabled, isFalse);
    expect(items.firstWhere((item) => item.label == '全部还原').enabled, isFalse);
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
      onCreateFile: () {},
      onCreateShortcut: () {},
      onPaste: () {},
      onSelectAll: () {},
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
      onCreateFile: () {},
      onCreateShortcut: () {},
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
      onCreateFile: () {},
      onCreateShortcut: () {},
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
        ShellNewEntry(
          extension: '.xlsx',
          name: 'Excel 工作表',
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
      '文件',
      '快捷方式',
      null, // divider
      'Word 文档',
      'Excel 工作表',
    ]);
    newItem.children!.last.onAction!();
  });
}

Iterable<CommandMenuItem> _enabledLeaves(List<CommandMenuItem> items) sync* {
  for (final item in items) {
    if (item.isDivider || !item.enabled) continue;
    final children = item.children;
    if (children == null) {
      yield item;
    } else {
      yield* _enabledLeaves(children);
    }
  }
}
