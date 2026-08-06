import 'dart:async';
import 'dart:typed_data';

import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/directory_service.dart';
import 'package:inf_dir/utils/path_utils.dart';

/// 可控的 fake cursor：按预设页返回，记录翻页次数与关闭状态。
class FakeCursor implements DirectoryCursor {
  FakeCursor(this.pages);

  /// 每个元素是一页；null 表示枚举结束。
  final List<List<FileEntry>?> pages;
  int nextPageCalls = 0;
  bool _open = true;

  @override
  bool get isOpen => _open;

  @override
  List<FileEntry>? nextPage({int count = 100}) {
    nextPageCalls++;
    if (!_open) return null;
    if (nextPageCalls > pages.length) return null;
    return pages[nextPageCalls - 1];
  }

  @override
  void close() {
    _open = false;
  }
}

/// 按路径供给 fake cursor 的工厂。路径不在表中 → begin 失败（返回 null）。
class FakeCursorSource {
  final Map<String, List<List<FileEntry>?>> data;
  final List<FakeCursor> created = [];

  FakeCursorSource(Map<String, List<List<FileEntry>?>> raw)
      : data = {for (final e in raw.entries) normPath(e.key): e.value};

  DirectoryCursor? open(String path, {bool directoriesOnly = false}) {
    final pages = data[normPath(path)];
    if (pages == null) return null;
    final cursor = FakeCursor(pages);
    created.add(cursor);
    return cursor;
  }

  FakeCursor get last => created.last;
}

/// 手动推进的帧边界：loadChildren 在 yieldFrame 处挂起，测试用 pump 放行。
class ManualPump {
  final _waiters = <Completer<void>>[];

  Future<void> yieldFrame() {
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  int get pending => _waiters.length;

  void pump([int n = 1]) {
    for (var i = 0; i < n && _waiters.isNotEmpty; i++) {
      _waiters.removeAt(0).complete();
    }
  }

  void pumpAll() => pump(_waiters.length);
}

/// 让 microtask 队列与已完成的 future 链推进若干轮。
Future<void> settle([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>(() {});
  }
}

/// 交替 settle + pump，直到没有挂起的帧等待（或达到上限）。
Future<void> runToIdle(ManualPump pump) async {
  for (var i = 0; i < 100; i++) {
    await settle();
    if (pump.pending == 0) return;
    pump.pumpAll();
  }
  await settle();
}

FileEntry dirEntry(
  String path, {
  bool hasChildren = false,
  List<int>? nameSortKey,
}) {
  final name = path.replaceAll('/', '\\').split('\\').last;
  return FileEntry(
    name: name.isEmpty ? path : name,
    nameSortKey: nameSortKey == null ? null : Uint8List.fromList(nameSortKey),
    path: path,
    isDirectory: true,
    hasChildren: hasChildren,
    size: 0,
    modified: DateTime(2025),
  );
}

FileEntry fileEntry(String path, {List<int>? nameSortKey}) {
  final name = path.replaceAll('/', '\\').split('\\').last;
  return FileEntry(
    name: name,
    nameSortKey: nameSortKey == null ? null : Uint8List.fromList(nameSortKey),
    path: path,
    isDirectory: false,
    size: 1,
    modified: DateTime(2025),
  );
}
