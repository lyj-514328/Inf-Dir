import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_search_service.dart';
import 'package:inf_dir/services/text_search_service.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/file_search_dialog.dart';
import 'package:inf_dir/widgets/search_dialog.dart';
import 'package:inf_dir/widgets/text_search_dialog.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileSearchOptions', () {
    test('builds fd arguments for glob directory search', () {
      final args = const FileSearchOptions(
        patternMode: FileSearchPatternMode.glob,
        entryKind: FileSearchEntryKind.directories,
        includeHidden: true,
        caseSensitive: true,
        followLinks: true,
        maxResults: 200,
      ).buildArguments('src*', r'C:\work');

      expect(args, [
        '--color=never',
        '--print0',
        '--absolute-path',
        '--max-results',
        '200',
        '--hidden',
        '--follow',
        '--case-sensitive',
        '--glob',
        '--type',
        'directory',
        '--',
        'src*',
        r'C:\work',
      ]);
    });
  });

  group('TextSearchOptions', () {
    test('maps the per-file line limit to rg max-count', () {
      final args = const TextSearchOptions(
        maxFiles: 20,
        maxMatchesPerFile: 50,
      ).buildArguments('needle', r'C:\work');

      expect(args, containsAllInOrder(['--max-count', '50']));
      expect(args, isNot(contains('20')));
    });
  });

  group('FileSearchService', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('inf-dir-search-');
      Directory(p.join(root.path, 'folder')).createSync();
      File(p.join(root.path, 'report.txt')).createSync();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('parses NUL-separated results and identifies directories', () async {
      List<String>? capturedArguments;
      String? capturedWorkingDirectory;
      final folder = p.join(root.path, 'folder');
      final file = p.join(root.path, 'report.txt');
      final streamedPaths = <String>[];
      final service = FileSearchService(
        executable: 'fd-test',
        runner: (executable, arguments, {workingDirectory}) async {
          capturedArguments = arguments;
          capturedWorkingDirectory = workingDirectory;
          return ProcessResult(1, 0, '$folder\u0000$file\u0000', '');
        },
      );

      final results = await service.search(
        root.path,
        'report',
        onResult: (result) => streamedPaths.add(result.path),
      );

      expect(capturedArguments, contains('--fixed-strings'));
      expect(capturedArguments, contains('--ignore-case'));
      expect(capturedWorkingDirectory, root.path);
      expect(results.map((result) => result.path), [folder, file]);
      expect(streamedPaths, [folder, file]);
      expect(results.first.isDirectory, isTrue);
      expect(results.last.isDirectory, isFalse);
    });

    test('treats fd exit code 1 as no matches', () async {
      final service = FileSearchService(
        executable: 'fd-test',
        runner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(1, 1, '', ''),
      );

      expect(await service.search(root.path, 'missing'), isEmpty);
    });

    test('rejects an empty query before starting fd', () async {
      var called = false;
      final service = FileSearchService(
        executable: 'fd-test',
        runner: (executable, arguments, {workingDirectory}) async {
          called = true;
          return ProcessResult(1, 0, '', '');
        },
      );

      await expectLater(
        service.search(root.path, '  '),
        throwsA(isA<FileSearchException>()),
      );
      expect(called, isFalse);
    });

    test('parses streaming-style rg JSON matches', () async {
      final matchLine = jsonEncode({
        'type': 'match',
        'data': {
          'path': {'text': 'report.txt'},
          'lines': {'text': 'hello report\n'},
          'line_number': 3,
          'submatches': [
            {'start': 6, 'end': 12},
          ],
        },
      });
      final streamed = <TextSearchMatch>[];
      final service = TextSearchService(
        executable: 'rg-test',
        runner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(1, 0, '$matchLine\n', ''),
      );

      final results = await service.search(
        root.path,
        'report',
        onMatch: streamed.add,
      );

      expect(results, hasLength(1));
      expect(streamed, hasLength(1));
      expect(results.single.path, p.join(root.path, 'report.txt'));
      expect(results.single.line, 3);
      expect(results.single.column, 7);
      expect(results.single.text, 'hello report');
      expect(results.single.ranges, hasLength(1));
      expect(results.single.ranges.single.start, 6);
      expect(results.single.ranges.single.end, 12);
    });

    test(
      'trims long matching lines without losing UTF-8 highlight offsets',
      () async {
        final prefix =
            '${List.filled(80, '中').join()}${List.filled(500, 'a').join()}';
        final lineText = '$prefix needle ${List.filled(500, 'z').join()}';
        final byteStart = utf8.encode('$prefix ').length;
        final matchLine = jsonEncode({
          'type': 'match',
          'data': {
            'path': {'text': 'long.svg'},
            'lines': {'text': '$lineText\n'},
            'line_number': 9,
            'submatches': [
              {'start': byteStart, 'end': byteStart + 6},
            ],
          },
        });
        final service = TextSearchService(
          executable: 'rg-test',
          runner: (executable, arguments, {workingDirectory}) async =>
              ProcessResult(1, 0, '$matchLine\n', ''),
        );

        final results = await service.search(root.path, 'needle');
        final match = results.single;
        final range = match.ranges.single;

        expect(match.column, byteStart + 1);
        expect(match.text.length, lessThanOrEqualTo(520));
        expect(match.text.substring(range.start, range.end), 'needle');
      },
    );

    test('limits text search by distinct matching files', () async {
      String matchLine(String path, int line) => jsonEncode({
        'type': 'match',
        'data': {
          'path': {'text': path},
          'lines': {'text': 'needle\n'},
          'line_number': line,
          'submatches': [
            {'start': 0, 'end': 6},
          ],
        },
      });

      final output = [
        matchLine('first.txt', 1),
        matchLine('first.txt', 2),
        matchLine('second.txt', 1),
      ].join('\n');
      final streamed = <TextSearchMatch>[];
      final service = TextSearchService(
        executable: 'rg-test',
        runner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(1, 0, output, ''),
      );

      final results = await service.search(
        root.path,
        'needle',
        options: const TextSearchOptions(maxFiles: 1, maxMatchesPerFile: 20),
        onMatch: streamed.add,
      );

      expect(results, hasLength(2));
      expect(streamed, hasLength(2));
      expect(results.map((match) => p.basename(match.path)).toSet(), {
        'first.txt',
      });
    });

    testWidgets('dialog runs search and opens a selected result', (
      tester,
    ) async {
      final file = p.join(root.path, 'report.txt');
      String? capturedWorkingDirectory;
      final service = FileSearchService(
        executable: 'fd-test',
        runner: (executable, arguments, {workingDirectory}) async {
          capturedWorkingDirectory = workingDirectory;
          return ProcessResult(1, 0, '$file\u0000', '');
        },
      );
      late BuildContext hostContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final dialogFuture = showDialog<FileSearchResult>(
        context: hostContext,
        builder: (_) =>
            FileSearchDialog(rootPath: root.path, searchService: service),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('file-search-query')),
        'report',
      );
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pumpAndSettle();

      expect(find.text('report.txt'), findsOneWidget);
      expect(capturedWorkingDirectory, root.path);

      await tester.tap(find.text('report.txt'));
      await tester.pumpAndSettle();
      expect(await dialogFuture, isA<FileSearchResult>());
    });

    testWidgets('unified search defaults to files and switches to text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SearchDialog(rootPath: root.path),
        ),
      );

      expect(find.text('文件'), findsOneWidget);
      expect(find.text('输入文件名'), findsOneWidget);

      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();

      // 切换到文本模式后，查询框换成文本内容匹配
      expect(find.text('输入要匹配的文本'), findsOneWidget);
      expect(find.text('输入文件名'), findsNothing);
    });

    testWidgets('text search dialog shows and opens a matching file', (
      tester,
    ) async {
      final file = p.join(root.path, 'report.txt');
      final matchLine = jsonEncode({
        'type': 'match',
        'data': {
          'path': {'text': 'report.txt'},
          'lines': {'text': 'hello report\n'},
          'line_number': 3,
          'submatches': [
            {'start': 6, 'end': 12},
          ],
        },
      });
      final service = TextSearchService(
        executable: 'rg-test',
        runner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(1, 0, '$matchLine\n', ''),
      );
      late BuildContext hostContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final dialogFuture = showDialog<TextSearchMatch>(
        context: hostContext,
        builder: (_) =>
            TextSearchDialog(rootPath: root.path, searchService: service),
      );
      await tester.pumpAndSettle();
      expect(find.text('最大匹配文件数'), findsOneWidget);
      expect(find.text('文件内最大匹配行数'), findsOneWidget);
      final patternCenter = tester.getCenter(
        find.byType(SegmentedButton<TextSearchPatternMode>),
      );
      final limitCenter = tester.getCenter(
        find.byType(DropdownMenu<int>).first,
      );
      expect((patternCenter.dy - limitCenter.dy).abs(), lessThan(4));
      await tester.enterText(
        find.byKey(const ValueKey('text-search-query')),
        'report',
      );
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pumpAndSettle();

      expect(find.text('report.txt (1)'), findsOneWidget);
      expect(find.text('report.txt'), findsOneWidget);
      expect(find.text('3:'), findsOneWidget);
      expect(find.text('hello report'), findsOneWidget);
      await tester.tap(find.text('3:'));
      await tester.pumpAndSettle();
      expect((await dialogFuture)!.path, file);
    });
  });
}
