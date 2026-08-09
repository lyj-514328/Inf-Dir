import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/services/window_layout_store.dart';
import 'package:inf_dir/models/layout_node.dart';
import 'package:inf_dir/models/window_layout_snapshot.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/pane_controller.dart';

DirectoryRepository _emptyRepository() => DirectoryRepository(
  cursorFactory: (path, {bool directoriesOnly = false}) async => null,
  yieldFrame: () async {},
  hasChildrenProbe: (_) => false,
);

void main() {
  test('restores workspace tree and pane state from the previous session', () async {
    final temp = Directory.systemTemp.createTempSync('inf-dir-layout-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = WindowLayoutStore(
      filePath: p.join(temp.path, 'window_layout.json'),
    );

    final layout = LayoutState(
      repository: _emptyRepository(),
      layoutStore: store,
    );
    final firstNode = layout.allPaneNodes.first;
    final first = layout.controllerFor(firstNode)!;
    await first.navigateTo(r'C:\Alpha');
    first.addTab(r'C:\Beta');
    first.setSortColumn(SortColumn.size);
    first.setSortAscending(false);
    first.setEntryFilter(EntryFilter.files);
    first.setFilterQuery('report');
    first.setViewMode(PaneViewMode.compact);
    first.resizeColumn(0, 30);

    layout.splitPane(firstNode, SplitDirection.horizontal);
    final secondNode = layout.allPaneNodes.last;
    layout.focusNode(secondNode);
    await layout.controllerFor(secondNode)!.navigateTo(r'C:\Gamma');

    layout.addWorkspace();
    await layout.controllerFor(layout.allPaneNodes.single)!.navigateTo(
      r'C:\Workspace2',
    );
    layout.splitPane(layout.allPaneNodes.single, SplitDirection.vertical);
    layout.focusNode(layout.allPaneNodes.last);
    layout.setSidebarWidth(312);
    layout.flushLayoutCache();
    layout.dispose();

    final restored = LayoutState(
      repository: _emptyRepository(),
      layoutStore: store,
    );
    addTearDown(restored.dispose);

    expect(restored.workspaces, hasLength(2));
    expect(restored.activeWorkspaceIndex, 1);
    expect(restored.sidebarWidth, 312);
    expect(restored.allPaneNodes, hasLength(2));
    expect(restored.focusedNodeId, restored.allPaneNodes.last.id);
    expect(
      restored.controllerFor(restored.allPaneNodes.first)!.currentPath,
      r'C:\Workspace2',
    );

    restored.switchWorkspace(0);
    final restoredFirst = restored.controllerFor(restored.allPaneNodes.first)!;
    expect(
      restoredFirst.tabs.map((tab) => tab.path),
      [r'C:\Alpha', r'C:\Beta'],
    );
    expect(restoredFirst.canGoBack, isTrue);
    expect(restoredFirst.sortColumn, SortColumn.size);
    expect(restoredFirst.sortAscending, isFalse);
    expect(restoredFirst.entryFilter, EntryFilter.files);
    expect(restoredFirst.filterQuery, 'report');
    expect(restoredFirst.viewMode, PaneViewMode.compact);
    expect(restoredFirst.columnWidths.first, 330);
  });

  test('ignores a corrupt cache and starts with the default layout', () {
    final temp = Directory.systemTemp.createTempSync('inf-dir-layout-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = WindowLayoutStore(
      filePath: p.join(temp.path, 'window_layout.json'),
    );
    File(store.filePath).writeAsStringSync('{not valid json');

    final layout = LayoutState(
      repository: _emptyRepository(),
      layoutStore: store,
    );
    addTearDown(layout.dispose);

    expect(layout.workspaces, hasLength(1));
    expect(layout.allPaneNodes, hasLength(4));
    expect(
      layout.allPaneNodes.map(
        (node) => layout.controllerFor(node)!.currentPath,
      ),
      [
        FileService.desktopPath,
        FileService.homeDirectory,
        FileService.documentsPath,
        FileService.downloadsPath,
      ],
    );
  });

  test(
    'migrates the legacy single home pane cache to the four-pane layout',
    () {
      final temp = Directory.systemTemp.createTempSync('inf-dir-layout-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final store = WindowLayoutStore(
        filePath: p.join(temp.path, 'window_layout.json'),
      );
      store.save(
        const WindowLayoutSnapshot(
          workspaces: [
            LayoutNodeSnapshot(
              id: 'ws0',
              type: NodeType.workspace,
              layout: SplitDirection.vertical,
              percent: 1,
              label: 'Workspace 1',
              children: [
                LayoutNodeSnapshot(
                  id: 'p0',
                  type: NodeType.pane,
                  layout: SplitDirection.horizontal,
                  percent: 1,
                  paneId: 'pane_0',
                  children: [],
                ),
              ],
            ),
          ],
          activeWorkspaceIndex: 0,
          focusedNodeId: 'p0',
          nodeIdCounter: 0,
          nextPaneCounter: 1,
          sidebarWidth: 220,
          panes: {
            'pane_0': PaneLayoutSnapshot(
              currentPath: FileService.homeViewPath,
              tabs: [FileService.homeViewPath],
              activeTabIndex: 0,
              backStack: [],
              forwardStack: [],
              sortColumn: 'name',
              sortAscending: true,
              filterQuery: '',
              entryFilter: 'all',
              viewMode: 'content',
              columnWidths: [300, 140, 100, 80],
            ),
          },
        ),
      );

      final layout = LayoutState(
        repository: _emptyRepository(),
        layoutStore: store,
      );
      addTearDown(layout.dispose);

      expect(layout.allPaneNodes, hasLength(4));
      expect(
        layout.allPaneNodes.map(
          (node) => layout.controllerFor(node)!.currentPath,
        ),
        [
          FileService.desktopPath,
          FileService.homeDirectory,
          FileService.documentsPath,
          FileService.downloadsPath,
        ],
      );
    },
  );
}
