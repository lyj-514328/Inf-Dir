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

/// Reads the Windows Recent folder used by Explorer's Home page.
class HomeService {
  static List<RecentFile> getRecentFiles({int limit = 12}) {
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
}
