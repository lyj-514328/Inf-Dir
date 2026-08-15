import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_pane.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  testWidgets('moves across panes and then into a same-pane folder', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('inf_dir_drag_');
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    final target = Directory(p.join(temp.path, 'target'))..createSync();
    final nested = Directory(p.join(target.path, 'nested'))..createSync();
    final sourceFile = File(p.join(source.path, 'drag-me.txt'))
      ..writeAsStringSync('dragged');
    final secondFile = File(p.join(source.path, 'and-me.txt'))
      ..writeAsStringSync('also dragged');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final entries = [
      FileEntry(
        name: 'and-me.txt',
        path: secondFile.path,
        isDirectory: false,
        size: secondFile.lengthSync(),
        modified: secondFile.lastModifiedSync(),
      ),
      FileEntry(
        name: 'drag-me.txt',
        path: sourceFile.path,
        isDirectory: false,
        size: sourceFile.lengthSync(),
        modified: sourceFile.lastModifiedSync(),
      ),
    ];
    final nestedEntry = FileEntry(
      name: 'nested',
      path: nested.path,
      isDirectory: true,
      size: 0,
      modified: FileStat.statSync(nested.path).modified,
    );
    final repository = DirectoryRepository(
      cursorFactory: (path, {bool directoriesOnly = false}) async {
        if (p.equals(path, source.path)) {
          return FakeCursor([
            directoriesOnly ? const <FileEntry>[] : entries,
            null,
          ]);
        }
        if (p.equals(path, target.path)) {
          return FakeCursor([
            [nestedEntry],
            null,
          ]);
        }
        return FakeCursor([const <FileEntry>[], null]);
      },
      hasChildrenProbe: (_) => false,
    );
    final layoutState = LayoutState(repository: repository);
    final appState = AppState(repository: repository);
    addTearDown(layoutState.dispose);
    addTearDown(appState.dispose);

    final panes = layoutState.allPaneNodes;
    final sourcePane = panes[0];
    final targetPane = panes[1];
    final sourceController = layoutState.controllerFor(sourcePane)!;
    sourceController.navigateTo(source.path);
    layoutState.controllerFor(targetPane)!.navigateTo(target.path);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LayoutState>.value(value: layoutState),
          ChangeNotifierProvider<AppState>.value(value: appState),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(key: ValueKey('invalid-drop-zone'), height: 40),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: FilePane(
                          paneId: sourcePane.paneId!,
                          cloudZoneResolver: (_) => false,
                        ),
                      ),
                      Expanded(
                        child: FilePane(
                          paneId: targetPane.paneId!,
                          cloudZoneResolver: (_) => false,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    sourceController.selectAll();
    await tester.pump();

    final sourceItem = find.text('drag-me.txt');
    final sourceWidget = find.byWidgetPredicate(
      (widget) => widget is FilePane && widget.paneId == sourcePane.paneId,
    );
    final targetWidget = find.byWidgetPredicate(
      (widget) => widget is FilePane && widget.paneId == targetPane.paneId,
    );
    expect(sourceItem, findsOneWidget);
    expect(sourceWidget, findsOneWidget);
    expect(targetWidget, findsOneWidget);

    final sourceRect = tester.getRect(sourceWidget);
    final dragRect = tester.getRect(
      find.byKey(ValueKey('file-drag-${sourceFile.path}')),
    );
    expect(
      sourceRect.right - dragRect.right,
      greaterThanOrEqualTo(AppMetrics.scrollbarGutter - 1),
    );
    final scrollbarPoint = Offset(
      sourceRect.right - 2,
      tester.getCenter(sourceItem).dy,
    );
    await tester.tapAt(scrollbarPoint);
    await tester.pump();
    expect(find.text('源和目标文件夹相同'), findsNothing);

    final heldGesture = await tester.startGesture(
      tester.getCenter(sourceItem),
      kind: PointerDeviceKind.mouse,
    );
    await heldGesture.moveBy(const Offset(3, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('2 个项目'), findsNothing);
    expect(find.text('源和目标文件夹相同'), findsNothing);

    await heldGesture.up();
    await tester.pump();

    final rowEdgeGesture = await tester.startGesture(
      Offset(dragRect.right - 3, tester.getCenter(sourceItem).dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('2 个项目'), findsNothing);
    expect(find.text('源和目标文件夹相同'), findsNothing);

    await rowEdgeGesture.up();
    await tester.pump();
    sourceController.selectAll();
    await tester.pump();

    final gutterGesture = await tester.startGesture(
      tester.getCenter(sourceItem),
    );
    await gutterGesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gutterGesture.moveTo(scrollbarPoint);
    await tester.pump();

    expect(find.text('源和目标文件夹相同'), findsNothing);

    await gutterGesture.up();
    await tester.pump();

    final invalidGesture = await tester.startGesture(
      tester.getCenter(sourceItem),
    );
    await invalidGesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await invalidGesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('invalid-drop-zone'))),
    );
    await tester.pump();

    expect(find.text('不能放到此处'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file-drag-target-feedback')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('pane-drop-highlight-${sourcePane.paneId}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('pane-drop-highlight-${targetPane.paneId}')),
      findsNothing,
    );

    await invalidGesture.up();
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(sourceItem));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(targetWidget));
    await tester.pump();

    final dragFeedback = find.byKey(const ValueKey('file-drag-feedback'));
    final targetFeedback = find.byKey(
      const ValueKey('file-drag-target-feedback'),
    );
    expect(find.text('移动到 target'), findsOneWidget);
    expect(targetFeedback, findsOneWidget);
    expect(
      find.descendant(of: dragFeedback, matching: find.text('移动到 target')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('pane-drop-highlight-${targetPane.paneId}')),
      findsOneWidget,
    );

    await gesture.up();
    await _waitForFileOperations(tester, appState);

    expect(sourceFile.existsSync(), isFalse);
    expect(secondFile.existsSync(), isFalse);
    expect(
      File(p.join(target.path, 'drag-me.txt')).readAsStringSync(),
      'dragged',
    );
    expect(
      File(p.join(target.path, 'and-me.txt')).readAsStringSync(),
      'also dragged',
    );

    final nestedGesture = await tester.startGesture(
      tester.getCenter(find.text('drag-me.txt')),
    );
    await nestedGesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await nestedGesture.moveTo(tester.getCenter(find.text('nested')));
    await tester.pump();

    expect(find.text('移动到 nested'), findsOneWidget);
    expect(
      find.byKey(ValueKey('folder-drop-highlight-${nested.path}')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dragFeedback, matching: find.text('移动到 nested')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('folder-drop-${nested.path}')),
        matching: find.text('移动到 nested'),
      ),
      findsNothing,
    );

    await nestedGesture.up();
    await _waitForFileOperations(tester, appState);

    expect(File(p.join(target.path, 'drag-me.txt')).existsSync(), isFalse);
    expect(
      File(p.join(nested.path, 'drag-me.txt')).readAsStringSync(),
      'dragged',
    );
  });
}

Future<void> _waitForFileOperations(
  WidgetTester tester,
  AppState appState,
) async {
  for (var i = 0; i < 100; i++) {
    if (appState.fileOperations.activeTasks.isEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(appState.fileOperations.activeTasks, isEmpty);
}
