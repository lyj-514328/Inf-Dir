import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_search_service.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/command_menu.dart';
import 'package:inf_dir/widgets/file_search_dialog.dart';
import 'package:path/path.dart' as p;

void main() {
  test('command menu exposes search as an action item', () {
    var invoked = false;
    final items = buildCommandMenuItems(
      CommandMenuConfig(onSearch: () => invoked = true),
    );

    expect(items.first.label, '搜索');
    expect(items.first.icon, Icons.search);
    items.first.onAction!();
    expect(invoked, isTrue);
  });

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
      await tester.enterText(find.byType(TextField), 'report');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pumpAndSettle();

      expect(find.text('report.txt'), findsOneWidget);
      expect(capturedWorkingDirectory, root.path);

      await tester.tap(find.text('report.txt'));
      await tester.pumpAndSettle();
      expect(await dialogFuture, isA<FileSearchResult>());
    });
  });
}
