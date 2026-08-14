import 'package:flutter/foundation.dart';

enum FileOperationType { copy, move, delete, permanentDelete }

enum FileOperationStatus { queued, running, succeeded, failed, cancelled }

/// Outcome of a single item inside a shell file operation, as reported by
/// the native progress sink (or the dart:io fallback).
class FileOperationItemResult {
  const FileOperationItemResult(this.path, this.hr);

  final String path;

  /// HRESULT: 0 (S_OK) on success, otherwise a Win32/HRESULT failure code.
  /// HRESULTs are negative ints; raw Win32 error codes (dart:io fallback) are
  /// positive — either way success is exactly zero.
  final int hr;

  bool get isSuccess => hr == 0;

  /// Short human-readable error label, e.g. `0x80070005`.
  String get hrLabel {
    if (isSuccess) return '';
    if (hr == -1) return '失败';
    return '0x${hr.toUnsigned(32).toRadixString(16).toUpperCase()}';
  }
}

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
  final List<FileOperationItemResult> _itemResults = [];

  FileOperationStatus get status => _status;
  double get progress => _progress;
  Object? get error => _error;
  bool get cancelRequested => _cancelRequested;

  /// Per-item outcomes reported by the native progress sink.
  List<FileOperationItemResult> get itemResults =>
      List.unmodifiable(_itemResults);

  /// The items that failed, in report order.
  List<FileOperationItemResult> get failures => List.unmodifiable(
    _itemResults.where((result) => !result.isSuccess),
  );

  bool get hasFailures => _itemResults.any((result) => !result.isSuccess);

  void recordItemResults(Iterable<FileOperationItemResult> results) {
    if (results.isEmpty) return;
    _itemResults.addAll(results);
    notifyListeners();
  }

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
