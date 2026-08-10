import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum TextSearchPatternMode { keyword, regex }

class TextSearchOptions {
  final TextSearchPatternMode patternMode;
  final bool includeHidden;
  final bool caseSensitive;
  final bool followLinks;
  final int maxFiles;
  final int maxMatchesPerFile;

  const TextSearchOptions({
    this.patternMode = TextSearchPatternMode.keyword,
    this.includeHidden = false,
    this.caseSensitive = false,
    this.followLinks = false,
    this.maxFiles = 200,
    this.maxMatchesPerFile = 500,
  });

  List<String> buildArguments(String query, String rootPath) {
    final args = <String>[
      '--json',
      '--color=never',
      '--line-number',
      '--column',
      '--max-count',
      maxMatchesPerFile.toString(),
    ];
    if (includeHidden) args.add('--hidden');
    if (followLinks) args.add('--follow');
    args.add(caseSensitive ? '--case-sensitive' : '--ignore-case');
    if (patternMode == TextSearchPatternMode.keyword) {
      args.add('--fixed-strings');
    }
    args.addAll(['--', query, rootPath]);
    return args;
  }
}

class TextSearchMatch {
  final String path;
  final int line;
  final int column;
  final String text;
  final List<TextSearchMatchRange> ranges;

  const TextSearchMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.text,
    this.ranges = const [],
  });
}

class TextSearchMatchRange {
  final int start;
  final int end;

  const TextSearchMatchRange({required this.start, required this.end});
}

class TextSearchException implements Exception {
  final String message;

  const TextSearchException(this.message);

  @override
  String toString() => message;
}

typedef TextSearchRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

typedef TextSearchProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

typedef TextSearchMatchCallback = void Function(TextSearchMatch match);

class _TextSearchJsonEvent {
  final String type;
  final String? path;
  final TextSearchMatch? match;

  const _TextSearchJsonEvent({required this.type, this.path, this.match});
}

class TextSearchService {
  final String executable;
  // A buffered runner remains available for deterministic tests.
  final TextSearchRunner? _runner;
  final TextSearchProcessStarter _processStarter;

  TextSearchService({
    String? executable,
    TextSearchRunner? runner,
    TextSearchProcessStarter? processStarter,
  }) : executable = executable ?? _resolveExecutable(),
       _runner = runner,
       _processStarter = processStarter ?? _start;

