import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/file_operation_task.dart';
import 'shell_file_operation.dart';

typedef FileOperationAction = Future<void> Function(FileOperationTask task);

/// Serializes filesystem work and exposes state for a future task-center UI.
///
/// The current Shell executor is synchronous, so cancellation is limited to
/// queued work. The task contract is ready for native progress/cancellation
/// callbacks without changing callers.
class FileOperationCenter extends ChangeNotifier {
  final List<FileOperationTask> _tasks = [];
  final List<_QueuedOperation> _queue = [];
  bool _draining = false;
  int _nextId = 0;

  List<FileOperationTask> get tasks => List.unmodifiable(_tasks);
  Iterable<FileOperationTask> get activeTasks => _tasks.where(
    (task) =>
        task.status == FileOperationStatus.queued ||
        task.status == FileOperationStatus.running,
  );
  bool get hasFinishedTasks => _tasks.any(
    (task) =>
        task.status == FileOperationStatus.succeeded ||
        task.status == FileOperationStatus.failed ||
        task.status == FileOperationStatus.cancelled,
  );

  Future<FileOperationTask> enqueue({
    required FileOperationType type,
    required List<String> sources,
    String? destination,
    required FileOperationAction action,
  }) {
    if (sources.isEmpty) {
      return Future.error(ArgumentError('sources must not be empty'));
    }

    final task = FileOperationTask(
      id: 'file-op-${_nextId++}',
      type: type,
      sources: sources,
      destination: destination,
    );
    final completer = Completer<FileOperationTask>();
    _tasks.add(task);
    _queue.add(_QueuedOperation(task, action, completer));
    notifyListeners();
    unawaited(_drain());
    return completer.future;
  }

  bool cancel(String taskId) {
    final task = _find(taskId);
    if (task == null ||
        (task.status != FileOperationStatus.queued &&
            task.status != FileOperationStatus.running)) {
      return false;
    }
    task.requestCancel();
    if (task.status == FileOperationStatus.running) return true;
    final index = _queue.indexWhere((item) => item.task.id == taskId);
    if (index >= 0) {
      final item = _queue.removeAt(index);
      task.markCancelled();
      item.completer.complete(task);
      notifyListeners();
      return true;
    }
    return false;
  }

  FileOperationTask? _find(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// Removes a finished task from the list. Active tasks (queued/running)
  /// cannot be dismissed; cancel them first.
  bool dismiss(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) return false;
    final task = _tasks[index];
    if (task.status == FileOperationStatus.queued ||
        task.status == FileOperationStatus.running) {
      return false;
    }
    _tasks.removeAt(index);
    notifyListeners();
    return true;
  }

  /// Removes every finished task, keeping queued and running work.
  void clearFinished() {
    final before = _tasks.length;
    _tasks.removeWhere(
      (task) =>
          task.status == FileOperationStatus.succeeded ||
          task.status == FileOperationStatus.failed ||
          task.status == FileOperationStatus.cancelled,
    );
    if (_tasks.length != before) notifyListeners();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        final task = item.task;
        if (task.status == FileOperationStatus.cancelled) continue;
        task.markRunning();
        notifyListeners();
        try {
          await item.action(task);
          if (task.cancelRequested) {
            task.markCancelled();
          } else {
            task.markSucceeded();
          }
          item.completer.complete(task);
        } catch (error, stackTrace) {
          if (task.cancelRequested) {
            task.markCancelled();
            item.completer.complete(task);
          } else {
            if (error is ShellFileOperationException) {
              task.recordItemResults(error.items);
            }
            task.markFailed(error);
            item.completer.completeError(error, stackTrace);
          }
        }
        notifyListeners();
      }
    } finally {
      _draining = false;
    }
  }
}

class _QueuedOperation {
  const _QueuedOperation(this.task, this.action, this.completer);

  final FileOperationTask task;
  final FileOperationAction action;
  final Completer<FileOperationTask> completer;
}
