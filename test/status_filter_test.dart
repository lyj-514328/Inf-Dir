import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_pane.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  testWidgets('filter button shows summary only when a filter is active', (
    tester,
  ) async {
    final state = await _pumpFilePane(tester, [
      fileEntry(r'C:\menu-test\report.txt'),
      fileEntry(r'C:\menu-test\photo.png'),
    ]);
    final pane = state.layoutState.controllerFor(
      state.layoutState.focusedNode,
    )!;

    // 未激活：只有漏斗图标，没有摘要。
    expect(find.byIcon(Symbols.filter_alt), findsOneWidget);
    expect(find.text('关键字'), findsNothing);

    // 打开面板：搜索框 + 两组选项。
    await tester.tap(find.byIcon(Symbols.filter_alt));
    await tester.pumpAndSettle();
    expect(find.text('输入筛选内容'), findsOneWidget);
    expect(find.text('关键字（忽略大小写）'), findsOneWidget);
    expect(find.text('glob（* ? 通配）'), findsOneWidget);
    expect(find.text('正则表达式'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    // 输入筛选词并选择类型。
    await tester.enterText(find.byType(TextField).last, 'photo');
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();

    expect(pane.filterQuery, 'photo');
    expect(pane.entryFilter, EntryFilter.images);

    // 激活后按钮显示：模式图标 + 查询内容 | 类型（不写模式名称）。
    expect(find.text('关键字'), findsNothing);
    expect(find.text('photo'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(pane.visibleEntries.map((e) => e.name), ['photo.png']);
  });

  testWidgets('type-only filter shows the type without a mode summary', (
    tester,
  ) async {
    final state = await _pumpFilePane(tester, [
      fileEntry(r'C:\menu-test\report.txt'),
    ]);
    final pane = state.layoutState.controllerFor(
      state.layoutState.focusedNode,
    )!;

    await tester.tap(find.byIcon(Symbols.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件夹'));
    await tester.pumpAndSettle();

    expect(pane.entryFilter, EntryFilter.folders);
    // 查询为空：不显示匹配模式文字，只显示类型。
    expect(find.text('关键字'), findsNothing);
    expect(find.text('文件夹'), findsOneWidget);
  });

  testWidgets('filter panel closes on outside tap and Esc keeps the query', (
    tester,
  ) async {
    final state = await _pumpFilePane(tester, [
      fileEntry(r'C:\menu-test\report.txt'),
    ]);
    final pane = state.layoutState.controllerFor(
      state.layoutState.focusedNode,
    )!;

    await tester.tap(find.byIcon(Symbols.filter_alt));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'rep');
    await tester.pump();

    // 点击面板外关闭。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('输入筛选内容'), findsNothing);
    expect(pane.filterQuery, 'rep');

    // Esc 关闭。
    await tester.tap(find.byIcon(Symbols.filter_alt));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('输入筛选内容'), findsNothing);
  });
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
