import 'package:flutter/foundation.dart';

enum FileOperationType { copy, move, delete, permanentDelete }

enum FileOperationStatus { queued, running, succeeded, failed, cancelled }

/// Mutable state for one user-visible filesystem operation.
class FileOperationTask extends ChangeNotifier {
  FileOperationTask({
    required this.id,
    required this.type,
    required List<String> sources,
    this.destination,
  }) : sources = List.unmodifiable(sources);

  final String id;
  final FileOperationType type;
  final List<String> sources;
  final String? destination;

  FileOperationStatus _status = FileOperationStatus.queued;
  double _progress = 0;
  Object? _error;
  bool _cancelRequested = false;

  FileOperationStatus get status => _status;
  double get progress => _progress;
  Object? get error => _error;
  bool get cancelRequested => _cancelRequested;

  void markRunning() {
    if (_status != FileOperationStatus.queued) return;
    _status = FileOperationStatus.running;
    notifyListeners();
  }

  void updateProgress(double value) {
    final next = value.clamp(0, 1).toDouble();
    if (_progress == next) return;
    _progress = next;
    notifyListeners();
  }

  void requestCancel() {
    if (_status == FileOperationStatus.succeeded ||
        _status == FileOperationStatus.failed ||
        _status == FileOperationStatus.cancelled) {
      return;
    }
    _cancelRequested = true;
    notifyListeners();
  }

  void markSucceeded() {
    _status = FileOperationStatus.succeeded;
    _progress = 1;
    notifyListeners();
  }

  void markFailed(Object error) {
    _error = error;
    _status = FileOperationStatus.failed;
    notifyListeners();
  }

  void markCancelled() {
    _status = FileOperationStatus.cancelled;
    notifyListeners();
  }
}
