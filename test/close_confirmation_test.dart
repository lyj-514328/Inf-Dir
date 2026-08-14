import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/close_confirmation.dart';

typedef _ResultGetter = Future<bool> Function();

void main() {
  Future<_ResultGetter> runFlow(
    WidgetTester tester,
    int activeCount,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmCloseWithActiveTasks(
                  context,
                  activeCount,
                );
              },
              child: const Text('关闭'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    return () async => result!;
  }

  testWidgets('no active tasks closes without a dialog', (tester) async {
    final getResult = await runFlow(tester, 0);

    expect(find.text('文件操作正在进行'), findsNothing);
    expect(await getResult(), isTrue);
  });

  testWidgets('lists the active count and cancels', (tester) async {
    final getResult = await runFlow(tester, 2);

    expect(find.text('文件操作正在进行'), findsOneWidget);
    expect(
      find.text('有 2 个文件操作尚未完成。关闭窗口将中断这些操作，部分文件可能不完整。'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await getResult(), isFalse);
  });

  testWidgets('singular wording for one task and confirm closes', (
    tester,
  ) async {
    final getResult = await runFlow(tester, 1);

    expect(
      find.text('有 1 个文件操作尚未完成。关闭窗口将中断该操作，部分文件可能不完整。'),
      findsOneWidget,
    );

    await tester.tap(find.text('仍然关闭'));
    await tester.pumpAndSettle();
    expect(await getResult(), isTrue);
  });

  testWidgets('dismissing the dialog keeps the window open', (tester) async {
    final getResult = await runFlow(tester, 1);

    // 点击遮罩关闭对话框 → 视为不放行。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(await getResult(), isFalse);
  });
}
