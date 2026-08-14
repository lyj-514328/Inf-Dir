import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/services/shell_file_operation.dart';

void main() {
  group('planRestoreDestinations', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf-dir-restore-plan-');
    });

    tearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    });

    FileEntry entry(String name, {String? originalPath}) => FileEntry(
      name: name,
      path: name,
      isDirectory: false,
      size: 0,
      modified: DateTime(2026),
      originalPath: originalPath,
      parsingName: '\$R$name',
    );

    test('keeps a null target when the original directory exists', () {
      final existing = Directory('${temp.path}\\existing')..createSync();
      final plan = FileService.planRestoreDestinations([
        entry('a.pdf', originalPath: existing.path),
      ]);

      expect(plan.missing, isEmpty);
      expect(plan.destinations, [null]);
    });

    test('flags missing originals and applies the fallback', () {
      final gone = '${temp.path}\\gone';
      final plan = FileService.planRestoreDestinations([
        entry('a.pdf', originalPath: gone),
        entry('b.txt', originalPath: gone),
      ], fallback: 'C:\\Target');

      expect(plan.missing, hasLength(2));
      expect(plan.destinations, ['C:\\Target', 'C:\\Target']);
    });

    test('treats a null originalPath as missing', () {
      final plan = FileService.planRestoreDestinations([entry('a.pdf')]);

      expect(plan.missing, hasLength(1));
      expect(plan.destinations, [null]);
    });

    test('mixes existing and missing originals', () {
      final existing = Directory('${temp.path}\\existing')..createSync();
      final plan = FileService.planRestoreDestinations([
        entry('a.pdf', originalPath: existing.path),
        entry('b.txt', originalPath: '${temp.path}\\gone'),
      ], fallback: 'C:\\Target');

      expect(plan.missing, hasLength(1));
      expect(plan.missing.single.name, 'b.txt');
      expect(plan.destinations, [null, 'C:\\Target']);
    });

    test('without a fallback missing entries keep a null target', () {
      final plan = FileService.planRestoreDestinations([
        entry('a.pdf', originalPath: '${temp.path}\\gone'),
      ]);

      expect(plan.missing, hasLength(1));
      expect(plan.destinations, [null]);
    });

    test('empty restore selections produce an empty plan', () {
      final plan = FileService.planRestoreDestinations(const []);

      expect(plan.missing, isEmpty);
      expect(plan.destinations, isEmpty);
    });
  });

  group('planRestoreCollisions', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf-dir-restore-plan-');
    });

    tearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    });

    FileEntry entry(
      String name, {
      bool isDirectory = false,
      String? originalPath,
    }) => FileEntry(
      name: name,
      path: name,
      isDirectory: isDirectory,
      size: 0,
      modified: DateTime(2026),
      originalPath: originalPath,
      parsingName: '\$R$name',
    );

    test('flags a same-named file in the target directory', () {
      final target = Directory('${temp.path}\\target')..createSync();
      File('${target.path}\\a.pdf').writeAsStringSync('existing');

      final collisions = FileService.planRestoreCollisions([
        entry('a.pdf', originalPath: target.path),
      ]);

      expect(collisions, hasLength(1));
      expect(collisions.single.name, 'a.pdf');
    });

    test('keeps entries whose target directory has no match', () {
      final target = Directory('${temp.path}\\target')..createSync();
      File('${target.path}\\b.txt').writeAsStringSync('existing');

      final collisions = FileService.planRestoreCollisions([
        entry('a.pdf', originalPath: target.path),
      ]);

      expect(collisions, isEmpty);
    });

    test('ignores entries whose target directory is missing', () {
      final collisions = FileService.planRestoreCollisions([
        entry('a.pdf', originalPath: '${temp.path}\\gone'),
      ]);

      expect(collisions, isEmpty);
    });

    test('flags any same-named item regardless of entry type', () {
      final target = Directory('${temp.path}\\target')..createSync();
      Directory('${target.path}\\folder').createSync();
      File('${target.path}\\doc.txt').writeAsStringSync('x');

      // Windows namespaces cannot hold a file and a directory with the same
      // name, so a same-named directory collides with a file entry too.
      expect(
        FileService.planRestoreCollisions([
          entry('folder', isDirectory: false, originalPath: target.path),
        ]),
        hasLength(1),
      );
      expect(
        FileService.planRestoreCollisions([
          entry('doc.txt', isDirectory: true, originalPath: target.path),
        ]),
        hasLength(1),
      );
    });

    test('uses destination overrides when provided', () {
      final targetA = Directory('${temp.path}\\targetA')..createSync();
      final targetB = Directory('${temp.path}\\targetB')..createSync();
      File('${targetB.path}\\a.pdf').writeAsStringSync('existing');

      final collisions = FileService.planRestoreCollisions(
        [entry('a.pdf', originalPath: targetA.path)],
        destinations: [targetB.path],
      );

      expect(collisions, hasLength(1));
    });

    test('detects collisions across a multi-selection', () {
      final target = Directory('${temp.path}\\target')..createSync();
      File('${target.path}\\a.pdf').writeAsStringSync('existing');
      Directory('${target.path}\\folder').createSync();

      final collisions = FileService.planRestoreCollisions([
        entry('a.pdf', originalPath: target.path),
        entry('folder', isDirectory: true, originalPath: target.path),
        entry('new.txt', originalPath: target.path),
      ]);

      expect(collisions.map((item) => item.name), ['a.pdf', 'folder']);
    });

    test('empty collision selections are a no-op', () {
      expect(FileService.planRestoreCollisions(const []), isEmpty);
    });
  });

  test('empty restore operation does not enter the native layer', () {
    expect(
      () => FileService.restoreRecycleBinEntries(const []),
      returnsNormally,
    );
  });

  test('empty async restore returns no results without the native layer', () async {
    expect(await FileService.restoreRecycleBinEntriesAsync(const []), isEmpty);
    expect(
      await ShellFileOperation.restoreRecycleBinAsync(const []),
      isEmpty,
    );
  });

  group('matchRecycledParsingName', () {
    FileEntry binEntry({
      required String name,
      String? originalPath,
      String? parsingName,
    }) => FileEntry(
      name: name,
      path: parsingName ?? '',
      isDirectory: false,
      size: 1,
      modified: DateTime(2025),
      originalPath: originalPath,
      parsingName: parsingName,
    );

    test('matches by original directory and name', () {
      final entries = [
        binEntry(
          name: 'a.txt',
          originalPath: r'C:\Docs',
          parsingName: r'C:\$Recycle.Bin\$R1.txt',
        ),
        binEntry(
          name: 'a.txt',
          originalPath: r'C:\Other',
          parsingName: r'C:\$Recycle.Bin\$R2.txt',
        ),
      ];
      expect(
        FileService.matchRecycledParsingName(entries, r'C:\Docs\a.txt'),
        r'C:\$Recycle.Bin\$R1.txt',
      );
    });

    test('returns null when no entry matches name or origin', () {
      final entries = [
        binEntry(
          name: 'b.txt',
          originalPath: r'C:\Docs',
          parsingName: r'C:\$Recycle.Bin\$R1.txt',
        ),
        binEntry(
          name: 'a.txt',
          originalPath: r'C:\Other',
          parsingName: r'C:\$Recycle.Bin\$R2.txt',
        ),
        binEntry(name: 'a.txt', originalPath: r'C:\Docs'), // 无 parsingName
      ];
      expect(
        FileService.matchRecycledParsingName(entries, r'C:\Docs\a.txt'),
        isNull,
      );
    });
  });
}
