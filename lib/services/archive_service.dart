import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_plugin_resolver.dart';

enum ArchiveFormat {
  zip('zip'),
  sevenZip('7z');

  const ArchiveFormat(this.extension);

  final String extension;
}

class ArchiveException implements Exception {
  final String message;

  const ArchiveException(this.message);

  @override
  String toString() => message;
}

typedef ArchiveRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

class ArchiveService {
  final String? executable;
  final ArchiveRunner? _runner;

  ArchiveService({
    String? executable,
    ArchiveRunner? runner,
    bool discoverExecutable = true,
  }) : executable =
           executable ?? (discoverExecutable ? _resolveExecutable() : null),
       _runner = runner;

  static String? _resolveExecutable() {
    final overridePath = Platform.environment['INF_DIR_7Z_PATH'];
    if (overridePath?.trim().isNotEmpty == true) return overridePath!.trim();

    final pluginExecutable = ArchivePluginResolver.resolve(
      pluginId: 'inf-dir.7z-archive',
      type: ArchivePluginType.sevenZip,
    );
    if (pluginExecutable != null) return pluginExecutable;

    final appDirectory = p.dirname(Platform.resolvedExecutable);
    for (final candidate in [
      p.join(appDirectory, '7za.exe'),
      p.join(appDirectory, 'tools', '7za.exe'),
      p.join(Directory.current.path, 'tools', '7za.exe'),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static List<String> buildArguments(
    List<String> paths,
    String archivePath,
    ArchiveFormat format,
  ) {
    return ['a', '-t${format.extension}', '-y', archivePath, ...paths];
  }

  Future<void> createArchive(
    List<String> paths,
    String archivePath, {
    required ArchiveFormat format,
  }) async {
    if (paths.isEmpty) {
      throw const ArchiveException('No files were selected for compression.');
    }
    if (archivePath.trim().isEmpty) {
      throw const ArchiveException('Archive path cannot be empty.');
    }

    final resolvedExecutable = executable;
    if (resolvedExecutable == null) {
      throw const ArchiveException(
        '未找到 7-Zip 压缩插件，请先运行 plugins/archive/build.bat，或配置 INF_DIR_7Z_PATH。',
      );
    }

    final arguments = buildArguments(paths, archivePath, format);
    final workingDirectory = p.dirname(archivePath);
    final result = _runner == null
        ? await Process.run(
            resolvedExecutable,
            arguments,
            workingDirectory: workingDirectory,
            runInShell: false,
          )
        : await _runner(
            resolvedExecutable,
            arguments,
            workingDirectory: workingDirectory,
          );
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim();
      throw ArchiveException(
        detail.isEmpty
            ? '7-Zip exited with code ${result.exitCode}.'
            : '7-Zip failed: $detail',
      );
    }
  }
}
