import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/models/layout_node.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/pane_controller.dart';

import 'fakes.dart';

void main() {
  group('PaneController listing revision', () {
    late FakeCursorSource source;
    late ManualPump pump;
    late DirectoryRepository repo;

    PaneController makePane(String path) =>
        PaneController(path, repository: repo, frameYield: pump.yieldFrame);

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

    test('构造后尽快拿到第一页（worker 异步），分页完成后排序', () async {
      final pc = makePane('C:\\A');
      // 第一页经 worker isolate 异步返回
      await settle();
      expect(pc.entries.length, 2);
      expect(pc.entries.map((e) => e.name), ['a1', 'f1.txt']);
      expect(pc.isLoading, isFalse);

      await runToIdle(pump);
      expect(pc.entries.length, 3);
      expect(source.last.isOpen, isFalse);
      pc.dispose();
    });

    test('inverts only visible entries', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);

      pc.selectSingle('C:\\A\\a1');
      pc.invertSelection();

      expect(pc.selectedPaths, {'C:\\A\\f1.txt', 'C:\\A\\a2'});
      pc.dispose();
    });

    test(
      'search, quick filters and view mode stay local to the pane',
      () async {
        source = FakeCursorSource({
          'C:\\Filtered': [
            [
              dirEntry('C:\\Filtered\\Reports'),
              fileEntry('C:\\Filtered\\report.pdf'),
              fileEntry('C:\\Filtered\\photo.png'),
              fileEntry('C:\\Filtered\\notes.txt'),
            ],
            null,
          ],
        });
        repo = DirectoryRepository(
          cursorFactory: source.open,
          yieldFrame: pump.yieldFrame,
          hasChildrenProbe: (_) => true,
        );

        final pc = makePane('C:\\Filtered');
        await runToIdle(pump);

        pc.setFilterQuery('report');
        expect(pc.visibleEntries.map((e) => e.name), ['Reports', 'report.pdf']);

        pc.setFilterQuery('');
        pc.setEntryFilter(EntryFilter.images);
        expect(pc.visibleEntries.map((e) => e.name), ['photo.png']);

        pc.selectAll();
        expect(pc.selectedPaths, {'C:\\Filtered\\photo.png'});

        pc.setViewMode(PaneViewMode.list);
        expect(pc.viewMode, PaneViewMode.list);
        expect(pc.entries, hasLength(4));
        pc.dispose();
      },
    );

    test('filter query supports keyword / glob / regex modes', () async {
      source = FakeCursorSource({
        'C:\\Modes': [
          [
            fileEntry('C:\\Modes\\report2024.txt'),
            fileEntry('C:\\Modes\\report2025.pdf'),
            fileEntry('C:\\Modes\\notes.md'),
            fileEntry('C:\\Modes\\data.tmp'),
            dirEntry('C:\\Modes\\Reports'),
          ],
          null,
        ],
      });
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );

      final pc = makePane('C:\\Modes');
      await runToIdle(pump);

      // 关键字（默认忽略大小写）
      pc.setFilterQuery('REPORT');
      expect(pc.filterMode, QueryFilterMode.keyword);
      expect(pc.caseSensitive, isFalse);
      expect(pc.visibleEntries.map((e) => e.name), [
        'Reports',
        'report2024.txt',
        'report2025.pdf',
      ]);

      // 关键字（大小写敏感）
      pc.setFilterMode(QueryFilterMode.keyword, caseSensitive: true);
      // 当前 query 'REPORT'（大写）不再匹配小写文件名
      expect(pc.visibleEntries, isEmpty);
      pc.setFilterQuery('report');
      expect(pc.visibleEntries.map((e) => e.name), [
        'report2024.txt',
        'report2025.pdf',
      ]);
      pc.setFilterQuery('Reports');
      expect(pc.visibleEntries.map((e) => e.name), ['Reports']);

      // glob：* 任意串（整名锚定）
      pc.setFilterMode(QueryFilterMode.glob);
      pc.setFilterQuery('*.txt');
      expect(pc.visibleEntries.map((e) => e.name), ['report2024.txt']);

      pc.setFilterQuery('report*2025.*');
      expect(pc.visibleEntries.map((e) => e.name), ['report2025.pdf']);

      pc.setFilterQuery('?.md');
      expect(pc.visibleEntries, isEmpty);

      // 正则：显式模式，直接写表达式
      pc.setFilterMode(QueryFilterMode.regex);
      pc.setFilterQuery(r'^note');
      expect(pc.visibleEntries.map((e) => e.name), ['notes.md']);

      pc.setFilterQuery(r'report\d+');
      expect(pc.visibleEntries.map((e) => e.name), [
        'report2024.txt',
        'report2025.pdf',
      ]);

      // 无效正则退化为关键字匹配，不崩溃
      pc.setFilterQuery(r'[');
      expect(pc.visibleEntries, isEmpty);

      pc.setFilterQuery('');
      expect(pc.visibleEntries, hasLength(5));
      pc.dispose();
    });

    test('keeps every published page globally sorted', () async {
      source = FakeCursorSource({
        'C:\\Paged': [
          [
            fileEntry('C:\\Paged\\z.txt'),
            dirEntry('C:\\Paged\\z-dir'),
            fileEntry('C:\\Paged\\a.txt'),
            dirEntry('C:\\Paged\\a-dir'),
          ],
          [
            fileEntry('C:\\Paged\\m.txt'),
            dirEntry('C:\\Paged\\m-dir'),
            fileEntry('C:\\Paged\\b.txt'),
            dirEntry('C:\\Paged\\b-dir'),
          ],
          null,
        ],
      });
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );

      final pc = makePane('C:\\Paged');
      await settle();
      expect(pc.entries.map((e) => e.name), [
        'a-dir',
        'z-dir',
        'a.txt',
        'z.txt',
      ]);

      pump.pump();
      await settle();
      pump.pump();
      await settle();

      expect(pc.entries.map((e) => e.name), [
        'a-dir',
        'b-dir',
        'm-dir',
        'z-dir',
        'a.txt',
        'b.txt',
        'm.txt',
        'z.txt',
      ]);

      await runToIdle(pump);
      pc.dispose();
    });

    test('uses native natural sort keys for name sorting', () async {
      source = FakeCursorSource({
        'C:\\Natural': [
          [
            fileEntry('C:\\Natural\\file10.txt', nameSortKey: [10]),
            fileEntry('C:\\Natural\\file2.txt', nameSortKey: [2]),
            fileEntry('C:\\Natural\\file1.txt', nameSortKey: [1]),
          ],
          null,
        ],
      });
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );

      final pc = makePane('C:\\Natural');
      await settle();
      expect(pc.entries.map((entry) => entry.name), [
        'file1.txt',
        'file2.txt',
        'file10.txt',
      ]);

      await runToIdle(pump);
      pc.dispose();
    });

    test(
      'home is a virtual page and participates in navigation history',
      () async {
        final pc = makePane(FileService.homeViewPath);

        expect(pc.isHome, isTrue);
        expect(pc.displayPath, '主文件夹');
        expect(pc.entries, isEmpty);
        expect(pc.isLoading, isFalse);
        expect(pc.canGoUp, isFalse);
        expect(source.created, isEmpty);

        pc.navigateTo('C:\\A');
        expect(pc.isHome, isFalse);
        await settle();
        expect(source.created, hasLength(1));

        pc.goBack();
        expect(pc.isHome, isTrue);
        expect(pc.entries, isEmpty);
        expect(source.created, hasLength(1));
        pc.dispose();
      },
    );

    test('default workspace starts with four panes and remains splittable', () {
      final layout = LayoutState(repository: repo);

      expect(layout.allPaneNodes, hasLength(4));
      expect(
        layout.allPaneNodes.map(
          (node) => layout.controllerFor(node)?.currentPath,
        ),
        [
          FileService.desktopPath,
          FileService.homeDirectory,
          FileService.documentsPath,
          FileService.downloadsPath,
        ],
      );

      layout.splitPane(layout.allPaneNodes.first, SplitDirection.horizontal);
      expect(layout.allPaneNodes, hasLength(5));
      layout.dispose();
    });

    testWidgets('refreshPanesWhere reloads only matching panes', (
      tester,
    ) async {
      final layout = LayoutState(repository: repo);
      final panes = layout.allPaneNodes
          .map(layout.controllerFor)
          .whereType<PaneController>()
          .toList();
      panes[0].navigateTo('C:\\A');
      panes[1].navigateTo('C:\\B');
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      source.created.clear();

      layout.refreshPanesWhere((path) => path == 'C:\\A');
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(source.created, hasLength(1));
      expect(panes[0].entries, isNotEmpty);
      layout.dispose();
    });

    testWidgets('applyLocalRemovals updates panes without reloading', (
      tester,
    ) async {
      final layout = LayoutState(repository: repo);
      final panes = layout.allPaneNodes
          .map(layout.controllerFor)
          .whereType<PaneController>()
          .toList();
      panes[0].navigateTo('C:\\A');
      panes[1].navigateTo('C:\\A');
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      const removedPath = 'C:\\A\\f1.txt';
      panes[0].selectSingle(removedPath);
      panes[1].selectSingle(removedPath);
      source.created.clear();

      layout.applyLocalRemovals(const [removedPath]);

      expect(
        panes[0].entries.map((entry) => entry.path),
        isNot(contains(removedPath)),
      );
      expect(
        panes[1].entries.map((entry) => entry.path),
        isNot(contains(removedPath)),
      );
      expect(panes[0].selectedPaths, isNot(contains(removedPath)));
      expect(panes[1].selectedPaths, isNot(contains(removedPath)));
      expect(source.created, isEmpty);
      layout.dispose();
    });

    testWidgets('applyLocalChanges fans out to panes showing the affected '
        'directories only', (tester) async {
      final layout = LayoutState(repository: repo);
      final panes = layout.allPaneNodes
          .map(layout.controllerFor)
          .whereType<PaneController>()
          .toList();
      panes[0].navigateTo('C:\\A');
      panes[1].navigateTo('C:\\A');
      panes[2].navigateTo('C:\\B');
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      const removedPath = 'C:\\A\\f1.txt';
      panes[0].selectSingle(removedPath);
      panes[1].selectSingle(removedPath);
      source.created.clear();

      layout.applyLocalChanges(removedPaths: const [removedPath]);

      for (final pane in panes.take(2)) {
        expect(pane.entries.map((entry) => entry.path),
            isNot(contains(removedPath)));
        expect(pane.selectedPaths, isNot(contains(removedPath)));
      }
      // 显示其他目录的面板不受影响。
      expect(panes[2].entries.map((entry) => entry.name), ['b1']);
      expect(source.created, isEmpty);
      layout.dispose();
    });

    test('uses a sort change for pages that arrive while loading', () async {
      source = FakeCursorSource({
        'C:\\Paged': [
          [dirEntry('C:\\Paged\\a-dir'), fileEntry('C:\\Paged\\a.txt')],
          [dirEntry('C:\\Paged\\z-dir'), fileEntry('C:\\Paged\\z.txt')],
          null,
        ],
      });
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );

      final pc = makePane('C:\\Paged');
      pc.sortBy(SortColumn.name);
      expect(pc.sortAscending, isFalse);

      await runToIdle(pump);
      expect(pc.entries.map((e) => e.name), [
        'z-dir',
        'a-dir',
        'z.txt',
        'a.txt',
      ]);
      pc.dispose();
    });

    test('快速 A -> B -> C：只显示 C，A/B 的 cursor 都关闭', () async {
      final pc = makePane('C:\\A');
      await settle();
      final cursorA = source.last;

      pc.navigateTo('C:\\B');
      await settle();
      final cursorB = source.last;
      pc.navigateTo('C:\\C');
      await settle();
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
      await settle();
      final cursorA = source.last;
      expect(pc.entries.length, 2); // A 第一页

      pc.navigateTo('C:\\B');
      await settle();
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
      await settle();
      expect(source.created.length, greaterThan(cursorsBefore)); // 新 cursor

      await runToIdle(pump);
      expect(pc.entries.length, 3);
      pc.dispose();
    });

    test('native begin 失败：entries 清空、loading 结束', () async {
      final pc = makePane('C:\\Nowhere');
      await settle();
      expect(pc.entries, isEmpty);
      expect(pc.isLoading, isFalse);
      pc.dispose();
    });

    test('native page 返回 null：空目录正常结束', () async {
      final pc = makePane('C:\\Empty');
      await settle();
      expect(pc.entries, isEmpty);
      expect(pc.isLoading, isFalse);
      expect(source.last.isOpen, isFalse);
      pc.dispose();
    });

    test('focusedPath 跟随最近操作项并在清空时重置', () {
      final pc = makePane('C:\\A');
      pc.selectSingle('C:\\A\\f1.txt');
      expect(pc.focusedPath, 'C:\\A\\f1.txt');

      pc.selectSingle('C:\\A\\a1');
      expect(pc.focusedPath, 'C:\\A\\a1');

      pc.toggleSelection('C:\\A\\a1');
      expect(pc.selectedPaths, isEmpty);
      pc.clearSelection();
      expect(pc.focusedPath, isNull);
      pc.dispose();
    });

    test('dispose 时仍有 page task：cursor 关闭、不再 setState', () async {
      final pc = makePane('C:\\A');
      await settle();
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

  group('PaneController tab management', () {
    late FakeCursorSource source;
    late ManualPump pump;
    late DirectoryRepository repo;
    final closedRecords = <TabRecord>[];

    PaneController makePane(String path) => PaneController(
      path,
      repository: repo,
      frameYield: pump.yieldFrame,
      onTabClosed: closedRecords.add,
    );

    setUp(() {
      source = FakeCursorSource({
        'C:\\A': [[dirEntry('C:\\A\\a1')], null],
        'C:\\B': [[dirEntry('C:\\B\\b1')], null],
        'C:\\C': [[dirEntry('C:\\C\\c1')], null],
        'C:\\D': [[dirEntry('C:\\D\\d1')], null],
      });
      pump = ManualPump();
      repo = DirectoryRepository(
        cursorFactory: source.open,
        yieldFrame: pump.yieldFrame,
        hasChildrenProbe: (_) => true,
      );
      closedRecords.clear();
    });

    Future<void> nav(PaneController pc, String path) async {
      pc.navigateTo(path);
      await runToIdle(pump);
    }

    test('每个标签保留独立的前进后退历史', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      await nav(pc, 'C:\\B');
      pc.addTab();
      await nav(pc, 'C:\\C');

      pc.switchTab(0);
      expect(pc.currentPath, 'C:\\B');
      expect(pc.canGoBack, isTrue);
      pc.goBack();
      expect(pc.currentPath, 'C:\\A');
      expect(pc.canGoForward, isTrue);

      pc.switchTab(1);
      expect(pc.currentPath, 'C:\\C');
      expect(pc.canGoBack, isTrue);
      pc.goBack();
      expect(pc.currentPath, 'C:\\B');

      pc.switchTab(0);
      expect(pc.currentPath, 'C:\\A');
      pc.goForward();
      expect(pc.currentPath, 'C:\\B');
      pc.dispose();
    });

    test('addTab 同路径时新标签不继承旧历史', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      await nav(pc, 'C:\\B');
      pc.addTab();
      expect(pc.canGoBack, isFalse);
      expect(pc.canGoForward, isFalse);
      pc.switchTab(0);
      expect(pc.canGoBack, isTrue);
      pc.dispose();
    });

    test('moveTab 重排并保持激活标签', () {
      final pc = makePane('C:\\A');
      pc.addTab('C:\\B');
      pc.addTab('C:\\C');
      expect(pc.activeTabIndex, 2);

      pc.moveTab(0, 3);
      expect(pc.tabs.map((t) => t.path), ['C:\\B', 'C:\\C', 'C:\\A']);
      expect(pc.activeTabIndex, 1); // 活动标签 C 随重排移到索引 1
      expect(pc.currentPath, 'C:\\C');

      pc.moveTab(2, 0);
      expect(pc.tabs.map((t) => t.path), ['C:\\A', 'C:\\B', 'C:\\C']);
      expect(pc.activeTabIndex, 2);

      pc.switchTab(1);
      pc.moveTab(0, 2);
      expect(pc.tabs.map((t) => t.path), ['C:\\B', 'C:\\A', 'C:\\C']);
      expect(pc.activeTabIndex, 0);
      pc.dispose();
    });

    test('duplicateTab 深拷贝历史且互不影响', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      await nav(pc, 'C:\\B');
      pc.duplicateTab();
      expect(pc.tabs, hasLength(2));
      expect(pc.activeTabIndex, 1);
      expect(pc.currentPath, 'C:\\B');
      expect(pc.canGoBack, isTrue);

      await nav(pc, 'C:\\C');
      pc.switchTab(0);
      expect(pc.currentPath, 'C:\\B');
      expect(pc.canGoForward, isFalse);
      pc.dispose();
    });

    test('cycleTab 环绕切换', () {
      final pc = makePane('C:\\A');
      pc.addTab('C:\\B');
      pc.addTab('C:\\C');
      expect(pc.activeTabIndex, 2);
      pc.cycleTab(1);
      expect(pc.activeTabIndex, 0);
      pc.cycleTab(-1);
      expect(pc.activeTabIndex, 2);
      pc.cycleTab(-1);
      expect(pc.activeTabIndex, 1);
      pc.dispose();
    });

    test('closeTab 上报关闭记录', () {
      final pc = makePane('C:\\A');
      pc.addTab('C:\\B');
      pc.closeTab(0);
      expect(closedRecords, hasLength(1));
      expect(closedRecords.single.path, 'C:\\A');
      expect(closedRecords.single.index, 0);
      pc.dispose();
    });

    test('关闭其他/左侧/右侧会上报关闭记录并保留锚点标签', () {
      final pc = makePane('C:\\A');
      pc.addTab('C:\\B');
      pc.addTab('C:\\C');
      pc.addTab('C:\\D');
      pc.switchTab(1);

      pc.closeTabsToTheRight(1);
      expect(pc.tabs.map((t) => t.path), ['C:\\A', 'C:\\B']);
      expect(closedRecords.map((r) => r.path), ['C:\\D', 'C:\\C']);

      pc.addTab('C:\\C');
      pc.addTab('C:\\D');
      pc.switchTab(2);
      pc.closeTabsToTheLeft(2);
      expect(pc.tabs.map((t) => t.path), ['C:\\C', 'C:\\D']);
      expect(pc.activeTabIndex, 0);
      expect(pc.currentPath, 'C:\\C');
      expect(
        closedRecords.map((r) => r.path),
        ['C:\\D', 'C:\\C', 'C:\\B', 'C:\\A'],
      );

      pc.closeOtherTabs(0);
      expect(pc.tabs.map((t) => t.path), ['C:\\C']);
      expect(closedRecords.last.path, 'C:\\D');
      pc.dispose();
    });

    test('takeTab/insertTab 跨 pane 往返保留历史', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      await nav(pc, 'C:\\B');
      pc.addTab('C:\\C');
      final record = pc.takeTab(0)!;
      expect(record.path, 'C:\\B');
      expect(record.backStack, ['C:\\A']);
      expect(pc.tabs, hasLength(1));

      final other = makePane('C:\\D');
      other.insertTab(0, record);
      expect(other.tabs.map((t) => t.path), ['C:\\B', 'C:\\D']);
      expect(other.activeTabIndex, 0);
      expect(other.canGoBack, isTrue);
      other.goBack();
      expect(other.currentPath, 'C:\\A');
      other.dispose();
      pc.dispose();
    });

    test('takeTab 拒绝取走唯一标签', () {
      final pc = makePane('C:\\A');
      expect(pc.takeTab(0), isNull);
      expect(pc.tabs, hasLength(1));
      pc.dispose();
    });

    test('collectClosedRecords 导出全部标签状态', () async {
      final pc = makePane('C:\\A');
      await runToIdle(pump);
      await nav(pc, 'C:\\B');
      pc.addTab('C:\\C');
      final records = pc.collectClosedRecords();
      expect(records.map((r) => r.path), ['C:\\B', 'C:\\C']);
      expect(records.first.backStack, ['C:\\A']);
      pc.dispose();
    });
  });
}
