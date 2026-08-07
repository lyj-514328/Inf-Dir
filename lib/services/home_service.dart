import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

class RecentFile {
  final String name;
  final String path;
  final DateTime modified;

  const RecentFile({
    required this.name,
    required this.path,
    required this.modified,
  });
}

typedef _GetRecentFilesNative =
    Pointer<Uint8> Function(Int32 limit, Pointer<Int32> outSize);
typedef _GetRecentFilesDart =
    Pointer<Uint8> Function(int limit, Pointer<Int32> outSize);

typedef _FreeRecentFilesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeRecentFilesDart = void Function(Pointer<Uint8> ptr);

/// Data source for the local Home page.
///
/// Recent files come from the Windows "Recent" shell folder, enumerated in
/// most-recently-used order with shortcuts resolved to their targets — the
/// same data Explorer shows on its Home page. Favorites are an Inf-Dir
/// preference, persisted separately so they work for local files and shell
/// links without changing the user's Windows Explorer state.
class HomeService {
  static final _getRecentFilesNative = DynamicLibrary.process()
      .lookupFunction<_GetRecentFilesNative, _GetRecentFilesDart>(
        'GetRecentFiles',
      );

  static final _freeRecentFiles = DynamicLibrary.process()
      .lookupFunction<_FreeRecentFilesNative, _FreeRecentFilesDart>(
        'FreeRecentFiles',
      );

  static List<RecentFile> getRecommendedFiles({int limit = 8}) =>
      getRecentFiles(limit: limit);

  /// Recent files in most-recently-used order. [limit] <= 0 returns all.
  static List<RecentFile> getRecentFiles({int limit = 0}) {
    final fromShell = _recentFromShell(limit);
    if (fromShell != null) return fromShell;
    return _scanRecentShortcuts(limit: limit);
  }

  static List<RecentFile>? _recentFromShell(int limit) {
    final outSize = calloc<Int32>();
    final ptr = _getRecentFilesNative(limit, outSize);
    if (ptr == nullptr || outSize.value < 4) {
      calloc.free(outSize);
      return null;
    }
    try {
      return _parseRecentBuffer(ptr);
    } finally {
      _freeRecentFiles(ptr);
      calloc.free(outSize);
    }
  }

  /// Layout: [count: int32], then per item [path: wstr] [modified: wstr].
  static List<RecentFile> _parseRecentBuffer(Pointer<Uint8> buf) {
    int offset = 0;
    final count = buf.cast<Int32>().value;
    offset += 4;

    final items = <RecentFile>[];
    for (int i = 0; i < count; i++) {
      final (path, o1) = _readWStr(buf, offset);
      offset = o1;
      final (modifiedStr, o2) = _readWStr(buf, offset);
      offset = o2;
      if (path.isEmpty) continue;
      items.add(
        RecentFile(
          name: p.basename(path),
          path: path,
          modified: _parseDate(modifiedStr),
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

  /// Parse "YYYY/MM/DD HH:MM:SS" as produced by the native layer.
  static DateTime _parseDate(String s) {
    if (s.isEmpty) return DateTime.now();
    try {
      final parts = s.split(' ');
      if (parts.length != 2) return DateTime.now();
      final dp = parts[0].split('/');
      final tp = parts[1].split(':');
      if (dp.length != 3 || tp.length != 3) return DateTime.now();
      return DateTime(
        int.parse(dp[0]),
        int.parse(dp[1]),
        int.parse(dp[2]),
        int.parse(tp[0]),
        int.parse(tp[1]),
        int.parse(tp[2]),
      );
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Fallback: scan the physical Recent folder when shell enumeration is
  /// unavailable. Entries are the .lnk files themselves.
  static List<RecentFile> _scanRecentShortcuts({int limit = 0}) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return const [];

    final recentDirectory = Directory(
      p.join(appData, 'Microsoft', 'Windows', 'Recent'),
    );
    if (!recentDirectory.existsSync()) return const [];

    final items = <RecentFile>[];
    for (final entity in recentDirectory.listSync(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.lnk') {
        continue;
      }
      try {
        final stat = entity.statSync();
        items.add(
          RecentFile(
            name: p.basename(entity.path),
            path: entity.path,
            modified: stat.modified,
          ),
        );
      } on FileSystemException {
        // A recent shortcut can disappear while the folder is being read.
      }
    }

    items.sort((a, b) => b.modified.compareTo(a.modified));
    if (limit > 0 && items.length > limit) {
      return items.take(limit).toList(growable: false);
    }
    return items;
  }

  static List<RecentFile> getFavorites({int limit = 50}) {
    final paths = _readFavoritePaths();
    final items = <RecentFile>[];
    for (final path in paths) {
      try {
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.notFound) continue;
        final modified = type == FileSystemEntityType.directory
            ? Directory(path).statSync().modified
            : File(path).statSync().modified;
        items.add(
          RecentFile(name: p.basename(path), path: path, modified: modified),
        );
      } on FileSystemException {
        // Stale favorites are left in storage until the user removes them.
      }
    }
    return items.take(limit).toList(growable: false);
  }

  static bool isFavorite(String path) => _readFavoritePaths().contains(path);

  static void addFavorite(String path) {
    final paths = _readFavoritePaths();
    if (paths.contains(path)) return;
    paths.insert(0, path);
    _writeFavoritePaths(paths);
  }

  static void removeFavorite(String path) {
    final paths = _readFavoritePaths()..remove(path);
    _writeFavoritePaths(paths);
  }

  static File? _preferenceFile() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return File(p.join(appData, 'Inf-Dir', 'home_favorites.json'));
  }

  static List<String> _readFavoritePaths() {
    final file = _preferenceFile();
    if (file == null || !file.existsSync()) return <String>[];
    try {
      final value = jsonDecode(file.readAsStringSync());
      if (value is! List) return <String>[];
      return value
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
    } on Object {
      return <String>[];
    }
  }

  static void _writeFavoritePaths(List<String> paths) {
    final file = _preferenceFile();
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(paths));
    } on FileSystemException {
      // Preferences are best-effort; the Home page remains usable if the
      // profile directory is read-only.
    }
  }
}
