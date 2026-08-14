import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_operation_task.dart';
import 'package:inf_dir/services/file_operation_center.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_task_center.dart';

void main() {
  Future<void> pumpPanel(WidgetTester tester, FileOperationCenter center) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FileTaskCenterPanel(center: center, onClose: () {}),
        ),
      ),
    );
  }

  testWidgets('shows empty state when there are no tasks', (tester) async {
    await pumpPanel(tester, FileOperationCenter());

    expect(find.text('文件任务'), findsOneWidget);
    expect(find.text('没有文件任务'), findsOneWidget);
    expect(find.text('清除已完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders queued, running, succeeded, cancelled and failed rows', (
    tester,
  ) async {
    final center = FileOperationCenter();
    final runningGate = Completer<void>();

    // 1) A blocking copy runs first and reports 50% progress.
    final running = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['C:\\src\\report.txt'],
      destination: 'D:\\backup',
      action: (task) async {
        task.updateProgress(0.5);
        await runningGate.future;
      },
    );
    // 2) B stays queued behind A, then gets cancelled.
    final queued = center.enqueue(
      type: FileOperationType.move,
      sources: const ['C:\\src\\old.txt'],
      destination: 'D:\\backup',
      action: (_) async {},
    );

    await pumpPanel(tester, center);
    await tester.pump();

    // Running row with progress.
    expect(find.text('复制 "report.txt"'), findsOneWidget);
    expect(find.text('到 D:\\backup'), findsNWidgets(2));
    expect(find.text('进行中 50%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);

    // Queued row behind the running one.
    expect(find.text('移动 "old.txt"'), findsOneWidget);
    expect(find.text('排队中'), findsOneWidget);
    expect(find.byTooltip('取消'), findsNWidgets(2));

    // Cancel the queued task; it never starts.
    center.cancel(center.tasks[1].id);
    await tester.pump();
    expect(find.text('已取消'), findsOneWidget);

    // 3) Release A; it succeeds.
    runningGate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);

    // 4) A failing task reports its error. Attach the error listener
    // before pumping so the completed error is handled.
    final failed = center.enqueue(
      type: FileOperationType.permanentDelete,
      sources: const ['C:\\src\\secret.txt'],
      action: (_) async => throw StateError('denied'),
    );
    final failedExpectation = expectLater(failed, throwsStateError);
    await tester.pump();
    await tester.pump();
    expect(find.text('永久删除 "secret.txt"'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(find.text('Bad state: denied'), findsOneWidget);

    await failedExpectation;
    await running;
    await queued;
  });

  testWidgets('cancel button cancels a running task after it returns', (
    tester,
  ) async {
    final center = FileOperationCenter();
    final gate = Completer<void>();
    final future = center.enqueue(
      type: FileOperationType.move,
      sources: const ['C:\\src\\big.iso'],
      destination: 'D:\\backup',
      action: (_) async => gate.future,
    );

    await pumpPanel(tester, center);
    await tester.pump();
    expect(find.text('移动 "big.iso"'), findsOneWidget);

    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    expect(center.tasks.single.cancelRequested, isTrue);
    expect(find.text('已取消'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.byTooltip('移除'), findsOneWidget);

    await future;
  });

  testWidgets('dismiss removes one row and clear finished empties the panel', (
    tester,
  ) async {
    final center = FileOperationCenter();
    final gate = Completer<void>();
    final running = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['C:\\src\\a.txt'],
      action: (_) => gate.future,
    );
    final queued = center.enqueue(
      type: FileOperationType.delete,
      sources: const ['C:\\src\\b.txt'],
      action: (_) async {},
    );

    await pumpPanel(tester, center);
    await tester.pump();

    // Cancel the running task; after it returns both rows are finished.
    await tester.tap(find.byTooltip('取消').first);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byTooltip('移除'), findsNWidgets(2));

    // Dismiss the first (cancelled) row only.
    await tester.tap(find.byTooltip('移除').first);
    await tester.pump();
    expect(find.text('已取消'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);

    // Clear all finished work: the panel falls back to its empty state.
    await tester.tap(find.text('清除已完成'));
    await tester.pump();
    expect(find.text('没有文件任务'), findsOneWidget);
    expect(center.tasks, isEmpty);

    await running;
    await queued;
  });

  testWidgets('top bar button always shows the active count and reports taps', (
    tester,
  ) async {
    final center = FileOperationCenter();

    // Idle: the entry is still visible with a zero badge.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FileTaskCenterButton(center: center, open: false, onTap: () {}),
        ),
      ),
    );
    expect(find.byTooltip('文件任务'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    final gate = Completer<void>();
    var taps = 0;
    center.enqueue(
      type: FileOperationType.copy,
      sources: const ['a'],
      action: (_) => gate.future,
    );
    center.enqueue(
      type: FileOperationType.copy,
      sources: const ['b'],
      action: (_) => gate.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FileTaskCenterButton(
            center: center,
            open: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(FileTaskCenterButton));
    expect(taps, 1);

    // Completing the work drops the badge back to zero.
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });
}
