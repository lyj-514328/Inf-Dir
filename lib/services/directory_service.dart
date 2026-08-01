import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../models/file_entry.dart';

// Native function signatures

typedef _ListDirectoryNative = Pointer<Uint8> Function(
    Pointer<Utf16> path, Pointer<Int32> outSize);
typedef _ListDirectoryDart = Pointer<Uint8> Function(
    Pointer<Utf16> path, Pointer<Int32> outSize);

typedef _FreeDirEntriesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeDirEntriesDart = void Function(Pointer<Uint8> ptr);

typedef _GetDisplayNameNative = Pointer<Utf16> Function(Pointer<Utf16> path);
typedef _GetDisplayNameDart = Pointer<Utf16> Function(Pointer<Utf16> path);

// Session-based paged enumeration
typedef _BeginShellEnumNative = Int32 Function(
    Pointer<Utf16> path, Int32 directoriesOnly);
typedef _BeginShellEnumDart = int Function(
    Pointer<Utf16> path, int directoriesOnly);

typedef _GetNextEnumPageNative = Pointer<Uint8> Function(
    Int32 sessionId, Int32 count, Pointer<Int32> outSize);
typedef _GetNextEnumPageDart = Pointer<Uint8> Function(
    int sessionId, int count, Pointer<Int32> outSize);

typedef _EndShellEnumNative = Void Function(Int32 sessionId);
typedef _EndShellEnumDart = void Function(int sessionId);

class DirectoryService {
  static final _list = DynamicLibrary.process()
      .lookupFunction<_ListDirectoryNative, _ListDirectoryDart>(
          'ListDirectoryEntries');

  static final _free = DynamicLibrary.process()
      .lookupFunction<_FreeDirEntriesNative, _FreeDirEntriesDart>(
          'FreeDirectoryEntries');

  static final _getDisplayName = DynamicLibrary.process()
      .lookupFunction<_GetDisplayNameNative, _GetDisplayNameDart>(
          'GetShellDisplayName');

  static final _beginEnum = DynamicLibrary.process()
      .lookupFunction<_BeginShellEnumNative, _BeginShellEnumDart>(
          'BeginShellEnum');

  static final _nextPage = DynamicLibrary.process()
      .lookupFunction<_GetNextEnumPageNative, _GetNextEnumPageDart>(
          'GetNextEnumPage');

  static final _endEnum = DynamicLibrary.process()
      .lookupFunction<_EndShellEnumNative, _EndShellEnumDart>(
          'EndShellEnum');

  /// Cache for shell display names to avoid repeated FFI calls.
  static final Map<String, String> _displayNameCache = {};

  /// Get the friendly display name for any path (including Shell CLSIDs).
  /// Falls back to the path itself if the shell cannot resolve it.
  static String getDisplayName(String path) {
    final cached = _displayNameCache[path];
    if (cached != null) return cached;

    final pathPtr = path.toNativeUtf16();
    final resultPtr = _getDisplayName(pathPtr);
    calloc.free(pathPtr);

    if (resultPtr == nullptr) return path;

    final name = resultPtr.toDartString();
    // Free the CoTaskMem-allocated string
    _free(resultPtr.cast<Uint8>());

    _displayNameCache[path] = name;
    return name;
  }

  /// Unified directory listing: handles regular paths, Shell virtual
  /// folders (Recycle Bin, This PC), and drive roots.
  ///
  /// Returns an empty list on error.
  static List<FileEntry> listDirectory(String path,
      {void Function(int ffiMs, int parseMs, int sortMs, int count)? onPerf}) {
    final pathPtr = path.toNativeUtf16();
    final outSize = calloc<Int32>();

    final ffiSw = Stopwatch()..start();
    final ptr = _list(pathPtr, outSize);
    ffiSw.stop();

    calloc.free(pathPtr);

    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return [];
    }

