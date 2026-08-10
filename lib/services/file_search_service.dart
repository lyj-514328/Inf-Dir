import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum FileSearchPatternMode { keyword, glob, regex }

enum FileSearchEntryKind { all, files, directories }

class FileSearchOptions {
  final FileSearchPatternMode patternMode;
  final FileSearchEntryKind entryKind;
  final bool includeHidden;
  final bool caseSensitive;
  final bool followLinks;
  final int maxResults;

  const FileSearchOptions({
    this.patternMode = FileSearchPatternMode.keyword,
    this.entryKind = FileSearchEntryKind.all,
    this.includeHidden = false,
    this.caseSensitive = false,
    this.followLinks = false,
    this.maxResults = 500,
  });

  List<String> buildArguments(String query, String rootPath) {
    final args = <String>[
      '--color=never',
      '--print0',
      '--absolute-path',
      '--max-results',
      maxResults.toString(),
    ];
    if (includeHidden) args.add('--hidden');
    if (followLinks) args.add('--follow');
    args.add(caseSensitive ? '--case-sensitive' : '--ignore-case');

    switch (patternMode) {
      case FileSearchPatternMode.keyword:
        args.add('--fixed-strings');
      case FileSearchPatternMode.glob:
        args.add('--glob');
      case FileSearchPatternMode.regex:
        break;
    }

    switch (entryKind) {
      case FileSearchEntryKind.all:
        break;
      case FileSearchEntryKind.files:
        args.addAll(['--type', 'file']);
      case FileSearchEntryKind.directories:
        args.addAll(['--type', 'directory']);
    }

    args.addAll(['--', query, rootPath]);
    return args;
  }
}

class FileSearchResult {
  final String path;
  final bool isDirectory;

  const FileSearchResult({required this.path, required this.isDirectory});
}

class FileSearchException implements Exception {
  final String message;

  const FileSearchException(this.message);

  @override
  String toString() => message;
}

typedef FileSearchRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

typedef FileSearchProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

typedef FileSearchResultCallback = void Function(FileSearchResult result);

class FileSearchService {
  final String executable;
  // The buffered runner is kept for deterministic tests and custom callers.
  // Normal application searches use Process.start and stream fd output.
  final FileSearchRunner? _runner;
  final FileSearchProcessStarter _processStarter;

  FileSearchService({
    String? executable,
    FileSearchRunner? runner,
    FileSearchProcessStarter? processStarter,
  }) : executable = executable ?? _resolveExecutable(),
       _runner = runner,
       _processStarter = processStarter ?? _start;

  static String _resolveExecutable() {
    final overridePath = Platform.environment['INF_DIR_FD_PATH'];
    if (overridePath?.trim().isNotEmpty == true) return overridePath!.trim();

    final appDirectory = p.dirname(Platform.resolvedExecutable);
    final bundled = File(p.join(appDirectory, 'fd.exe'));
    if (bundled.existsSync()) return bundled.path;

    // Development and portable layouts may keep helper tools in a subfolder.
    final toolsBundled = File(p.join(appDirectory, 'tools', 'fd.exe'));
    if (toolsBundled.existsSync()) return toolsBundled.path;
    final developmentBundled = File(
      p.join(Directory.current.path, 'tools', 'fd.exe'),
    );
    if (developmentBundled.existsSync()) return developmentBundled.path;
    return Platform.isWindows ? 'fd.exe' : 'fd';
  }

  static Future<Process> _start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }

  Future<List<FileSearchResult>> search(
    String rootPath,
    String query, {
    FileSearchOptions options = const FileSearchOptions(),
    FileSearchResultCallback? onResult,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const FileSearchException('请输入搜索内容');
    }
    if (FileSystemEntity.typeSync(rootPath) != FileSystemEntityType.directory) {
      throw const FileSearchException('当前路径不是可搜索的文件夹');
    }

    if (_runner != null) {
      return _searchBuffered(
        rootPath,
        normalizedQuery,
        options,
        onResult: onResult,
      );
    }
    return _searchStreaming(
      rootPath,
      normalizedQuery,
      options,
      onResult: onResult,
    );
  }

  Future<List<FileSearchResult>> _searchBuffered(
    String rootPath,
    String query,
    FileSearchOptions options, {
    FileSearchResultCallback? onResult,
  }) async {
    late final ProcessResult result;
    try {
      result = await _runner!(
        executable,
        options.buildArguments(query, rootPath),
        workingDirectory: rootPath,
      );
    } on ProcessException {
      throw const FileSearchException('找不到 fd.exe，请将 fd.exe 放入程序目录或加入 PATH');
    }

    final stdout = result.stdout is String
        ? result.stdout as String
        : result.stdout.toString();
    _throwOnExit(result.exitCode, result.stderr.toString());

    final seen = <String>{};
    final results = <FileSearchResult>[];
    for (final path in stdout.split('\u0000')) {
      final parsed = _appendResult(path, seen, results);
      if (parsed != null) onResult?.call(parsed);
    }
    return results;
  }

  Future<List<FileSearchResult>> _searchStreaming(
    String rootPath,
    String query,
    FileSearchOptions options, {
    FileSearchResultCallback? onResult,
  }) async {
    late final Process process;
    try {
      process = await _processStarter(
        executable,
        options.buildArguments(query, rootPath),
        workingDirectory: rootPath,
      );
    } on ProcessException {
      throw const FileSearchException('找不到 fd.exe，请将 fd.exe 放入程序目录或加入 PATH');
    }

    // Read stderr concurrently so a verbose fd failure cannot block stdout.
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final seen = <String>{};
    final results = <FileSearchResult>[];
    var pending = StringBuffer();
    await for (final chunk in process.stdout.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      pending.write(chunk);
      final text = pending.toString();
      var start = 0;
      while (true) {
        final separator = text.indexOf('\u0000', start);
        if (separator < 0) break;
        final parsed = _appendResult(
          text.substring(start, separator),
          seen,
          results,
        );
        if (parsed != null) onResult?.call(parsed);
        start = separator + 1;
      }
      pending = StringBuffer(text.substring(start));
    }

    final trailing = pending.toString();
    final parsed = _appendResult(trailing, seen, results);
    if (parsed != null) onResult?.call(parsed);

    final exitCode = await process.exitCode;
    final stderr = (await stderrFuture).trim();
    _throwOnExit(exitCode, stderr);
    return results;
  }

  void _throwOnExit(int exitCode, String stderr) {
    if (exitCode != 0 && exitCode != 1) {
      throw FileSearchException(
        stderr.trim().isEmpty ? 'fd 搜索失败（退出码 $exitCode）' : stderr.trim(),
      );
    }
  }

  FileSearchResult? _appendResult(
    String path,
    Set<String> seen,
    List<FileSearchResult> results,
  ) {
    if (path.isEmpty) return null;
    final key = p.normalize(path).toLowerCase();
    if (!seen.add(key)) return null;
    final result = FileSearchResult(
      path: path,
      isDirectory: Directory(path).existsSync(),
    );
    results.add(result);
    return result;
  }
}