  static String _resolveExecutable() {
    final overridePath = Platform.environment['INF_DIR_RG_PATH'];
    if (overridePath?.trim().isNotEmpty == true) return overridePath!.trim();

    final appDirectory = p.dirname(Platform.resolvedExecutable);
    final bundled = File(p.join(appDirectory, 'rg.exe'));
    if (bundled.existsSync()) return bundled.path;
    final toolsBundled = File(p.join(appDirectory, 'tools', 'rg.exe'));
    if (toolsBundled.existsSync()) return toolsBundled.path;
    final developmentBundled = File(
      p.join(Directory.current.path, 'tools', 'rg.exe'),
    );
    if (developmentBundled.existsSync()) return developmentBundled.path;
    return Platform.isWindows ? 'rg.exe' : 'rg';
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

  Future<List<TextSearchMatch>> search(
    String rootPath,
    String query, {
    TextSearchOptions options = const TextSearchOptions(),
    TextSearchMatchCallback? onMatch,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw const TextSearchException('请输入搜索内容');
    }
    if (FileSystemEntity.typeSync(rootPath) != FileSystemEntityType.directory) {
      throw const TextSearchException('当前路径不是可搜索的文件夹');
    }
    if (options.maxFiles < 1 || options.maxMatchesPerFile < 1) {
      throw const TextSearchException('搜索数量限制必须大于 0');
    }

    if (_runner != null) {
      return _searchBuffered(
        rootPath,
        normalizedQuery,
        options,
        onMatch: onMatch,
      );
    }
    return _searchStreaming(
      rootPath,
      normalizedQuery,
      options,
      onMatch: onMatch,
    );
  }

  Future<List<TextSearchMatch>> _searchBuffered(
    String rootPath,
    String query,
    TextSearchOptions options, {
    TextSearchMatchCallback? onMatch,
  }) async {
    late final ProcessResult result;
    try {
      result = await _runner!(
        executable,
        options.buildArguments(query, rootPath),
        workingDirectory: rootPath,
      );
    } on ProcessException {
      throw const TextSearchException('找不到 rg.exe，请将 rg.exe 放入程序目录或加入 PATH');
    }

    _throwOnExit(result.exitCode, result.stderr.toString());
    return _parseOutput(
      result.stdout is String
          ? result.stdout as String
          : result.stdout.toString(),
      rootPath,
      options.maxFiles,
      onMatch: onMatch,
    );
  }

  Future<List<TextSearchMatch>> _searchStreaming(
    String rootPath,
    String query,
    TextSearchOptions options, {
    TextSearchMatchCallback? onMatch,
  }) async {
    late final Process process;
    try {
      process = await _processStarter(
        executable,
        options.buildArguments(query, rootPath),
        workingDirectory: rootPath,
      );
    } on ProcessException {
      throw const TextSearchException('找不到 rg.exe，请将 rg.exe 放入程序目录或加入 PATH');
    }

    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final matches = <TextSearchMatch>[];
    final seenFiles = <String>{};
    String? stopAfterPath;
    var stoppedByFileLimit = false;

    bool accept(_TextSearchJsonEvent? event) {
      if (event == null) return false;
      final match = event.match;
      if (match != null) {
        final key = _pathKey(match.path);
        if (!seenFiles.contains(key)) {
          if (seenFiles.length >= options.maxFiles) return true;
          seenFiles.add(key);
          if (seenFiles.length == options.maxFiles) stopAfterPath = key;
        }
        matches.add(match);
        onMatch?.call(match);
      }

      return stopAfterPath != null &&
          event.type == 'end' &&
          event.path != null &&
          _pathKey(event.path!) == stopAfterPath;
    }

    var pending = StringBuffer();
    outputLoop:
    await for (final chunk in process.stdout.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      pending.write(chunk);
      final text = pending.toString();
      var start = 0;
      while (true) {
        final end = text.indexOf('\n', start);
        if (end < 0) break;
        final event = _parseLine(
          text.substring(start, end).replaceFirst(RegExp(r'\r$'), ''),
          rootPath,
        );
        if (accept(event)) {
          stoppedByFileLimit = true;
          process.kill();
          break outputLoop;
        }
        start = end + 1;
      }
      pending = StringBuffer(text.substring(start));
    }
    if (!stoppedByFileLimit) {
      accept(_parseLine(pending.toString(), rootPath));
    }

    final exitCode = await process.exitCode;
    final stderr = (await stderrFuture).trim();
    if (!stoppedByFileLimit) _throwOnExit(exitCode, stderr);
    return matches;
  }

  List<TextSearchMatch> _parseOutput(
    String output,
    String rootPath,
    int maxFiles, {
    TextSearchMatchCallback? onMatch,
  }) {
    final matches = <TextSearchMatch>[];
    final seenFiles = <String>{};
    for (final line in output.split('\n')) {
      final match = _parseLine(
        line.replaceFirst(RegExp(r'\r$'), ''),
        rootPath,
      )?.match;
      if (match == null) continue;
      final key = _pathKey(match.path);
      if (!seenFiles.contains(key)) {
        if (seenFiles.length >= maxFiles) break;
        seenFiles.add(key);
      }
      matches.add(match);
      onMatch?.call(match);
    }
    return matches;
  }

  _TextSearchJsonEvent? _parseLine(String line, String rootPath) {
    if (line.trim().isEmpty) return null;
    final dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final type = decoded['type']?.toString();
    if (type == null) return null;
    final data = decoded['data'];
    if (data is! Map) return _TextSearchJsonEvent(type: type);

    final pathData = data['path'];
    final rawPath = pathData is Map ? pathData['text']?.toString() : null;
    final path = rawPath == null || rawPath.isEmpty
        ? null
        : p.isAbsolute(rawPath)
        ? rawPath
        : p.join(rootPath, rawPath);
    if (type != 'match' || path == null) {
      return _TextSearchJsonEvent(type: type, path: path);
    }

    final lineNumber = (data['line_number'] as num?)?.toInt() ?? 0;
    final linesData = data['lines'];
    final text = linesData is Map
        ? (linesData['text']?.toString() ?? '').replaceFirst(
            RegExp(r'\r?\n$'),
            '',
          )
        : '';
    final submatches = data['submatches'];
    final ranges = <TextSearchMatchRange>[];
    var firstStart = 0;
    if (submatches is List) {
      for (final submatch in submatches) {
        if (submatch is! Map) continue;
        final byteStart = (submatch['start'] as num?)?.toInt();
        final byteEnd = (submatch['end'] as num?)?.toInt();
        if (byteStart == null || byteEnd == null || byteEnd <= byteStart) {
          continue;
        }
        final start = _byteOffsetToCodeUnit(text, byteStart);
        final end = _byteOffsetToCodeUnit(text, byteEnd);
        if (end <= start) continue;
        if (ranges.isEmpty) firstStart = byteStart;
        ranges.add(TextSearchMatchRange(start: start, end: end));
      }
    }
    final match = TextSearchMatch(
      path: path,
      line: lineNumber,
      column: firstStart + 1,
      text: text,
      ranges: ranges,
    );
    return _TextSearchJsonEvent(type: type, path: path, match: match);
  }

  String _pathKey(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  int _byteOffsetToCodeUnit(String text, int byteOffset) {
    if (byteOffset <= 0) return 0;
    var bytes = 0;
    var codeUnits = 0;
    for (final rune in text.runes) {
      final value = String.fromCharCode(rune);
      final runeBytes = utf8.encode(value).length;
      if (bytes + runeBytes > byteOffset) break;
      bytes += runeBytes;
      codeUnits += value.length;
      if (bytes == byteOffset) break;
    }
    return codeUnits;
  }

  void _throwOnExit(int exitCode, String stderr) {
    if (exitCode != 0 && exitCode != 1) {
      throw TextSearchException(
        stderr.trim().isEmpty ? 'rg 搜索失败（退出码 $exitCode）' : stderr.trim(),
      );
    }
  }
}
