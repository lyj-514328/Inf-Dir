import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';

class FileService {
  static Future<List<FileEntry>> listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final List<FileEntry> entries = [];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          entries.add(FileEntry(
            name: p.basename(entity.path),
            path: entity.path,
            isDirectory: entity is Directory,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
    } catch (_) {}

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  static List<String> getDrives() {
    final drives = <String>[];
    for (int i = 65; i <= 90; i++) {
      final letter = String.fromCharCode(i);
      if (Directory('$letter:\\').existsSync()) {
        drives.add('$letter:\\');
      }
    }
    return drives;
  }

  static String get homeDirectory =>
      Platform.environment['USERPROFILE'] ?? 'C:\\';

  static String get desktopPath => p.join(homeDirectory, 'Desktop');
  static String get documentsPath => p.join(homeDirectory, 'Documents');
  static String get downloadsPath => p.join(homeDirectory, 'Downloads');
  static String get picturesPath => p.join(homeDirectory, 'Pictures');
  static String get musicPath => p.join(homeDirectory, 'Music');
  static String get videosPath => p.join(homeDirectory, 'Videos');

  static Future<void> openFile(String filePath) async {
    await Process.run('cmd', ['/c', 'start', '', filePath]);
  }

  static Future<void> deleteEntry(String path) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  static Future<void> renameEntry(String oldPath, String newName) async {
    final newPath = p.join(p.dirname(oldPath), newName);
    final type = FileSystemEntity.typeSync(oldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
  }

  static Future<String> createFolder(String parentPath, String name) async {
    final newPath = p.join(parentPath, name);
    await Directory(newPath).create(recursive: true);
    return newPath;
  }

  static Future<void> copyEntry(String srcPath, String destDir) async {
    final name = p.basename(srcPath);
    final destPath = p.join(destDir, name);
    final type = FileSystemEntity.typeSync(srcPath);
    if (type == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(srcPath), Directory(destPath));
    } else {
      await File(srcPath).copy(destPath);
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else {
        await File(entity.path).copy(newPath);
      }
    }
  }

  static Future<void> moveEntry(String srcPath, String destDir) async {
    final name = p.basename(srcPath);
    final destPath = p.join(destDir, name);
    final type = FileSystemEntity.typeSync(srcPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(srcPath).rename(destPath);
    } else {
      await File(srcPath).rename(destPath);
    }
  }
}
