import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_pane.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  testWidgets('file pane item menu exposes only implemented commands', (
    tester,
  ) async {
    await _pumpFilePane(tester, [fileEntry(r'C:\menu-test\report.txt')]);

    await tester.tap(find.text('report.txt'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('压缩到'), findsOneWidget);
    await tester.tap(find.text('压缩到'));
    await tester.pumpAndSettle();

    expect(find.text('创建 report.zip'), findsOneWidget);
    expect(find.text('创建 report.7z'), findsOneWidget);
    expect(find.text('创建压缩包'), findsNothing);
    expect(find.text('在新窗口中打开'), findsNothing);
    expect(find.text('发送到'), findsNothing);
    expect(find.text('固定到侧边栏'), findsNothing);
  });

  testWidgets('file pane folder menu tracks clipboard enabled state', (
    tester,
  ) async {
    final state = await _pumpFilePane(tester, const []);

    await tester.tap(find.text('空文件夹'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(_menuInkWell(tester, '粘贴').onTap, isNull);

    await tester.tapAt(const Offset(990, 690));
    await tester.pumpAndSettle();
    state.appState.copyPaths([r'C:\source.txt']);

    await tester.tap(find.text('空文件夹'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(_menuInkWell(tester, '粘贴').onTap, isNotNull);
  });
}

InkWell _menuInkWell(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  expect(row, findsOneWidget);
  return tester.widget<InkWell>(row);
}

Future<_PaneTestState> _pumpFilePane(
  WidgetTester tester,
  List<FileEntry> entries,
) async {
  final repository = DirectoryRepository(
    cursorFactory: (_, {bool directoriesOnly = false}) async =>
        FakeCursor([entries, null]),
    hasChildrenProbe: (_) => false,
  );
  final layoutState = LayoutState(repository: repository);
  final appState = AppState(repository: repository);
  final state = _PaneTestState(layoutState, appState);
  addTearDown(state.dispose);

  await tester.binding.setSurfaceSize(const Size(1000, 700));
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
          body: FilePane(
            paneId: layoutState.focusedNode.paneId!,
            cloudZoneResolver: (_) => false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return state;
}

class _PaneTestState {
  _PaneTestState(this.layoutState, this.appState);

  final LayoutState layoutState;
  final AppState appState;

  void dispose() {
    layoutState.dispose();
    appState.dispose();
  }
}
