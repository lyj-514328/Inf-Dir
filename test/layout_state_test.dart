import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/layout_node.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/services/settings_store.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/state/settings_controller.dart';
import 'package:path/path.dart' as p;

DirectoryRepository _emptyRepository() => DirectoryRepository(
  cursorFactory: (path, {bool directoriesOnly = false}) async => null,
  yieldFrame: () async {},
  hasChildrenProbe: (_) => false,
);

void main() {
  test(
    'new panes and tabs use settings defaults without changing existing panes',
    () {
      final temp = Directory.systemTemp.createTempSync(
        'inf_dir_layout_settings_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final settings = SettingsController(
        store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      );
      addTearDown(settings.dispose);
      settings.setDefaultViewMode(PaneViewMode.tiles);
      settings.setCustomNewTabPath(r'D:\New tabs');
      final layout = LayoutState(
        repository: _emptyRepository(),
        settings: settings,
      );
      addTearDown(layout.dispose);

      final existing = layout.controllerFor(layout.allPaneNodes.first)!;
      expect(existing.viewMode, PaneViewMode.tiles);
      existing.setViewMode(PaneViewMode.list);

      final created = layout.splitPane(
        layout.allPaneNodes.first,
        SplitDirection.horizontal,
      )!;
      expect(created.viewMode, PaneViewMode.tiles);
      expect(existing.viewMode, PaneViewMode.list);

      existing.addTab();
      expect(existing.currentPath, r'D:\New tabs');
    },
  );

  test('closeTab 记录最近关闭并可恢复到原索引', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final node = layout.allPaneNodes.first;
    final pane = layout.controllerFor(node)!;
    pane.addTab(r'C:\One');
    pane.addTab(r'C:\Two');
    layout.focusNode(node);
    expect(layout.canRestoreClosedTab, isFalse);

    pane.closeTab(1);
    expect(layout.canRestoreClosedTab, isTrue);

    layout.restoreClosedTab();
    expect(pane.tabs.map((t) => t.path), [
      FileService.desktopPath,
      r'C:\One',
      r'C:\Two',
    ]);
    expect(pane.activeTabIndex, 1);
    expect(pane.currentPath, r'C:\One');
  });

  test('restoreClosedTab 索引越界时 clamp 到末尾', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final node = layout.allPaneNodes.first;
    final pane = layout.controllerFor(node)!;
    pane.addTab(r'C:\One');
    pane.addTab(r'C:\Two');
    layout.focusNode(node);
    pane.closeTab(2);
    pane.closeTab(1);
    expect(pane.tabs, hasLength(1));

    layout.restoreClosedTab();
    layout.restoreClosedTab();
    expect(pane.tabs.map((t) => t.path), [
      FileService.desktopPath,
      r'C:\One',
      r'C:\Two',
    ]);
  });

  test('关闭 pane 后其标签按原顺序恢复', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final node = layout.allPaneNodes.first;
    final pane = layout.controllerFor(node)!;
    pane.addTab(r'C:\One');
    pane.addTab(r'C:\Two');

    layout.closePane(node);
    expect(layout.allPaneNodes, hasLength(3));
    expect(layout.canRestoreClosedTab, isTrue);

    final restoredPaths = <String>[];
    for (var i = 0; i < 3; i++) {
      layout.restoreClosedTab();
      restoredPaths.add(layout.controllerFor(layout.focusedNode)!.currentPath);
    }
    expect(restoredPaths, [FileService.desktopPath, r'C:\One', r'C:\Two']);
    expect(layout.canRestoreClosedTab, isFalse);
  });

  test('moveTabBetweenPanes 支持移动、复制并拒绝取走唯一标签', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final nodes = layout.allPaneNodes;
    final source = layout.controllerFor(nodes[0])!;
    final target = layout.controllerFor(nodes[1])!;
    final sourceId = nodes[0].paneId!;
    final targetId = nodes[1].paneId!;
    source.addTab(r'C:\One');

    expect(
      layout.moveTabBetweenPanes(sourceId, 1, targetId, 0, copy: false),
      isTrue,
    );
    expect(source.tabs.map((t) => t.path), [FileService.desktopPath]);
    expect(target.tabs.map((t) => t.path), [
      r'C:\One',
      FileService.homeDirectory,
    ]);
    expect(target.currentPath, r'C:\One');

    // 源 pane 唯一标签：拒绝移动，但允许复制。
    expect(
      layout.moveTabBetweenPanes(sourceId, 0, targetId, 1, copy: false),
      isFalse,
    );
    expect(source.tabs, hasLength(1));
    expect(
      layout.moveTabBetweenPanes(sourceId, 0, targetId, 1, copy: true),
      isTrue,
    );
    expect(source.tabs, hasLength(1));
    expect(target.tabs.map((t) => t.path), [
      r'C:\One',
      FileService.desktopPath,
      FileService.homeDirectory,
    ]);

    // 源 pane 已不存在：静默失败。
    expect(
      layout.moveTabBetweenPanes('pane_missing', 0, targetId, 0, copy: false),
      isFalse,
    );
  });

  test('closeActiveTabForShortcut 三段语义', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final node = layout.allPaneNodes.first;
    final pane = layout.controllerFor(node)!;
    pane.addTab();
    layout.focusNode(node);

    layout.closeActiveTabForShortcut();
    expect(pane.tabs, hasLength(1));
    expect(layout.allPaneNodes, hasLength(4));

    layout.focusNode(layout.allPaneNodes.first);
    layout.closeActiveTabForShortcut();
    expect(layout.allPaneNodes, hasLength(3));

    layout.closePane(layout.allPaneNodes.first);
    layout.closePane(layout.allPaneNodes.first);
    expect(layout.allPaneNodes, hasLength(1));

    layout.focusNode(layout.allPaneNodes.single);
    final last = layout.controllerFor(layout.allPaneNodes.single)!;
    layout.closeActiveTabForShortcut();
    expect(layout.allPaneNodes, hasLength(1));
    expect(last.tabs, hasLength(1));
  });
}
