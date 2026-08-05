import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/utils/path_utils.dart';

import 'fakes.dart';

DirectoryRepository makeRepo(FakeCursorSource source, ManualPump pump) =>
    DirectoryRepository(
      cursorFactory: source.open,
      yieldFrame: pump.yieldFrame,
      hasChildrenProbe: (_) => true,
    );

void main() {
  group('DirectoryRepository', () {
    test('完整加载后进入 complete cache，partial 逐步发布', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1'), fileEntry('C:\\A\\f.txt')],
          [dirEntry('C:\\A\\a2')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);
      final partials = <List<String>>[];
      final loadingStates = <bool>[];

      late DirectoryLoadLease lease;
      lease = repo.acquireChildren(
        'C:\\A',
        onPartial: (key, children, loading, owner) {
          partials.add(children.map((e) => e.name).toList());
          loadingStates.add(loading);
          expect(owner, lease.loadId);
          expect(key, normPath('C:\\A'));
        },
      );
      final future = lease.done;

      // 第一页前的 loading 占位（同步发布）
      await settle();
      expect(partials.first, isEmpty);
      expect(loadingStates.first, isTrue);

      await runToIdle(pump);
      final result = await future;

      expect(result, isNotNull);
      // 文件被过滤，只保留目录
      expect(result!.map((e) => e.name), ['a1', 'a2']);
      expect(repo.cachedChildren('C:\\A')!.map((e) => e.name), ['a1', 'a2']);
      // 最后一次发布 loading == false
      expect(loadingStates.last, isFalse);
      // cursor 已关闭
      expect(source.last.isOpen, isFalse);
      // 枚举元数据种入 hasChildren 缓存
      expect(repo.hasChildrenIfKnown('C:\\A\\a1'), isFalse);
    });

    test('A 请求开始后切换到 B：A 被取消，不再翻页，不进 cache', () async {
      final source = FakeCursorSource({
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
      final repo = makeRepo(source, pump);
      final leaseA = repo.acquireChildren('C:\\A');
      final futureA = leaseA.done;
      await settle();
      pump.pump(); // A 翻过第一页
      await settle();
      final cursorA = source.last;
      expect(cursorA.nextPageCalls, 1);

      // 切换到 B：取消 A
      leaseA.release();
      final leaseB = repo.acquireChildren('C:\\B');
      final futureB = leaseB.done;

      await runToIdle(pump);

      expect(await futureA, isNull); // A 被丢弃
      expect(cursorA.isOpen, isFalse);
      expect(cursorA.nextPageCalls, 1); // 取消后不再翻页
      expect(repo.cachedChildren('C:\\A'), isNull); // 未完成不进 cache

      expect((await futureB)!.map((e) => e.name), ['b1']);
      expect(repo.cachedChildren('C:\\B'), isNotNull);
    });

    test('A -> B -> A：旧 A 晚恢复只清理自己，新 A 的 cursor 不受影响', () async {
      final source = FakeCursorSource({
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
      final repo = makeRepo(source, pump);

      final leaseA1 = repo.acquireChildren('C:\\A');
      final futureA1 = leaseA1.done;
      await settle();
      pump.pump();
      await settle();
      final cursorA1 = source.last;

      // 切到 B
      leaseA1.release();
      final leaseB = repo.acquireChildren('C:\\B');
      final futureB = leaseB.done;
      await settle();
      final cursorB = source.last;

      // 立即又切回 A
      leaseB.release();
      final leaseA2 = repo.acquireChildren('C:\\A');
      final futureA2 = leaseA2.done;
      await settle();
      final cursorA2 = source.last;
      expect(identical(cursorA2, cursorA1), isFalse);

      await runToIdle(pump);

      expect(await futureA1, isNull);
      expect(await futureB, isNull);
      expect(cursorA1.isOpen, isFalse);
      expect(cursorB.isOpen, isFalse);
      // 新 A 的 cursor 没有被旧 request 关闭，且完成了加载
      expect((await futureA2)!.map((e) => e.name), ['a1', 'a2']);
      expect(repo.cachedChildren('C:\\A')!.length, 2);
    });

    test('同路径重复请求：complete cache 直接命中，不开新 cursor', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      await runToIdle(pump);
      final lease1 = repo.acquireChildren('C:\\A');
      final f1 = lease1.done;
      await runToIdle(pump);
      await f1;
      expect(source.created.length, 1);

      final lease2 = repo.acquireChildren('C:\\A');
      final cached = await lease2.done;
      expect(cached, isNotNull);
      expect(source.created.length, 1); // 没有新 cursor
    });

    test('complete cache 在另一个请求取消后保留', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
        'C:\\B': [
          [dirEntry('C:\\B\\b1')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease1 = repo.acquireChildren('C:\\A');
      final f1 = lease1.done;
      await runToIdle(pump);
      await f1;
      expect(repo.cachedChildren('C:\\A'), isNotNull);

      // B 开始后被取消
      final lease2 = repo.acquireChildren('C:\\B');
      final f2 = lease2.done;
      await settle();
      lease2.release();
      await runToIdle(pump);
      expect(await f2, isNull);

      // A 的 complete cache 保留
      expect(repo.cachedChildren('C:\\A'), isNotNull);
    });

    test('同一路径并发加载：复用活动任务，不开第二个 cursor', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease1 = repo.acquireChildren('C:\\A');
      final lease2 = repo.acquireChildren('C:\\A');
      final f1 = lease1.done;
      final f2 = lease2.done;
      await runToIdle(pump);

      expect(source.created.length, 1);
      expect((await f1)!.length, 1);
      expect((await f2)!.length, 1);
    });

    test('同路径一个 lease 释放后，其他消费者继续分页', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          [dirEntry('C:\\A\\a2')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease1 = repo.acquireChildren('C:\\A');
      final lease2 = repo.acquireChildren('C:\\A');
      await settle();
      pump.pump();
      await settle();

      final cursor = source.last;
      expect(cursor.nextPageCalls, 1);
      lease1.release();
      expect(await lease1.done, isNull);
      expect(cursor.isOpen, isTrue);

      await runToIdle(pump);
      expect((await lease2.done)!.map((e) => e.name), ['a1', 'a2']);
      expect(repo.cachedChildren('C:\\A')!.length, 2);
      expect(cursor.isOpen, isFalse);
      expect(source.created.length, 1);
    });

    test('native begin 失败：按空目录完成并缓存', () async {
      final source = FakeCursorSource({}); // 没有该路径 → begin 失败
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease = repo.acquireChildren('C:\\Nowhere');
      final result = await lease.done;
      expect(result, isEmpty);
      expect(repo.cachedChildren('C:\\Nowhere'), isEmpty);
      expect(source.created, isEmpty);
    });

    test('native page 返回 null：空目录正常完成', () async {
      final source = FakeCursorSource({
        'C:\\Empty': [null],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease = repo.acquireChildren('C:\\Empty');
      final future = lease.done;
      await runToIdle(pump);
      final result = await future;

      expect(result, isEmpty);
      expect(repo.cachedChildren('C:\\Empty'), isEmpty);
      expect(source.last.isOpen, isFalse);
    });

    test('invalidate 后重新加载会开新 cursor', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final lease1 = repo.acquireChildren('C:\\A');
      final f1 = lease1.done;
      await runToIdle(pump);
      await f1;
      expect(source.created.length, 1);

      repo.invalidate('C:\\A');
      expect(repo.cachedChildren('C:\\A'), isNull);

      final lease2 = repo.acquireChildren('C:\\A');
      final f2 = lease2.done;
      await runToIdle(pump);
      await f2;
      expect(source.created.length, 2);
    });

    test('hasChildren：未知路径只 probe 一次并缓存', () async {
      final source = FakeCursorSource({});
      final pump = ManualPump();
      var probeCount = 0;
      final repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (path) {
          probeCount++;
          return true;
        },
      );

      expect(repo.hasChildrenIfKnown('C:\\X'), isNull);
      repo.probeHasChildren('C:\\X');
      repo.probeHasChildren('C:\\X'); // 在途不重复
      await settle();
      expect(probeCount, 1);
      expect(repo.hasChildrenIfKnown('C:\\X'), isTrue);

      repo.invalidate('C:\\X');
      expect(repo.hasChildrenIfKnown('C:\\X'), isNull);
    });
  });
}
