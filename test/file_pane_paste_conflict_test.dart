import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_pane.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory temp;
  late Directory src;
  late Directory dest;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_paste_');
    src = Directory(p.join(temp.path, 'src'))..createSync();
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  File writeSource(String name, [String content = 'source']) =>
      File(p.join(src.path, name))..writeAsStringSync(content);

  File writeDest(String name, [String content = 'dest']) =>
      File(p.join(dest.path, name))..writeAsStringSync(content);

  testWidgets('skip keeps both files and the clipboard intact', (tester) async {
    writeSource('a.txt');
    writeDest('a.txt');
    final state = await _pumpPaste(tester, dest.path);
    state.appState.copyPaths([p.join(src.path, 'a.txt')]);

    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(find.text('文件冲突'), findsOneWidget);
    expect(find.text('“a.txt”'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pump();
    await tester.pump();

    expect(File(p.join(dest.path, 'a.txt')).readAsStringSync(), 'dest');
    expect(state.appState.hasClipboard, isTrue);
    // 让“已跳过”SnackBar 的定时器走完，避免测试结束时有挂起 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('replace overwrites the destination file', (tester) async {
    writeSource('a.txt');
    writeDest('a.txt');
    final state = await _pumpPaste(tester, dest.path);
    state.appState.copyPaths([p.join(src.path, 'a.txt')]);

    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('替换'));
    await tester.pump();
    await tester.pump();

    expect(File(p.join(dest.path, 'a.txt')).readAsStringSync(), 'source');
  });

  testWidgets('cancelling the conflict dialog aborts the paste', (
    tester,
  ) async {
    writeSource('a.txt');
    writeDest('a.txt');
    final state = await _pumpPaste(tester, dest.path);
    state.appState.copyPaths([p.join(src.path, 'a.txt')]);

    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(File(p.join(dest.path, 'a.txt')).readAsStringSync(), 'dest');
    expect(state.appState.hasClipboard, isTrue);
  });

  testWidgets('cut with skip leaves the source file where it was', (
    tester,
  ) async {
    writeSource('a.txt');
    writeDest('a.txt');
    final state = await _pumpPaste(tester, dest.path);
    state.appState.cutPaths([p.join(src.path, 'a.txt')]);

    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳过'));
    await tester.pump();
    await tester.pump();

    expect(File(p.join(src.path, 'a.txt')).readAsStringSync(), 'source');
    expect(File(p.join(dest.path, 'a.txt')).readAsStringSync(), 'dest');
    expect(state.appState.hasClipboard, isTrue);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

class _PasteState {
  _PasteState(this.layoutState, this.appState);

  final LayoutState layoutState;
  final AppState appState;
}

Future<_PasteState> _pumpPaste(WidgetTester tester, String destPath) async {
  final repository = DirectoryRepository(
    cursorFactory: (_, {bool directoriesOnly = false}) async => null,
    hasChildrenProbe: (_) => false,
  );
  final layoutState = LayoutState(repository: repository);
  final appState = AppState(repository: repository);
  final controller = PaneController(destPath, repository: repository);
  addTearDown(controller.dispose);
  addTearDown(layoutState.dispose);
  addTearDown(appState.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LayoutState>.value(value: layoutState),
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pasteIntoPane(context, controller),
              child: const Text('粘贴'),
            ),
          ),
        ),
      ),
    ),
  );
  return _PasteState(layoutState, appState);
}
