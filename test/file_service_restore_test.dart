import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/services/file_service.dart';

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
      final plan = FileService.planRestoreDestinations(
        [
          entry('a.pdf', originalPath: gone),
          entry('b.txt', originalPath: gone),
        ],
        fallback: 'C:\\Target',
      );

      expect(plan.missing, hasLength(2));
      expect(plan.destinations, ['C:\\Target', 'C:\\Target']);
    });

    test('treats a null originalPath as missing', () {
      final plan = FileService.planRestoreDestinations([
        entry('a.pdf'),
      ]);

      expect(plan.missing, hasLength(1));
      expect(plan.destinations, [null]);
    });

    test('mixes existing and missing originals', () {
      final existing = Directory('${temp.path}\\existing')..createSync();
      final plan = FileService.planRestoreDestinations(
        [
          entry('a.pdf', originalPath: existing.path),
          entry('b.txt', originalPath: '${temp.path}\\gone'),
        ],
        fallback: 'C:\\Target',
      );

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
  });
}
