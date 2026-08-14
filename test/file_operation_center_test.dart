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
}
