import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_operation_task.dart';
import 'package:inf_dir/services/file_operation_center.dart';

void main() {
  test('runs operations serially and records success', () async {
    final center = FileOperationCenter();
    final order = <String>[];
    final firstGate = Completer<void>();

    final first = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['a'],
      destination: 'dest',
      action: (_) async {
        order.add('first-start');
        await firstGate.future;
        order.add('first-end');
      },
    );
    final second = center.enqueue(
      type: FileOperationType.move,
      sources: const ['b'],
      destination: 'dest',
      action: (_) async => order.add('second'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    expect(center.tasks.map((task) => task.status), [
      FileOperationStatus.running,
      FileOperationStatus.queued,
    ]);

    firstGate.complete();
    expect((await first).status, FileOperationStatus.succeeded);
    expect((await second).status, FileOperationStatus.succeeded);
    expect(order, ['first-start', 'first-end', 'second']);
  });

  test('cancels queued work without invoking its action', () async {
    final center = FileOperationCenter();
    final gate = Completer<void>();
    var invoked = false;

    center.enqueue(
      type: FileOperationType.copy,
      sources: const ['a'],
      action: (_) => gate.future,
    );
    final queued = center.enqueue(
      type: FileOperationType.delete,
      sources: const ['b'],
      action: (_) async => invoked = true,
    );

    await Future<void>.delayed(Duration.zero);
    final task = center.tasks[1];
    expect(center.cancel(task.id), isTrue);
    expect((await queued).status, FileOperationStatus.cancelled);
    expect(invoked, isFalse);

    gate.complete();
  });

  test('records failure and propagates the original error', () async {
    final center = FileOperationCenter();
    final error = StateError('failed');

    final future = center.enqueue(
      type: FileOperationType.permanentDelete,
      sources: const ['a'],
      action: (_) async => throw error,
    );

    await expectLater(future, throwsA(same(error)));
    expect(center.tasks.single.status, FileOperationStatus.failed);
    expect(center.tasks.single.error, same(error));
  });

  test('dismiss removes finished tasks but refuses active ones', () async {
    final center = FileOperationCenter();
    var notified = 0;
    center.addListener(() => notified++);
    final gate = Completer<void>();

    final running = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['a'],
      action: (_) => gate.future,
    );
    final done = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['b'],
      action: (_) async {},
    );
    await Future<void>.delayed(Duration.zero);

    final runningTask = center.tasks[0];
    final doneTask = center.tasks[1];
    expect(center.tasks.map((task) => task.status), [
      FileOperationStatus.running,
      FileOperationStatus.queued,
    ]);

    // Active tasks (running or queued) cannot be dismissed.
    expect(center.dismiss(runningTask.id), isFalse);
    expect(center.dismiss(doneTask.id), isFalse);
    expect(center.tasks.length, 2);

    gate.complete();
    await running;
    await done;
    expect(doneTask.status, FileOperationStatus.succeeded);

    expect(center.dismiss(doneTask.id), isTrue);
    expect(center.tasks.map((task) => task.id), [runningTask.id]);
    expect(notified, greaterThan(0));

    expect(center.dismiss('missing'), isFalse);
  });

  test('clearFinished keeps active work and drops it once finished', () async {
    final center = FileOperationCenter();
    final gate = Completer<void>();

    final running = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['a'],
      action: (_) => gate.future,
    );
    final failed = center.enqueue(
      type: FileOperationType.delete,
      sources: const ['b'],
      action: (_) async => throw StateError('boom'),
    );
    final done = center.enqueue(
      type: FileOperationType.copy,
      sources: const ['c'],
      action: (_) async {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.tasks.map((task) => task.status), [
      FileOperationStatus.running,
      FileOperationStatus.queued,
      FileOperationStatus.queued,
    ]);

    // Nothing finished yet: clearing is a no-op.
    center.clearFinished();
    expect(center.tasks.length, 3);
    expect(center.hasFinishedTasks, isFalse);

    final failedExpectation = expectLater(failed, throwsStateError);
    gate.complete();
    await running;
    await failedExpectation;
    await done;

    expect(center.tasks.length, 3);
    expect(center.hasFinishedTasks, isTrue);

    center.clearFinished();
    expect(center.tasks, isEmpty);
    expect(center.hasFinishedTasks, isFalse);
  });
}
