import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../models/file_operation_task.dart';
import 'directory_service.dart';
import 'shell_context_menu.dart';
import 'shell_file_operation.dart';

class FileService {
  static void _shellDebugLog(String message) {
    try {
      final logFile = File(
        p.join(Directory.systemTemp.path, 'inf-dir-shell.log'),
      );
      logFile.writeAsStringSync(
        '${DateTime.now().toIso8601String()} dart $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Diagnostics must never affect normal file opening.
    }
  }

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
    return path.startsWith('shell:') ||
        path.startsWith('::') ||
        path.startsWith(r'\\SHELL\');
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

  static Future<void> openShellItem(String path) async {
    final opened = ShellFileOperation.openShellItem(path);
    _shellDebugLog('open path=${path.replaceAll('\n', ' ')} result=$opened');
    if (!opened) {
      // Keep the existing fallback for non-Windows test environments.
      await openFile(path);
      _shellDebugLog('fallback cmd-start path=${path.replaceAll('\n', ' ')}');
    }
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

  static Future<List<FileOperationItemResult>> deleteEntries(
    List<String> paths, {
    bool permanent = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (paths.isEmpty) return const [];
    if (ShellFileOperation.isAvailable) {
      return ShellFileOperation.deleteAsync(
        paths,
        permanent: permanent,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    }
    if (permanent) {
      final results = <FileOperationItemResult>[];
      for (final path in paths) {
        try {
          await _deleteEntryIo(path);
          results.add(FileOperationItemResult(path, 0));
        } catch (error) {
          results.add(FileOperationItemResult(path, _errorHr(error)));
        }
      }
      return results;
    }
    throw const FileSystemException(
      'Recycle Bin is unavailable; no files were deleted',
    );
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

  static Future<List<FileOperationItemResult>> copyEntries(
    List<String> srcPaths,
    String destDir, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (srcPaths.isEmpty) return const [];
    if (ShellFileOperation.isAvailable) {
      return ShellFileOperation.copyAsync(
        srcPaths,
        destDir,
        keepBothOnCollision: keepBothOnCollision,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    }
    final results = <FileOperationItemResult>[];
    for (final srcPath in srcPaths) {
      try {
        await _copyEntryIo(srcPath, destDir);
        results.add(FileOperationItemResult(srcPath, 0));
      } catch (error) {
        results.add(FileOperationItemResult(srcPath, _errorHr(error)));
      }
    }
    return results;
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

  static Future<List<FileOperationItemResult>> moveEntries(
    List<String> srcPaths,
    String destDir, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (srcPaths.isEmpty) return const [];
    if (ShellFileOperation.isAvailable) {
      return ShellFileOperation.moveAsync(
        srcPaths,
        destDir,
        keepBothOnCollision: keepBothOnCollision,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    }
    final results = <FileOperationItemResult>[];
    for (final srcPath in srcPaths) {
      try {
        await _moveEntryIo(srcPath, destDir);
        results.add(FileOperationItemResult(srcPath, 0));
      } catch (error) {
        results.add(FileOperationItemResult(srcPath, _errorHr(error)));
      }
    }
    return results;
  }

  /// Converts a dart:io failure into an HRESULT-shaped code so the rest of
  /// the app can treat success as exactly zero.
  static int _errorHr(Object error) {
    if (error is FileSystemException) {
      final osError = error.osError;
      if (osError != null && osError.errorCode != 0) {
        final code = osError.errorCode;
        // HRESULT_FROM_WIN32: positive Win32 codes become 0x8007xxxx.
        return code < 0 ? code : (code & 0xFFFF) | 0x80070000;
      }
    }
    return -1;
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
  /// already-visible pane or cache without re-enumerating the whole
  /// directory. Carries the native natural-sort key when available so the
  /// inserted entry sorts like enumerated ones.
  static FileEntry? inspectEntry(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return null;

      final stat = FileStat.statSync(path);
      final isDirectory = type == FileSystemEntityType.directory;
      return FileEntry(
        name: p.basename(path),
        nameSortKey: ShellFileOperation.buildNameSortKey(p.basename(path)),
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

  /// Restores Recycle Bin items on the native worker thread, reporting
  /// progress and per-item outcomes through the task center protocol.
  static Future<List<FileOperationItemResult>> restoreRecycleBinEntriesAsync(
    List<String> parsingNames, {
    List<String?>? destinations,
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) {
    if (parsingNames.isEmpty) return Future.value(const []);
    return ShellFileOperation.restoreRecycleBinAsync(
      parsingNames,
      destinations: destinations,
      keepBothOnCollision: keepBothOnCollision,
      cancelRequested: cancelRequested,
      onProgress: onProgress,
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
      final originalExists =
          original != null && original.isNotEmpty && _directoryExists(original);
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
  /// 从回收站条目中按原始目录 + 名称匹配解析名。原生删除回调未返回
  /// recycledPath 时的兜底（FOF_ALLOWUNDO 已移除，正常路径应已带路径）。
  static String? matchRecycledParsingName(
    List<FileEntry> entries,
    String sourcePath,
  ) {
    final name = p.basename(sourcePath);
    final dir = p.normalize(p.dirname(sourcePath));
    for (final entry in entries) {
      final parsing = entry.parsingName;
      final original = entry.originalPath;
      if (parsing == null || parsing.isEmpty) continue;
      if (entry.name != name) continue;
      if (original == null || !p.equals(p.normalize(original), dir)) continue;
      return parsing;
    }
    return null;
  }

  /// 枚举回收站查找 [sourcePath] 删除后的新解析名。
  static String? findRecycledParsingName(String sourcePath) =>
      matchRecycledParsingName(
        DirectoryService.listDirectory(recycleBinShellPath),
        sourcePath,
      );

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
