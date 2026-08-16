import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_plugin_resolver.dart';

enum ArchiveFormat {
  zip('zip'),
  sevenZip('7z');

  const ArchiveFormat(this.extension);

  final String extension;
}

/// 解压时遇到同名文件时的覆盖策略，映射到 7-Zip 的 `-ao` 开关。
enum ArchiveOverwriteMode {
  /// 覆盖全部已有文件（`-aoa`）。
  overwrite,

  /// 跳过已存在的文件（`-aos`）。
  skip,

  /// 自动重命名被解压的文件，保留两者（`-aou`）。
  keepBoth,
}

/// 通过扩展名判断是否为可解压的归档文件（对齐 Files 的解压入口范围）。
bool isArchiveName(String name) {
  final lower = name.toLowerCase();
  const extensions = {
    '.7z',
    '.zip',
    '.rar',
    '.tar',
    '.gz',
    '.tgz',
    '.bz2',
    '.tbz2',
    '.xz',
    '.txz',
    '.lzh',
    '.cab',
    '.iso',
    '.jar',
    '.wim',
    '.zst',
  };
  return extensions.any(lower.endsWith);
}

class ArchiveException implements Exception {
  const ArchiveException(this.message, {this.exitCode});

  final String message;
  final int? exitCode;

  @override
  String toString() => message;
}

typedef ArchiveRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// 通过随插件分发的 7-Zip 命令行版（`7za.exe`）执行压缩/解压。
///
/// 生产环境走 [Process.start] 流式读取进度（`-bsp1` 百分比行），支持取消
/// （[Process.kill]）与逐行错误捕获；注入 [ArchiveRunner] 时（测试）退化为
/// 一次性的 [ProcessResult]。
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

  static final RegExp _percentRe = RegExp(r'^\s*(\d{1,3})\s*%');

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

  String get _resolvedOrThrow {
    final resolved = executable;
    if (resolved == null) {
      throw const ArchiveException(
        '未找到 7-Zip 压缩插件，请先运行 plugins/archive/build.bat，或配置 INF_DIR_7Z_PATH。',
      );
    }
    return resolved;
  }

  /// 生成 `7za a` 的创建压缩包参数（不包含 `-bsp1` 进度开关，那是执行细节）。
  static List<String> buildArguments(
    List<String> paths,
    String archivePath,
    ArchiveFormat format, {
    String? password,
    int compressionLevel = 5,
    bool encryptHeaders = false,
  }) {
    return [
      'a',
      '-t${format.extension}',
      '-mx$compressionLevel',
      if (password != null && password.isNotEmpty) '-p$password',
      if (encryptHeaders && format == ArchiveFormat.sevenZip) '-mhe=on',
      '-y',
      archivePath,
      ...paths,
    ];
  }

  /// 生成 `7za x` 的解压参数（不包含 `-bsp1` 进度开关）。
  static List<String> buildExtractArguments(
    String archivePath,
    String destination, {
    String? password,
    ArchiveOverwriteMode overwrite = ArchiveOverwriteMode.overwrite,
    int? codePage,
  }) {
    return [
      'x',
      '-o$destination',
      switch (overwrite) {
        ArchiveOverwriteMode.overwrite => '-aoa',
        ArchiveOverwriteMode.skip => '-aos',
        ArchiveOverwriteMode.keepBoth => '-aou',
      },
      if (codePage != null) '-mcp=$codePage',
      if (password != null && password.isNotEmpty) '-p$password',
      '-y',
      archivePath,
    ];
  }

  Future<void> createArchive(
    List<String> paths,
    String archivePath, {
    required ArchiveFormat format,
    String? password,
    int compressionLevel = 5,
    bool encryptHeaders = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (paths.isEmpty) {
      throw const ArchiveException('No files were selected for compression.');
    }
    if (archivePath.trim().isEmpty) {
      throw const ArchiveException('Archive path cannot be empty.');
    }
    await _run(
      buildArguments(
        paths,
        archivePath,
        format,
        password: password,
        compressionLevel: compressionLevel,
        encryptHeaders: encryptHeaders,
      ),
      workingDirectory: p.dirname(archivePath),
      archivePath: archivePath,
      cancelRequested: cancelRequested,
      onProgress: onProgress,
    );
  }

  Future<void> extractArchive(
    String archivePath,
    String destination, {
    String? password,
    ArchiveOverwriteMode overwrite = ArchiveOverwriteMode.overwrite,
    int? codePage,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (archivePath.trim().isEmpty) {
      throw const ArchiveException('Archive path cannot be empty.');
    }
    if (destination.trim().isEmpty) {
      throw const ArchiveException('Extraction destination cannot be empty.');
    }
    await _run(
      buildExtractArguments(
        archivePath,
        destination,
        password: password,
        overwrite: overwrite,
        codePage: codePage,
      ),
      workingDirectory: p.dirname(archivePath),
      archivePath: archivePath,
      cancelRequested: cancelRequested,
      onProgress: onProgress,
    );
  }

  Future<void> _run(
    List<String> arguments, {
    required String workingDirectory,
    required String archivePath,
    required bool Function()? cancelRequested,
    required void Function(double progress)? onProgress,
  }) async {
    final runner = _runner;
    if (runner != null) {
      final result = await runner(
        _resolvedOrThrow,
        arguments,
        workingDirectory: workingDirectory,
      );
      if (cancelRequested?.call() == true) return;
      if (result.exitCode != 0) {
        throw _exceptionFromResult(result);
      }
      onProgress?.call(1);
      return;
    }

    final process = await Process.start(
      _resolvedOrThrow,
      [...arguments, '-bsp1'],
      workingDirectory: workingDirectory,
      runInShell: false,
    );

    final stderrLines = <String>[];
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            if (stderrLines.length < 200) stderrLines.add(trimmed);
          }
        });

    var cancelled = false;
    await for (final line
        in process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      final match = _percentRe.firstMatch(line);
      if (match != null) {
        final percent = int.tryParse(match.group(1)!);
        if (percent != null) {
          onProgress?.call((percent / 100).clamp(0, 1).toDouble());
        }
      }
      if (cancelRequested?.call() == true) {
        cancelled = true;
        process.kill(ProcessSignal.sigterm);
        break;
      }
    }

    final exitCode = await process.exitCode;
    if (cancelled) return;
    if (exitCode != 0) {
      throw ArchiveException(
        _errorMessage(stderrLines, exitCode),
        exitCode: exitCode,
      );
    }
    onProgress?.call(1);
  }

  ArchiveException _exceptionFromResult(ProcessResult result) {
    final detail = '${result.stderr}'.trim();
    return ArchiveException(
      detail.isEmpty
          ? '7-Zip exited with code ${result.exitCode}.'
          : '7-Zip failed: $detail',
      exitCode: result.exitCode,
    );
  }

  String _errorMessage(List<String> stderrLines, int exitCode) {
    final errorLines = stderrLines
        .where((line) => line.toUpperCase().contains('ERROR'))
        .toList();
    if (errorLines.isNotEmpty) return errorLines.join('; ');
    if (stderrLines.isNotEmpty) {
      final tail = stderrLines.length <= 3
          ? stderrLines
          : stderrLines.sublist(stderrLines.length - 3);
      return tail.join('; ');
    }
    return '7-Zip 退出码 $exitCode';
  }
}
