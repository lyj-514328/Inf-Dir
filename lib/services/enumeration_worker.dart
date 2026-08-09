import 'dart:async';
import 'dart:isolate';

import '../models/file_entry.dart';
import 'directory_service.dart';

/// 常驻 worker isolate：所有目录枚举 session（begin / nextPage / end）都
/// 在 worker 线程上执行，不再阻塞 UI isolate。
///
/// 为什么必须常驻：Shell 枚举走 COM（IEnumShellItems），COM 对象有线程
/// 亲和性——session 在哪个线程 CoInitializeEx 创建，翻页就必须在哪个线程
/// 调用。因此 begin/nextPage/end 必须全部经由同一 worker 线程，不能用
/// 每页 Isolate.run 的临时隔离区。
class EnumerationWorker {
  EnumerationWorker._();

  static EnumerationWorker? _instance;
  static EnumerationWorker get instance => _instance ??= EnumerationWorker._();

  /// 仅供测试重置：关闭旧 worker 后再重建。
  static void debugReset() {
    _instance?._teardown();
    _instance = null;
  }

  final Map<int, Completer<Object?>> _pending = {};
  ReceivePort? _replyPort;
  SendPort? _workerPort;
  int _nextRequestId = 0;
  Future<void>? _ready;

  void _teardown() {
    _replyPort?.close();
    _replyPort = null;
    _workerPort = null;
    _ready = null;
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
      final value = list[1];
      final completer = _pending.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(value);
      }
    });
    await Isolate.spawn(_workerMain, reply.sendPort);
    _workerPort = await first.future;
  }

  /// 在 worker 线程打开一个枚举 session；返回 sessionId（<=0 表示失败）。
  Future<int> begin(String path, {bool directoriesOnly = false}) async {
    await _ensureReady();
    final result = await _send(const [0], [path, directoriesOnly]);
    return result as int? ?? 0;
  }

  /// 在 worker 线程取下一页；null 表示没有更多（或 session 已关闭）。
  Future<List<FileEntry>?> nextPage(int sessionId, {int count = 100}) async {
    await _ensureReady();
    final result = await _send(const [1], [sessionId, count]);
    return result as List<FileEntry>?;
  }

  /// 幂等结束 session；fire-and-forget，worker 内按消息 FIFO 顺序执行。
  void end(int sessionId) {
    final port = _workerPort;
    if (port == null) return;
    port.send([_nextRequestId, 2, sessionId]);
  }

  Future<Object?> _send(
    List<Object?> cmd,
    List<Object?> args,
  ) async {
    final id = ++_nextRequestId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _workerPort!.send([id, ...cmd, ...args]);
    return completer.future;
  }
}

/// worker 入口：串行处理 begin/nextPage/end，结果按 requestId 回传。
///
/// 消息格式（主 → worker）：
///   [requestId, 0, path, directoriesOnly]           // begin
///   [requestId, 1, sessionId, count]                // nextPage
///   [requestId, 2, sessionId]                       // end（无回传）
/// 回传格式（worker → 主）：
///   [requestId, result]
void _workerMain(SendPort replyPort) {
  final requests = ReceivePort();
  replyPort.send(requests.sendPort);

  requests.listen((raw) {
    final list = raw as List<Object?>;
    final requestId = list[0] as int;
    final cmd = list[1] as int;
    Object? result;
    try {
      switch (cmd) {
        case 0: // begin
          final path = list[2] as String;
          final directoriesOnly = list[3] as bool;
          result = DirectoryService.beginShellEnum(
            path,
            directoriesOnly: directoriesOnly,
          );
        case 1: // nextPage
          final sessionId = list[2] as int;
          final count = list[3] as int;
          result = DirectoryService.getNextEnumPage(sessionId, count: count);
        case 2: // end
          final sessionId = list[2] as int;
          DirectoryService.endShellEnum(sessionId);
          result = null;
      }
    } on Object {
      // FFI 异常视为失败：begin 返回无效 id，nextPage 按枚举结束处理，
      // 不让未捕获异常杀掉 worker。
      result = cmd == 0 ? 0 : null;
    }
    if (cmd != 2) {
      replyPort.send([requestId, result]);
    }
  });
}
