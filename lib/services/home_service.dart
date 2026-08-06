import 'dart:convert';
import 'dart:io';

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

/// Data source for the local Home page.
///
/// Windows maintains the Recent folder for Explorer. Favorites are an
/// Inf-Dir preference, persisted separately so they work for local files and
/// shell links without changing the user's Windows Explorer state.
class HomeService {
  static List<RecentFile> getRecommendedFiles({int limit = 8}) =>
      getRecentFiles(limit: limit);

  static List<RecentFile> getRecentFiles({int limit = 50}) {
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
            name: p.basenameWithoutExtension(entity.path),
            path: entity.path,
            modified: stat.modified,
          ),
        );
      } on FileSystemException {
        // A recent shortcut can disappear while the folder is being read.
      }
    }

    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items.take(limit).toList(growable: false);
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
          RecentFile(
            name: p.basenameWithoutExtension(path),
            path: path,
            modified: modified,
          ),
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
