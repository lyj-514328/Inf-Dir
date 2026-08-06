import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import 'directory_service.dart';

class FileService {
  /// Virtual path used by the Files home page. It is not a filesystem path.
  static const String homeViewPath = 'shell:InfDirHome';

  static Future<List<FileEntry>> listDirectory(String dirPath) async {
    return DirectoryService.listDirectory(dirPath);
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

  /// Recycle Bin virtual path constants.
  static const String recycleBinShellPath = 'shell:RecycleBinFolder';
  static const String recycleBinClsidPath =
      '::{645FF040-5081-101B-9F08-00AA002F954E}';

  /// My Computer (This PC) virtual path constant.
  static const String myComputerClsidPath =
      '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';

  /// Returns true if [path] is a virtual shell path (Recycle Bin, etc.)
  /// rather than a regular filesystem path.
  static bool isSpecialPath(String path) {
    return path.startsWith('shell:') || path.startsWith('::');
  }

  static bool isHomePath(String path) => path == homeViewPath;

  /// Returns true if [path] points to the Recycle Bin.
  static bool isRecycleBinPath(String path) {
    return path.startsWith(recycleBinShellPath) ||
        path.startsWith(recycleBinClsidPath);
  }

  /// Returns true if [path] points to "This PC" (My Computer).
  static bool isMyComputerPath(String path) {
    return path.startsWith(myComputerClsidPath) ||
        path.startsWith('shell:MyComputerFolder');
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

  /// Creates an empty file and returns its full path. Keeping this operation
  /// in the service makes the command bar testable without tying it to a
  /// platform-specific shell implementation.
  static Future<String> createTextFile(String parentPath, String name) async {
    final newPath = p.join(parentPath, name);
    await File(newPath).create();
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
