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
      final token = repo.startRequest();
      final partials = <List<String>>[];
      final loadingStates = <bool>[];

      final future = repo.loadChildren('C:\\A', token: token,
          onPartial: (key, children, loading, owner) {
        partials.add(children.map((e) => e.name).toList());
        loadingStates.add(loading);
        expect(owner, token.id);
        expect(key, normPath('C:\\A'));
      });

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
      final tokenA = repo.startRequest();

      final futureA = repo.loadChildren('C:\\A', token: tokenA);
      await settle();
      pump.pump(); // A 翻过第一页
      await settle();
      final cursorA = source.last;
      expect(cursorA.nextPageCalls, 1);

      // 切换到 B：取消 A
      repo.cancelRequest(tokenA);
      final tokenB = repo.startRequest();
      final futureB = repo.loadChildren('C:\\B', token: tokenB);

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

      final tokenA1 = repo.startRequest();
      final futureA1 = repo.loadChildren('C:\\A', token: tokenA1);
      await settle();
      pump.pump();
      await settle();
      final cursorA1 = source.last;

      // 切到 B
      repo.cancelRequest(tokenA1);
      final tokenB = repo.startRequest();
      final futureB = repo.loadChildren('C:\\B', token: tokenB);
      await settle();
      final cursorB = source.last;

      // 立即又切回 A
      repo.cancelRequest(tokenB);
      final tokenA2 = repo.startRequest();
      final futureA2 = repo.loadChildren('C:\\A', token: tokenA2);
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
      final t1 = repo.startRequest();
      final f1 = repo.loadChildren('C:\\A', token: t1);
      await runToIdle(pump);
      await f1;
      expect(source.created.length, 1);

      final t2 = repo.startRequest();
      final cached = await repo.loadChildren('C:\\A', token: t2);
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

      final t1 = repo.startRequest();
      final f1 = repo.loadChildren('C:\\A', token: t1);
      await runToIdle(pump);
      await f1;
      expect(repo.cachedChildren('C:\\A'), isNotNull);

      // B 开始后被取消
      final t2 = repo.startRequest();
      final f2 = repo.loadChildren('C:\\B', token: t2);
      await settle();
      repo.cancelRequest(t2);
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

      final t1 = repo.startRequest();
      final t2 = repo.startRequest();
      final f1 = repo.loadChildren('C:\\A', token: t1);
      final f2 = repo.loadChildren('C:\\A', token: t2);
      await runToIdle(pump);

      expect(source.created.length, 1);
      expect((await f1)!.length, 1);
      expect((await f2)!.length, 1);
    });

    test('native begin 失败：按空目录完成并缓存', () async {
      final source = FakeCursorSource({}); // 没有该路径 → begin 失败
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final token = repo.startRequest();
      final result = await repo.loadChildren('C:\\Nowhere', token: token);
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

      final token = repo.startRequest();
      final future = repo.loadChildren('C:\\Empty', token: token);
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

      final t1 = repo.startRequest();
      final f1 = repo.loadChildren('C:\\A', token: t1);
      await runToIdle(pump);
      await f1;
      expect(source.created.length, 1);

      repo.invalidate('C:\\A');
      expect(repo.cachedChildren('C:\\A'), isNull);

      final t2 = repo.startRequest();
      final f2 = repo.loadChildren('C:\\A', token: t2);
      await runToIdle(pump);
      await f2;
      expect(source.created.length, 2);
    });

    test('patchCompleteCache 就地增删目录条目并保持排序', () async {
      final source = FakeCursorSource({
        'C:\\A': [
          [dirEntry('C:\\A\\a1'), dirEntry('C:\\A\\a3')],
          null,
        ],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);

      final token = repo.startRequest();
      final future = repo.loadChildren('C:\\A', token: token);
      await runToIdle(pump);
      await future;

      final changedKeys = <String>[];
      repo.onCacheChanged = changedKeys.add;

      repo.patchCompleteCache(
        'C:\\A',
        added: [dirEntry('C:\\A\\a2')],
      );
      expect(repo.cachedChildren('C:\\A')!.map((e) => e.name), [
        'a1',
        'a2',
        'a3',
      ]);
      expect(changedKeys, [normPath('C:\\A')]);

      // 文件条目被忽略（缓存只存目录）；删除按路径匹配。
      changedKeys.clear();
      repo.patchCompleteCache(
        'C:\\A',
        added: [fileEntry('C:\\A\\f.txt')],
        removedPaths: ['C:\\A\\a2'],
      );
      expect(repo.cachedChildren('C:\\A')!.map((e) => e.name), ['a1', 'a3']);
      expect(changedKeys, [normPath('C:\\A')]);

      // 无实际变化的补丁不触发回调。
      changedKeys.clear();
      repo.patchCompleteCache('C:\\A', added: [dirEntry('C:\\A\\a1')]);
      expect(changedKeys, isEmpty);
    });

    test('patchCompleteCache 未缓存路径是空操作，空目录补丁更新 hasChildren',
        () async {
      final source = FakeCursorSource({
        'C:\\Empty': [null],
      });
      final pump = ManualPump();
      final repo = makeRepo(source, pump);
      final token = repo.startRequest();
      final future = repo.loadChildren('C:\\Empty', token: token);
      await runToIdle(pump);
      await future;

      var changed = 0;
      repo.onCacheChanged = (_) => changed++;

      repo.patchCompleteCache('C:\\Missing', added: [dirEntry('C:\\M\\x')]);
      expect(changed, 0);

      expect(repo.hasChildrenIfKnown('C:\\Empty'), isFalse);
      repo.patchCompleteCache(
        'C:\\Empty',
        added: [dirEntry('C:\\Empty\\new')],
      );
      expect(repo.cachedChildren('C:\\Empty')!.map((e) => e.name), ['new']);
      expect(repo.hasChildrenIfKnown('C:\\Empty'), isTrue);
      expect(changed, 1);
    });

    test('invalidate 触发 onCacheChanged 回调', () async {
      final source = FakeCursorSource({});
      final pump = ManualPump();
      final repo = makeRepo(source, pump);
      final changedKeys = <String>[];
      repo.onCacheChanged = changedKeys.add;

      repo.invalidate('C:\\X');
      expect(changedKeys, [normPath('C:\\X')]);
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
