import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import 'directory_service.dart';
import 'shell_context_menu.dart';
import 'shell_file_operation.dart';

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

  static Future<void> openContainingFolder(String filePath) async {
    if (!Platform.isWindows) return;
    await Process.run('explorer.exe', ['/select,"$filePath"']);
  }

  static Future<void> deleteEntry(String path, {bool permanent = false}) async {
    if (ShellFileOperation.isAvailable) {
      ShellFileOperation.delete([path], permanent: permanent);
    } else if (permanent) {
      await _deleteEntryIo(path);
    } else {
      throw const FileSystemException(
        'Recycle Bin is unavailable; the file was not deleted',
      );
    }
  }

  static Future<void> deleteEntries(
    List<String> paths, {
    bool permanent = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (paths.isEmpty) return;
    if (ShellFileOperation.isAvailable) {
      await ShellFileOperation.deleteAsync(
        paths,
        permanent: permanent,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    } else if (permanent) {
      for (final path in paths) {
        await _deleteEntryIo(path);
      }
    } else {
      throw const FileSystemException(
        'Recycle Bin is unavailable; no files were deleted',
      );
    }
  }

  static Future<void> _deleteEntryIo(String path) async {
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

  static Future<String> createFile(String parentPath, String name) async {
    final newPath = p.join(parentPath, name);
    await File(newPath).create();
    return newPath;
  }

  static Future<void> copyEntry(String srcPath, String destDir) async {
    if (ShellFileOperation.isAvailable) {
      ShellFileOperation.copy([srcPath], destDir);
    } else {
      await _copyEntryIo(srcPath, destDir);
    }
  }

  static Future<void> copyEntries(
    List<String> srcPaths,
    String destDir, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (srcPaths.isEmpty) return;
    if (ShellFileOperation.isAvailable) {
      await ShellFileOperation.copyAsync(
        srcPaths,
        destDir,
        keepBothOnCollision: keepBothOnCollision,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    } else {
      for (final srcPath in srcPaths) {
        await _copyEntryIo(srcPath, destDir);
      }
    }
  }

  static Future<void> _copyEntryIo(String srcPath, String destDir) async {
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
    if (ShellFileOperation.isAvailable) {
      ShellFileOperation.move([srcPath], destDir);
    } else {
      await _moveEntryIo(srcPath, destDir);
    }
  }

  static Future<void> moveEntries(
    List<String> srcPaths,
    String destDir, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (srcPaths.isEmpty) return;
    if (ShellFileOperation.isAvailable) {
      await ShellFileOperation.moveAsync(
        srcPaths,
        destDir,
        keepBothOnCollision: keepBothOnCollision,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    } else {
      for (final srcPath in srcPaths) {
        await _moveEntryIo(srcPath, destDir);
      }
    }
  }

  static Future<void> _moveEntryIo(String srcPath, String destDir) async {
    final name = p.basename(srcPath);
    final destPath = p.join(destDir, name);
    final type = FileSystemEntity.typeSync(srcPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(srcPath).rename(destPath);
    } else {
      await File(srcPath).rename(destPath);
    }
  }

  /// Reads the metadata needed to add a newly-created filesystem item to an
  /// already-visible pane without re-enumerating the whole directory.
  static FileEntry? inspectEntry(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return null;

      final stat = FileStat.statSync(path);
      final isDirectory = type == FileSystemEntityType.directory;
      return FileEntry(
        name: p.basename(path),
        path: path,
        isDirectory: isDirectory,
        size: isDirectory ? 0 : stat.size,
        modified: stat.modified,
      );
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> openWithDialog(String filePath) async {
    await Process.run('rundll32.exe', ['shell32.dll,OpenAs_RunDLL', filePath]);
  }

  static Future<void> openTerminal(String dirPath) async {
    await Process.run('wt.exe', ['-d', dirPath]);
  }

  static void restoreRecycleBinEntries(
    List<String> parsingNames, {
    List<String?>? destinations,
    bool keepBothOnCollision = false,
  }) {
    if (parsingNames.isEmpty) return;
    ShellFileOperation.restoreRecycleBin(
      parsingNames,
      destinations: destinations,
      keepBothOnCollision: keepBothOnCollision,
    );
  }

  /// Plans restore targets for Recycle Bin [entries]: entries whose original
  /// directory still exists keep a null target (the Shell restores them via
  /// `System.Recycle.DeletedFrom`); entries whose original directory is
  /// missing get [fallback] as their target.
  ///
  /// Returns the missing entries (for UI prompting) and the per-entry
  /// targets, aligned with [entries].
  static ({List<FileEntry> missing, List<String?> destinations})
      planRestoreDestinations(List<FileEntry> entries, {String? fallback}) {
    final missing = <FileEntry>[];
    final destinations = <String?>[];
    for (final entry in entries) {
      final original = entry.originalPath?.trim();
      final originalExists = original != null &&
          original.isNotEmpty &&
          _directoryExists(original);
      if (!originalExists) missing.add(entry);
      destinations.add(originalExists ? null : fallback);
    }
    return (missing: missing, destinations: destinations);
  }

  static bool _directoryExists(String path) {
    try {
      return Directory(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  static bool _exists(String path) {
    try {
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    } on FileSystemException {
      return false;
    }
  }

  /// Detects restore collisions: entries whose target directory exists and
  /// already holds a same-named item. [destinations] (when provided, aligned
  /// with [entries]) overrides the original directory per entry, matching
  /// [planRestoreDestinations].
  static List<FileEntry> planRestoreCollisions(
    List<FileEntry> entries, {
    List<String?>? destinations,
  }) {
    final collisions = <FileEntry>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final targetDir = (destinations?[i] ?? entry.originalPath)?.trim();
      if (targetDir == null || targetDir.isEmpty) continue;
      if (!_directoryExists(targetDir)) continue;
      if (_exists(p.join(targetDir, entry.name))) collisions.add(entry);
    }
    return collisions;
  }

  /// Detects same-name conflicts for copying/moving [sources] into [destDir]:
  /// returns the source paths whose basename already exists in [destDir]
  /// (case-insensitive on Windows). A source that IS the existing item
  /// (same absolute path, e.g. moving within the same folder) is not a
  /// conflict.
  static List<String> detectConflicts(List<String> sources, String destDir) {
    final conflicts = <String>[];
    for (final source in sources) {
      final name = p.basename(source);
      if (name.isEmpty) continue;
      final existing = p.join(destDir, name);
      if (p.equals(
        p.normalize(p.absolute(source)),
        p.normalize(p.absolute(existing)),
      )) {
        continue; // The source itself; not a collision.
      }
      if (_exists(existing)) conflicts.add(source);
    }
    return conflicts;
  }

  /// Shows the native folder-picker dialog; returns the chosen directory or
  /// null when cancelled.
  static String? pickFolder({String? initialPath}) =>
      ShellFileOperation.pickFolder(initialPath: initialPath);

  static void emptyRecycleBin() => ShellFileOperation.emptyRecycleBin();

  static Future<String> createShortcutIn(
    String targetPath,
    String destDir, {
    String? name,
  }) async {
    final targetName = p.basename(targetPath);
    var linkName = name?.trim();
    if (linkName == null || linkName.isEmpty) {
      linkName = '$targetName - 快捷方式';
    }
    if (!linkName.toLowerCase().endsWith('.lnk')) {
      linkName = '$linkName.lnk';
    }
    var linkPath = p.join(destDir, linkName);
    var n = 2;
    while (File(linkPath).existsSync()) {
      final stem = p.basenameWithoutExtension(linkName);
      linkPath = p.join(destDir, '$stem ($n).lnk');
      n++;
    }
    ShellOperations.createShortcut(targetPath, linkPath);
    return linkPath;
  }

  static Future<String> createFolderWithSelection(
    List<String> paths,
    String destDir,
  ) async {
    final base = p.basename(paths.first);
    var dirPath = p.join(destDir, base);
    var n = 2;
    while (Directory(dirPath).existsSync()) {
      dirPath = p.join(destDir, '$base ($n)');
      n++;
    }
    await Directory(dirPath).create();
    await moveEntries(paths, dirPath);
    return dirPath;
  }
}
