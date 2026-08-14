import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/conflict_dialog.dart';

typedef _ResultGetter = Future<Map<String, ConflictResolution>?> Function();

void main() {
  Future<_ResultGetter> runFlow(WidgetTester tester, List<String> names) async {
    Map<String, ConflictResolution>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await resolveFileConflicts(
                  context,
                  conflictNames: names,
                  destination: r'D:\target',
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return () async => result;
  }

  testWidgets('apply-to-all resolves every remaining conflict in one dialog', (
    tester,
  ) async {
    final getResult = await runFlow(tester, ['a.txt', 'b.txt']);

    expect(find.text('文件冲突'), findsOneWidget);
    expect(find.text('“a.txt”'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('保留两者'));
    await tester.pumpAndSettle();

    expect(find.text('文件冲突'), findsNothing);
    expect(await getResult(), {
      'a.txt': ConflictResolution.keepBoth,
      'b.txt': ConflictResolution.keepBoth,
    });
  });

  testWidgets('each conflict gets its own dialog without apply-to-all', (
    tester,
  ) async {
    final getResult = await runFlow(tester, ['a.txt', 'b.txt']);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('“b.txt”'), findsOneWidget);

    await tester.tap(find.text('替换'));
    await tester.pumpAndSettle();

    expect(find.text('文件冲突'), findsNothing);
    expect(await getResult(), {
      'a.txt': ConflictResolution.skip,
      'b.txt': ConflictResolution.replace,
    });
  });

  testWidgets('cancelling aborts the whole paste', (tester) async {
    final getResult = await runFlow(tester, ['a.txt', 'b.txt']);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('文件冲突'), findsNothing);
    expect(await getResult(), isNull);
  });
}
