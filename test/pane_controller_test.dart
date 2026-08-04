import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/pane_controller.dart';

import 'fakes.dart';

void main() {
  group('PaneController listing revision', () {
    late FakeCursorSource source;
    late ManualPump pump;
    late DirectoryRepository repo;

    PaneController makePane(String path) => PaneController(
          path,
          repository: repo,
          frameYield: pump.yieldFrame,
        );

    setUp(() {
      source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1'), fileEntry('C:\\A\\f1.txt')],
          [dirEntry('C:\\A\\a2')],
          null,
        ],
        'C:\\B': [
          [dirEntry('C:\\B\\b1')],
          null,
        ],
        'C:\\C': [
          [dirEntry('C:\\C\\c1')],
          null,
        ],
        'C:\\Empty': [null],
      });
      pump = ManualPump();
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );
    });

    test('构造后同步拿到第一页，分页完成后排序', () async {
      final pc = makePane('C:\\A');
      // 第一页同步提交
      expect(pc.entries.length, 2);
      expect(pc.isLoading, isFalse);

      await runToIdle(pump);
      expect(pc.entries.length, 3);
      expect(source.last.isOpen, isFalse);
      pc.dispose();
    });

    test('快速 A -> B -> C：只显示 C，A/B 的 cursor 都关闭', () async {
      final pc = makePane('C:\\A');
      final cursorA = source.last;

      pc.navigateTo('C:\\B');
      final cursorB = source.last;
      pc.navigateTo('C:\\C');
      final cursorC = source.last;

      await runToIdle(pump);

      expect(pc.currentPath, 'C:\\C');
      expect(pc.entries.map((e) => e.name), ['c1']);
      expect(cursorA.isOpen, isFalse);
      expect(cursorB.isOpen, isFalse);
      expect(cursorC.isOpen, isFalse);
      pc.dispose();
    });

    test('旧 request 晚返回只关闭自己的 cursor，不污染当前 entries', () async {
      final pc = makePane('C:\\A');
      final cursorA = source.last;
      expect(pc.entries.length, 2); // A 第一页

      pc.navigateTo('C:\\B');
      expect(pc.entries.map((e) => e.name), ['b1']);

      // A 的分页循环此时恢复：不得把 a2 追加进来，不得再翻页
      await runToIdle(pump);

      expect(pc.entries.map((e) => e.name), ['b1']);
      expect(cursorA.isOpen, isFalse);
      expect(cursorA.nextPageCalls, 1); // 取消后没有翻第二页
      pc.dispose();
    });

    test('同路径重复请求：refresh 重新枚举并使 cache 失效', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      final cursorsBefore = source.created.length;

      // 预填 complete cache（sidebar 侧）
      final token = repo.startRequest();
      final f = repo.loadChildren('C:\\A', token: token);
      await runToIdle(pump);
      await f;
      expect(repo.cachedChildren('C:\\A'), isNotNull);

      pc.refresh();
      expect(repo.cachedChildren('C:\\A'), isNull); // 定点失效
      expect(source.created.length, greaterThan(cursorsBefore)); // 新 cursor

      await runToIdle(pump);
      expect(pc.entries.length, 3);
      pc.dispose();
    });

    test('native begin 失败：entries 清空、loading 结束', () {
      final pc = makePane('C:\\Nowhere');
      expect(pc.entries, isEmpty);
      expect(pc.isLoading, isFalse);
      pc.dispose();
    });

    test('native page 返回 null：空目录正常结束', () {
      final pc = makePane('C:\\Empty');
      expect(pc.entries, isEmpty);
      expect(pc.isLoading, isFalse);
      expect(source.last.isOpen, isFalse);
      pc.dispose();
    });

    test('dispose 时仍有 page task：cursor 关闭、不再 setState', () async {
      final pc = makePane('C:\\A');
      final cursor = source.last;
      expect(cursor.isOpen, isTrue);

      var notifyCount = 0;
      pc.addListener(() => notifyCount++);
      pc.dispose();
      expect(cursor.isOpen, isFalse);
      final countAfterDispose = notifyCount;

      await runToIdle(pump); // 旧循环恢复也不得再 notify / 翻页
      expect(notifyCount, countAfterDispose);
      expect(cursor.nextPageCalls, 1);
    });

    test('goBack / switchTab 同样走新 request', () async {
      final pc = makePane('C:\\A');
      pc.navigateTo('C:\\B'); // 不 await：分页需要 pump 推进
      await runToIdle(pump);
      expect(pc.currentPath, 'C:\\B');

      pc.goBack();
      expect(pc.currentPath, 'C:\\A');
      await runToIdle(pump);
      expect(pc.entries.length, 3);

      pc.addTab('C:\\C');
      expect(pc.currentPath, 'C:\\C');
      pc.switchTab(0);
      expect(pc.currentPath, 'C:\\A');
      await runToIdle(pump);
      expect(pc.entries.length, 3);
      pc.dispose();
    });

    test('导航、后退和前进会用新快照同步当前标签', () async {
      final pc = makePane('C:\\A');
      final initialTabs = pc.tabs;

      pc.navigateTo('C:\\B');
      expect(initialTabs.single.path, 'C:\\A');
      expect(initialTabs.single.label, 'A');
      expect(pc.tabs.single.path, 'C:\\B');
      expect(pc.tabs.single.label, 'B');
      await runToIdle(pump);

      final navigatedTabs = pc.tabs;
      pc.goBack();
      expect(navigatedTabs.single.path, 'C:\\B');
      expect(pc.tabs.single.path, 'C:\\A');
      expect(pc.tabs.single.label, 'A');
      await runToIdle(pump);

      pc.goForward();
      expect(pc.tabs.single.path, 'C:\\B');
      expect(pc.tabs.single.label, 'B');
      await runToIdle(pump);
      pc.dispose();
    });
  });
}
