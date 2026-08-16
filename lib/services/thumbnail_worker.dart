import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'thumbnail_ffi.dart';

class ThumbnailWorker {
  ThumbnailWorker._();

  static ThumbnailWorker? _instance;
  static ThumbnailWorker get instance => _instance ??= ThumbnailWorker._();

  static Uint8List? Function(String path, int size, int flags)? extractImpl;

  static void debugReset() {
    _instance?._teardown();
    _instance = null;
  }

  final Map<int, Completer<Uint8List?>> _pending = {};
  ReceivePort? _replyPort;
  SendPort? _workerPort;
  int _nextRequestId = 0;
  Future<void>? _ready;

  Future<Uint8List?> extract({
    required String path,
    required int size,
    required int flags,
  }) async {
    final override = extractImpl;
    if (override != null) {
      try {
        return override(path, size, flags);
      } on Object {
        return null;
      }
    }
    await _ensureReady();
    final id = ++_nextRequestId;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    _workerPort!.send([id, path, size, flags]);
    return completer.future;
  }

  void _teardown() {
    _replyPort?.close();
    _replyPort = null;
    _workerPort = null;
    _ready = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    _nextRequestId = 0;
  }

  Future<void> _ensureReady() => _ready ??= _start();

  Future<void> _start() async {
    final reply = ReceivePort();
    _replyPort = reply;
    final first = Completer<SendPort>();
    reply.listen((message) {
      if (message is SendPort) {
        if (!first.isCompleted) first.complete(message);
        return;
      }
      final list = message as List<Object?>;
      final requestId = list[0] as int;
      final value = list[1] as Uint8List?;
      final completer = _pending.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(value);
      }
    });
    await Isolate.spawn(_workerMain, reply.sendPort);
    _workerPort = await first.future;
  }
}

void _workerMain(SendPort replyPort) {
  final requests = ReceivePort();
  replyPort.send(requests.sendPort);
  requests.listen((raw) {
    final list = raw as List<Object?>;
    final requestId = list[0] as int;
    final path = list[1] as String;
    final size = list[2] as int;
    final flags = list[3] as int;
    Uint8List? result;
    try {
      result = extractFileImagePng(path, size, flags);
    } on Object {
      result = null;
    }
    replyPort.send([requestId, result]);
  });
}
