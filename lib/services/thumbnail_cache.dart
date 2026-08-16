import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class ThumbnailCache {
  ThumbnailCache({
    Directory? directory,
    this.maxEntries = 256,
    this.maxBytes = 32 * 1024 * 1024,
  }) : directory = directory ?? Directory(defaultDirectoryPath());

  final Directory directory;
  final int maxEntries;
  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  int _bytes = 0;

  static String defaultDirectoryPath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'thumbs');
  }

  static String cacheKey({
    required String path,
    required int size,
    DateTime? modified,
  }) {
    final stamp = modified?.millisecondsSinceEpoch ?? 0;
    return 'T:$path:$stamp:$size';
  }

  static String fileNameFor(String key) => '${_fnv1aHex(key)}.png';

  Uint8List? getMemory(String key) {
    final cached = _memory.remove(key);
    if (cached == null) return null;
    _memory[key] = cached;
    return cached;
  }

  void putMemory(String key, Uint8List bytes) {
    final previous = _memory.remove(key);
    if (previous != null) _bytes -= previous.length;
    _memory[key] = bytes;
    _bytes += bytes.length;
    _evict();
  }

  Uint8List? getDisk(String key) {
    try {
      final file = File(p.join(directory.path, fileNameFor(key)));
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return null;
      final copy = Uint8List.fromList(bytes);
      putMemory(key, copy);
      return copy;
    } on Object {
      return null;
    }
  }

  Future<void> putDisk(String key, Uint8List bytes) async {
    try {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(p.join(directory.path, fileNameFor(key)));
      await file.writeAsBytes(bytes, flush: true);
    } on Object {
      // 磁盘缓存失败不影响内存命中。
    }
  }

  void clear() {
    _memory.clear();
    _bytes = 0;
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } on Object {
      // 清理失败时至少丢掉内存项。
    }
  }

  int get entryCount => _memory.length;
  int get byteCount => _bytes;

  void _evict() {
    while (_memory.isNotEmpty &&
        (_memory.length > maxEntries || _bytes > maxBytes)) {
      final evicted = _memory.remove(_memory.keys.first);
      if (evicted != null) _bytes -= evicted.length;
    }
  }

  static String _fnv1aHex(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
