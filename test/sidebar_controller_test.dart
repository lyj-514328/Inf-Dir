import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/cloud_drive_service.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/sidebar_controller.dart';
import 'package:inf_dir/utils/path_utils.dart';

import 'fakes.dart';

SidebarSyncController makeController(
  FakeCursorSource source,
  ManualPump pump, {
  List<String> driveRoots = const ['C:\\'],
  List<CloudDrive> cloudDrives = const [],
  ValueListenable<ActivePaneLocation?>? activeLocation,
}) {
  final repo = DirectoryRepository(
    cursorFactory: source.open,
    yieldFrame: pump.yieldFrame,
    hasChildrenProbe: (_) => true,
  );
  return SidebarSyncController(
    repository: repo,
    activeLocation: activeLocation,
    quickAccessItems: const [],
    driveRoots: driveRoots,
    cloudDrives: cloudDrives,
    probeDriveChildren: false,
  );
}

void main() {
  group('SidebarSyncController', () {
    test('syncTo 展开路径链并加载 children', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\Users', hasChildren: true)],
          null,
        ],
        'C:\\Users': [
          [dirEntry('C:\\Users\\Alice')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      controller.syncTo('C:\\Users\\Alice');
      await runToIdle(pump);

      expect(controller.selectedPath, 'C:\\Users\\Alice');
      expect(controller.isExpanded('C:\\'), isTrue);
      expect(controller.isExpanded('C:\\Users'), isTrue);
      expect(controller.childrenFor('C:\\').single.name, 'Users');
      expect(controller.childrenFor('C:\\Users').single.name, 'Alice');
      expect(controller.isLoading('C:\\'), isFalse);
      controller.dispose();
    });

    test('同一轮事件的重复 syncTo 用 microtask 合并，只提交最后一个', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\Users', hasChildren: true)],
          null,
        ],
        'C:\\Users': [
          [dirEntry('C:\\Users\\Alice')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      controller.syncTo('C:\\');
      controller.syncTo('C:\\Users');
      controller.syncTo('C:\\Users\\Alice');
      await runToIdle(pump);

      expect(controller.selectedPath, 'C:\\Users\\Alice');
      // 只为最后一轮开了 cursor：c:\ 与 c:\users
      expect(source.created.length, 2);
      controller.dispose();
    });

    test('取消同步：partial 卸载、loading 移除、自动展开回滚、手动展开保留', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\A', hasChildren: true)],
          null,
        ],
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          [dirEntry('C:\\A\\a2')],
          null,
        ],
        'C:\\B': [
          [dirEntry('C:\\B\\b1')],
          null,
        ],
        'C:\\Manual': [
          [dirEntry('C:\\Manual\\m1')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      // 用户手动展开一个节点（不随同步回滚）
      controller.toggleExpand('C:\\Manual');
      await runToIdle(pump);
      expect(
        controller.userExpandedPaths.contains(normPath('C:\\Manual')),
        isTrue,
      );

      // 同步到 A 深处，让 c:\a 处于 partial 状态
      controller.syncTo('C:\\A\\a1');
      await settle(); // microtask: startSync + 链开始
      pump.pumpAll(); // c:\ 第一页
      await settle();
      pump.pumpAll(); // c:\ 完成 / c:\a 第一页
      await settle();
      expect(controller.syncExpandedPaths.isNotEmpty, isTrue);

      // 快速切到 B：取消 A 的同步
      controller.syncTo('C:\\B');
      await runToIdle(pump);

      // partial 与自动展开已回滚
      expect(controller.partialNodes, isEmpty);
      expect(
        controller.syncExpandedPaths.where(
          (p) => p != normPath('C:\\') && p != normPath('C:\\B'),
        ),
        isEmpty,
      );
      // 手动展开保留
      expect(
        controller.userExpandedPaths.contains(normPath('C:\\Manual')),
        isTrue,
      );
      expect(controller.isExpanded('C:\\Manual'), isTrue);
      // B 的链已加载
      expect(controller.selectedPath, 'C:\\B');
      controller.dispose();
    });

    test('旧 request 的 partial 不覆盖新 request 接管的节点', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\A', hasChildren: true)],
          null,
        ],
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      controller.syncTo('C:\\A');
      await settle();
      pump.pumpAll();
      await settle();
      // c:\ 已完成，c:\a 挂起在第一页前
      final firstPartialOwner =
          controller.partialNodes[normPath('C:\\A')]?.loadId;

      controller.syncTo('C:\\A'); // 再次同步同一路径 → 新 request
      await runToIdle(pump);

      // c:\ 命中 complete cache，c:\a 由新 request 重新加载
      expect(controller.selectedPath, 'C:\\A');
      expect(controller.childrenFor('C:\\A').single.name, 'a1');
      final owner = controller.partialNodes[normPath('C:\\A')];
      if (firstPartialOwner != null && owner != null) {
        expect(owner.loadId, isNot(firstPartialOwner));
      }
      controller.dispose();
    });

    test('complete cache 可被后续 request 安全复用', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\A', hasChildren: true)],
          null,
        ],
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      controller.syncTo('C:\\A');
      await runToIdle(pump);
      final cursorsAfterFirst = source.created.length;

      // 切走再切回
      controller.syncTo(SidebarSyncController.thisPcGuid);
      await settle();
      controller.syncTo('C:\\A');
      await runToIdle(pump);

      expect(controller.childrenFor('C:\\A').single.name, 'a1');
      expect(source.created.length, cursorsAfterFirst); // 全部命中 cache
      controller.dispose();
    });

    test('dispose 时仍有 page task：cursor 关闭、不再 notify', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\A', hasChildren: true)],
          [dirEntry('C:\\B')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.syncTo('C:\\A');
      await settle();
      pump.pump(); // 翻过第一页后挂起
      await settle();
      final cursor = source.last;
      expect(cursor.isOpen, isTrue);
      final countBeforeDispose = notifyCount;

      controller.dispose();
      expect(cursor.isOpen, isFalse);

      // 放行后续帧：旧循环恢复，但不得再 notify / 不得再翻页
      pump.pumpAll();
      await settle();
      expect(notifyCount, countBeforeDispose);
      expect(cursor.nextPageCalls, 1);
    });

    test('用户收起手动展开的节点会取消其加载任务', () async {
      final source = FakeCursorSource({
        'C:\\M': [
          [dirEntry('C:\\M\\m1')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(source, pump);

      controller.toggleExpand('C:\\M');
      await settle();
      final cursor = source.last;
      controller.toggleExpand('C:\\M'); // 收起
      expect(cursor.isOpen, isFalse);
      expect(controller.isExpanded('C:\\M'), isFalse);
      expect(controller.partialNodes, isEmpty);
      await runToIdle(pump);
      controller.dispose();
    });
  });

  test('活动 Pane 位置流驱动 Sidebar reveal', () async {
    final source = FakeCursorSource({
      'C:\\': [
        [dirEntry('C:\\A', hasChildren: true)],
        null,
      ],
      'C:\\A': [
        [dirEntry('C:\\A\\a1')],
        null,
      ],
    });
    final pump = ManualPump();
    final location = ValueNotifier<ActivePaneLocation?>(null);
    final controller = makeController(source, pump, activeLocation: location);

    location.value = const ActivePaneLocation(paneId: 'pane_0', path: 'C:\\A');
    await runToIdle(pump);

    expect(controller.selectedPath, 'C:\\A');
    expect(controller.isExpanded('C:\\A'), isTrue);
    expect(controller.childrenFor('C:\\A').single.name, 'a1');

    controller.dispose();
    location.dispose();
  });

  test('同步 reveal 取消不会关闭手动展开仍持有的同路径 lease', () async {
    final source = FakeCursorSource({
      'C:\\': [
        [dirEntry('C:\\A', hasChildren: true)],
        null,
      ],
      'C:\\A': [
        [dirEntry('C:\\A\\a1')],
        [dirEntry('C:\\A\\a2')],
        null,
      ],
      'C:\\B': [
        [dirEntry('C:\\B\\b1')],
        null,
      ],
    });
    final pump = ManualPump();
    final controller = makeController(source, pump);

    controller.toggleExpand('C:\\A');
    await settle();
    pump.pump();
    await settle();
    final manualCursor = source.last;
    expect(manualCursor.nextPageCalls, 1);

    controller.syncTo('C:\\A');
    await settle();
    pump.pumpAll();
    await settle();

    controller.syncTo('C:\\B');
    await runToIdle(pump);

    expect(controller.userExpandedPaths.contains(normPath('C:\\A')), isTrue);
    expect(controller.childrenFor('C:\\A').map((e) => e.name), ['a1', 'a2']);
    expect(manualCursor.isOpen, isFalse);
    controller.dispose();
  });

  group('SidebarSyncController 云盘节点', () {
    test('syncTo 云盘内路径展开云盘节点链，不打扰驱动器链', () async {
      final source = FakeCursorSource({
        'C:\\Users\\Alice\\OneDrive': [
          [dirEntry('C:\\Users\\Alice\\OneDrive\\Docs', hasChildren: true)],
          null,
        ],
        'C:\\Users\\Alice\\OneDrive\\Docs': [
          [dirEntry('C:\\Users\\Alice\\OneDrive\\Docs\\a')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(
        source,
        pump,
        cloudDrives: const [
          CloudDrive('OneDrive', 'C:\\Users\\Alice\\OneDrive'),
        ],
      );

      controller.syncTo('C:\\Users\\Alice\\OneDrive\\Docs');
      await runToIdle(pump);

      expect(controller.selectedPath, 'C:\\Users\\Alice\\OneDrive\\Docs');
      expect(controller.isExpanded('C:\\Users\\Alice\\OneDrive'), isTrue);
      expect(controller.isExpanded('C:\\Users\\Alice\\OneDrive\\Docs'), isTrue);
      // 云盘分支不应顺带展开 C:\ 驱动器链
      expect(controller.isExpanded('C:\\'), isFalse);
      expect(
        controller.childrenFor('C:\\Users\\Alice\\OneDrive').single.name,
        'Docs',
      );
      controller.dispose();
    });

    test('syncTo 普通路径仍走驱动器链，云盘节点不受影响', () async {
      final source = FakeCursorSource({
        'C:\\': [
          [dirEntry('C:\\Data', hasChildren: true)],
          null,
        ],
        'C:\\Data': [
          [dirEntry('C:\\Data\\x')],
          null,
        ],
      });
      final pump = ManualPump();
      final controller = makeController(
        source,
        pump,
        cloudDrives: const [
          CloudDrive('OneDrive', 'C:\\Users\\Alice\\OneDrive'),
        ],
      );

      controller.syncTo('C:\\Data\\x');
      await runToIdle(pump);

      expect(controller.selectedPath, 'C:\\Data\\x');
      expect(controller.isExpanded('C:\\'), isTrue);
      expect(controller.isExpanded('C:\\Users\\Alice\\OneDrive'), isFalse);
      controller.dispose();
    });
  });
}