    try {
      final parseSw = Stopwatch()..start();
      final raw = _parseBuffer(ptr, outSize.value);
      parseSw.stop();

      final sortSw = Stopwatch()..start();
      // Sort: directories first, then by name
      raw.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      sortSw.stop();

      onPerf?.call(
        ffiSw.elapsedMilliseconds,
        parseSw.elapsedMilliseconds,
        sortSw.elapsedMilliseconds,
        raw.length,
      );

      return raw;
    } finally {
      _free(ptr);
      calloc.free(outSize);
    }
  }

  /// Parse the flat binary buffer from ListDirectoryEntries.
  ///
  /// Layout:
  ///   [count: int32]
  ///   for each:
  ///     [nameLen: int32] [nameChars: wchar_t[]]
  ///     [pathLen: int32] [pathChars: wchar_t[]]
  ///     [isDirectory: int32]
  ///     [hasChildren: int32]
  ///     [sizeBytes: int64]
  ///     [modifiedDateLen: int32] [modifiedDateChars: wchar_t[]]
  ///     [isRecycleBinItem: int32]
  ///     [originalPathLen: int32] [originalPathChars: wchar_t[]]
  ///     [recycleDateLen: int32] [recycleDateChars: wchar_t[]]
  ///     [parsingNameLen: int32] [parsingNameChars: wchar_t[]]
  static List<FileEntry> _parseBuffer(Pointer<Uint8> buf, int totalSize) {
    final items = <FileEntry>[];
    int offset = 0;

    final count = buf.cast<Int32>().value;
    offset += 4;

    for (int i = 0; i < count; i++) {
      final (name, o1) = _readWStr(buf, offset);
      offset = o1;
      final (filePath, o2) = _readWStr(buf, offset);
      offset = o2;

      int isDir = 0;
      if (offset + 4 <= totalSize) {
        isDir = buf.elementAt(offset).cast<Int32>().value;
        offset += 4;
      }

      int hasChildren = 0;
      if (offset + 4 <= totalSize) {
        hasChildren = buf.elementAt(offset).cast<Int32>().value;
        offset += 4;
      }

      int sizeBytes = 0;
      if (offset + 8 <= totalSize) {
        sizeBytes = buf.elementAt(offset).cast<Int64>().value;
        offset += 8;
      }

      final (modifiedDateStr, o3) = _readWStr(buf, offset);
      offset = o3;

      int isRecycle = 0;
      if (offset + 4 <= totalSize) {
        isRecycle = buf.elementAt(offset).cast<Int32>().value;
        offset += 4;
      }

      final (originalPath, o4) = _readWStr(buf, offset);
      offset = o4;
      final (recycleDateStr, o5) = _readWStr(buf, offset);
      offset = o5;
      final (parsingName, o6) = _readWStr(buf, offset);
      offset = o6;

      // Drive roots show "Windows (C:)" as name but we want path to be C:\
      // isRecycleBinItem check tells us whether this is a recycle bin entry
      final itemPath = parsingName.isNotEmpty ? parsingName : filePath;

      items.add(FileEntry(
        name: name.isNotEmpty ? name : '(unknown)',
        path: itemPath,
        isDirectory: isDir != 0,
        hasChildren: hasChildren != 0,
        size: sizeBytes,
        modified: _parseDate(modifiedDateStr),
        originalPath: originalPath.isNotEmpty ? originalPath : null,
        recycleDate: recycleDateStr.isNotEmpty ? recycleDateStr : null,
        parsingName: parsingName.isNotEmpty ? parsingName : null,
      ));
    }

    return items;
  }

  /// Read a counted wchar_t string from buffer.
  static (String, int) _readWStr(Pointer<Uint8> buf, int offset) {
    final len = buf.elementAt(offset).cast<Int32>().value;
    offset += 4;
    if (len <= 0) return ('', offset);
    final chars = <int>[];
    for (int i = 0; i < len; i++) {
      final low = buf.elementAt(offset + i * 2).value;
      final high = buf.elementAt(offset + i * 2 + 1).value;
      chars.add((high << 8) | low);
    }
    offset += len * 2;
    return (String.fromCharCodes(chars), offset);
  }

  /// Parse "YYYY/MM/DD HH:MM:SS" date string.
  static DateTime _parseDate(String s) {
    if (s.isEmpty) return DateTime.now();
    try {
      final parts = s.split(' ');
      if (parts.length != 2) return DateTime.now();
      final dp = parts[0].split('/');
      final tp = parts[1].split(':');
      if (dp.length != 3 || tp.length != 3) return DateTime.now();
      return DateTime(
        int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]),
        int.parse(tp[0]), int.parse(tp[1]), int.parse(tp[2]),
      );
    } catch (_) {
      return DateTime.now();
    }
  }

  // -- Session-based paged enumeration --

  /// Begin a shell enumeration session. Returns a session ID (>0) or -1 on failure.
  /// If [directoriesOnly] is true, files are skipped at the C layer.
  static int beginShellEnum(String path, {bool directoriesOnly = false}) {
    final pathPtr = path.toNativeUtf16();
    final id = _beginEnum(pathPtr, directoriesOnly ? 1 : 0);
    calloc.free(pathPtr);
    return id;
  }

  /// Get the next page of items. Returns null when no more items.
  /// [count] is the maximum number of items to fetch.
  static List<FileEntry>? getNextEnumPage(int sessionId,
      {int count = 100}) {
    final outSize = calloc<Int32>();
    final ptr = _nextPage(sessionId, count, outSize);

    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return null;
    }

    try {
      return _parseBuffer(ptr, outSize.value);
    } finally {
      _free(ptr);
      calloc.free(outSize);
    }
  }

  /// End a shell enumeration session.
  static void endShellEnum(int sessionId) {
    _endEnum(sessionId);
  }

  /// Open a paged enumeration cursor for [path].
  /// Returns null when the native begin call fails.
  static DirectoryCursor? openCursor(String path,
      {bool directoriesOnly = false}) {
    final id = beginShellEnum(path, directoriesOnly: directoriesOnly);
    if (id <= 0) return null;
    return _ShellDirectoryCursor._(id);
  }
}

/// 封装一次原生枚举 session 的小型幂等对象。
///
/// - close 可以重复调用；
/// - close 后 nextPage 直接返回 null；
/// - session id 只存在于 cursor 内部，上层不保存全局 session id。
abstract interface class DirectoryCursor {
  /// 取下一页；返回 null 表示没有更多（或 cursor 已关闭）。
  List<FileEntry>? nextPage({int count = 100});

  /// 幂等关闭底层 session。
  void close();

  bool get isOpen;
}

class _ShellDirectoryCursor implements DirectoryCursor {
  int _sessionId;

  _ShellDirectoryCursor._(this._sessionId);

  @override
  bool get isOpen => _sessionId > 0;

  @override
  List<FileEntry>? nextPage({int count = 100}) {
    if (_sessionId <= 0) return null;
    return DirectoryService.getNextEnumPage(_sessionId, count: count);
  }

  @override
  void close() {
    if (_sessionId <= 0) return;
    DirectoryService.endShellEnum(_sessionId);
    _sessionId = -1;
  }
}
