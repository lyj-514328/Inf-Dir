import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/pane_tab_bar.dart';

TabInfo _tab(String name) =>
    TabInfo(path: FileService.homeViewPath, label: name);

PaneTabBar _tabBar({
  required List<TabInfo> tabs,
  String paneId = 'pane_0',
  int activeIndex = 0,
  ValueChanged<int>? onCloseTab,
  void Function(int from, int insertIndex)? onReorderTab,
  void Function(int index, Offset position)? onTabContextMenu,
  bool Function(TabDragPayload payload, {required bool copy})?
  canAcceptForeignTab,
  void Function(TabDragPayload payload, int insertIndex, bool copy)?
  onForeignTabDropped,
}) {
  return PaneTabBar(
    paneId: paneId,
    tabs: tabs,
    activeIndex: activeIndex,
    onSwitchTab: (_) {},
    onCloseTab: onCloseTab ?? (_) {},
    onAddTab: () {},
    onReorderTab: onReorderTab ?? (_, _) {},
    onTabContextMenu: onTabContextMenu ?? (_, _) {},
    canAcceptForeignTab: canAcceptForeignTab ?? ((_, {required copy}) => true),
    onForeignTabDropped: onForeignTabDropped ?? (_, _, _) {},
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('middle-click closes the tab under the pointer', (tester) async {
    int? closed;
    await tester.pumpWidget(
      _app(_tabBar(tabs: [_tab('A'), _tab('B')], onCloseTab: (i) => closed = i)),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('B')),
      buttons: kMiddleMouseButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('right-click reports the tab index to the context menu', (
    tester,
  ) async {
    int? menuIndex;
    Offset? menuPosition;
    await tester.pumpWidget(
      _app(
        _tabBar(
          tabs: [_tab('A'), _tab('B')],
          onTabContextMenu: (index, position) {
            menuIndex = index;
            menuPosition = position;
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('B')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(menuIndex, 1);
    expect(menuPosition, isNotNull);
  });

  testWidgets('dragging a tab onto another reorders within the pane', (
    tester,
  ) async {
    int? from;
    int? insert;
    await tester.pumpWidget(
      _app(
        _tabBar(
          tabs: [_tab('A'), _tab('B'), _tab('C')],
          onReorderTab: (f, i) {
            from = f;
            insert = i;
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    // 移到 C 的中心：插入位 2（B 之后、C 之前）。
    await gesture.moveTo(tester.getCenter(find.text('C')));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(from, 0);
    expect(insert, 2);
  });

  testWidgets('cross-pane drop moves without Ctrl and copies with Ctrl', (
    tester,
  ) async {
    final drops = <(String, int, bool)>[];
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            _tabBar(paneId: 'pane_1', tabs: [_tab('X'), _tab('Y')]),
            const SizedBox(height: 40),
            _tabBar(
              paneId: 'pane_0',
              tabs: [_tab('A'), _tab('B')],
              onForeignTabDropped: (payload, index, copy) =>
                  drops.add((payload.sourcePaneId, index, copy)),
            ),
          ],
        ),
      ),
    );

    Future<void> dragTab(String label, Offset target) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(label)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    // 移动：未按 Ctrl。
    await dragTab('X', tester.getCenter(find.text('A')));
    expect(drops, [('pane_1', 0, false)]);

    // 复制：按住 Ctrl。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await dragTab('Y', tester.getCenter(find.text('A')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(drops.length, 2);
    expect(drops[1].$1, 'pane_1');
    expect(drops[1].$3, isTrue);
  });

  testWidgets('dropping past the last tab appends at the end', (tester) async {
    int? from;
    int? insert;
    await tester.pumpWidget(
      _app(
        _tabBar(
          tabs: [_tab('A'), _tab('B')],
          onReorderTab: (f, i) {
            from = f;
            insert = i;
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    // + 按钮区域：追加到末尾。
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.add)));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(from, 0);
    expect(insert, 2);
  });

  testWidgets('single tab is not draggable', (tester) async {
    await tester.pumpWidget(_app(_tabBar(tabs: [_tab('A')])));
    expect(
      find.byWidgetPredicate((widget) => widget is Draggable<TabDragPayload>),
      findsNothing,
    );

    await tester.pumpWidget(_app(_tabBar(tabs: [_tab('A'), _tab('B')])));
    expect(
      find.byWidgetPredicate((widget) => widget is Draggable<TabDragPayload>),
      findsNWidgets(2),
    );
  });

  testWidgets('rejected foreign drop flashes and invokes nothing', (
    tester,
  ) async {
    final drops = <(String, int, bool)>[];
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            _tabBar(paneId: 'pane_1', tabs: [_tab('X'), _tab('Y')]),
            const SizedBox(height: 40),
            _tabBar(
              paneId: 'pane_0',
              tabs: [_tab('A'), _tab('B')],
              canAcceptForeignTab: (_, {required copy}) => false,
              onForeignTabDropped: (payload, index, copy) =>
                  drops.add((payload.sourcePaneId, index, copy)),
            ),
          ],
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('X')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('A')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(drops, isEmpty);
  });
}
