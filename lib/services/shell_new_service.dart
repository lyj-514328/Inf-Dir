import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// A file type registered for Explorer's "New >" menu, parsed from the
/// ShellNew registry subkey. Mirrors Windows Explorer's own menu: creating
/// the item writes [data] or copies [templatePath] into a new file, or runs
/// [command] in the target folder when present.
class ShellNewEntry {
  final String extension;
  final String name;
  final String templatePath;
  final String command;
  final Uint8List data;
  final Uint8List iconPng;

  const ShellNewEntry({
    required this.extension,
    required this.name,
    required this.templatePath,
    required this.command,
    required this.data,
    required this.iconPng,
  });

  bool get hasIcon => iconPng.isNotEmpty;
  bool get isCommandBased => command.isNotEmpty;
}

typedef _GetShellNewEntriesNative =
    Pointer<Uint8> Function(Pointer<Int32> outSize);
typedef _GetShellNewEntriesDart = Pointer<Uint8> Function(Pointer<Int32> outSize);

typedef _FreeShellNewEntriesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeShellNewEntriesDart = void Function(Pointer<Uint8> ptr);

/// Enumerates the "New" menu entries from HKCR extension keys (ShellNew
/// subkeys), the same source Explorer's "New >" submenu uses. Results are
/// cached for the session; call [invalidateCache] after installs that may
/// register new file types.
class ShellNewService {
  ShellNewService._();

  static final _getEntries = DynamicLibrary.process()
      .lookupFunction<_GetShellNewEntriesNative, _GetShellNewEntriesDart>(
        'GetShellNewEntries',
      );
  static final _freeEntries = DynamicLibrary.process()
      .lookupFunction<_FreeShellNewEntriesNative, _FreeShellNewEntriesDart>(
        'FreeShellNewEntries',
      );

  static List<ShellNewEntry>? _cache;

  static List<ShellNewEntry> getEntries() {
    final cached = _cache;
    if (cached != null) return cached;

    final outSize = calloc<Int32>();
    final ptr = _getEntries(outSize);
    if (ptr == nullptr || outSize.value < 4) {
      calloc.free(outSize);
      _cache = const [];
      return _cache!;
    }
    try {
      _cache = _parseBuffer(ptr);
      return _cache!;
    } finally {
      _freeEntries(ptr);
      calloc.free(outSize);
    }
  }

  static void invalidateCache() {
    _cache = null;
  }

  /// Layout: [count: int32], then per item
  /// [ext: wstr] [name: wstr] [template: wstr] [command: wstr]
  /// [dataLen: int32] [data: uint8[]] [pngLen: int32] [png: uint8[]].
  static List<ShellNewEntry> _parseBuffer(Pointer<Uint8> buf) {
    int offset = 0;
    final count = buf.cast<Int32>().value;
    offset += 4;

    final items = <ShellNewEntry>[];
    for (int i = 0; i < count; i++) {
      final (ext, o1) = _readWStr(buf, offset);
      offset = o1;
      final (name, o2) = _readWStr(buf, offset);
      offset = o2;
      final (template, o3) = _readWStr(buf, offset);
      offset = o3;
      final (command, o4) = _readWStr(buf, offset);
      offset = o4;
      final (data, o5) = _readBytes(buf, offset);
      offset = o5;
      final (iconPng, o6) = _readBytes(buf, offset);
      offset = o6;

      if (ext.isEmpty) continue;
      items.add(
        ShellNewEntry(
          extension: ext,
          name: name.isEmpty ? '$ext 文件' : name,
          templatePath: template,
          command: command,
          data: data,
          iconPng: iconPng,
        ),
      );
    }
    return items;
  }

  static (String, int) _readWStr(Pointer<Uint8> buf, int offset) {
    final len = (buf + offset).cast<Int32>().value;
    offset += 4;
    if (len <= 0) return ('', offset);
    final chars = <int>[];
    for (int i = 0; i < len; i++) {
      final low = (buf + offset + i * 2).value;
      final high = (buf + offset + i * 2 + 1).value;
      chars.add((high << 8) | low);
    }
    offset += len * 2;
    return (String.fromCharCodes(chars), offset);
  }

  static (Uint8List, int) _readBytes(Pointer<Uint8> buf, int offset) {
    final len = (buf + offset).cast<Int32>().value;
    offset += 4;
    if (len <= 0) return (Uint8List(0), offset);
    final bytes = Uint8List(len);
    for (int i = 0; i < len; i++) {
      bytes[i] = (buf + offset + i).value;
    }
    offset += len;
    return (bytes, offset);
  }

  /// Creates a new item in [parentPath] from a ShellNew registration.
  /// Returns the created path, or null when a launch command was run instead
  /// of a file being created.
  static Future<String?> create(
    String parentPath,
    ShellNewEntry entry,
    String displayName,
  ) async {
    if (entry.isCommandBased) {
      final parts = _splitCommand(entry.command);
      await Process.start(
        parts.command,
        parts.arguments,
        workingDirectory: parentPath,
        runInShell: true,
      );
      return null;
    }

    final fullPath = p.join(
      parentPath,
      displayName.endsWith(entry.extension)
          ? displayName
          : '$displayName${entry.extension}',
    );
    if (entry.data.isNotEmpty) {
      await File(fullPath).writeAsBytes(entry.data, flush: true);
    } else if (entry.templatePath.isNotEmpty) {
      await File(entry.templatePath).copy(fullPath);
    } else {
      await File(fullPath).create();
    }
    return fullPath;
  }

  /// Splits a ShellNew command line into executable and arguments.
  static ({String command, List<String> arguments}) _splitCommand(
    String commandLine,
  ) {
    final parts = _splitCommandLine(commandLine);
    if (parts.isEmpty) return (command: commandLine, arguments: const []);
    return (command: parts.first, arguments: parts.skip(1).toList());
  }

  /// Minimal Windows command-line splitting: honors double-quoted segments.
  static List<String> _splitCommandLine(String input) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }
}
