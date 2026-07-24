import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../models/file_entry.dart';
import 'file_service.dart';

// Native function signatures

typedef _ListDirectoryNative = Pointer<Uint8> Function(
    Pointer<Utf16> path, Pointer<Int32> outSize);
typedef _ListDirectoryDart = Pointer<Uint8> Function(
    Pointer<Utf16> path, Pointer<Int32> outSize);

typedef _FreeDirEntriesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeDirEntriesDart = void Function(Pointer<Uint8> ptr);

class DirectoryService {
  static final _list = DynamicLibrary.process()
      .lookupFunction<_ListDirectoryNative, _ListDirectoryDart>(
          'ListDirectoryEntries');

  static final _free = DynamicLibrary.process()
      .lookupFunction<_FreeDirEntriesNative, _FreeDirEntriesDart>(
          'FreeDirectoryEntries');

  /// Unified directory listing: handles regular paths, Shell virtual
  /// folders (Recycle Bin, This PC), and drive roots.
  ///
  /// Returns an empty list on error.
  static List<FileEntry> listDirectory(String path) {
    final pathPtr = path.toNativeUtf16();
    final outSize = calloc<Int32>();
    final ptr = _list(pathPtr, outSize);

    calloc.free(pathPtr);

    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return [];
    }

    try {
      return _parseBuffer(ptr, outSize.value);
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

    // Sort: directories first, then by name
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

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
}
