import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory src;
  late Directory dest;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_conflict_');
    src = Directory(p.join(temp.path, 'src'))..createSync();
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  void writeFile(Directory dir, String name, [String content = '']) {
    File(p.join(dir.path, name)).writeAsStringSync(content);
  }

  test('returns nothing when sources or destination have no collisions', () {
    writeFile(src, 'a.txt');

    expect(FileService.detectConflicts(const [], dest.path), isEmpty);
    expect(FileService.detectConflicts([p.join(src.path, 'a.txt')], dest.path),
        isEmpty);
  });

  test('detects same-name files in the destination', () {
    writeFile(src, 'a.txt');
    writeFile(src, 'b.txt');
    writeFile(dest, 'a.txt');

    expect(
      FileService.detectConflicts(
        [p.join(src.path, 'a.txt'), p.join(src.path, 'b.txt')],
        dest.path,
      ),
      [p.join(src.path, 'a.txt')],
    );
  });

  test('treats a source already inside the destination as itself, not a '
      'conflict', () {
    writeFile(dest, 'keep.txt');

    expect(
      FileService.detectConflicts([p.join(dest.path, 'keep.txt')], dest.path),
      isEmpty,
    );
  });

  test('detects collisions with directories too', () {
    Directory(p.join(src.path, 'sub')).createSync();
    Directory(p.join(dest.path, 'sub')).createSync();

    expect(
      FileService.detectConflicts([p.join(src.path, 'sub')], dest.path),
      [p.join(src.path, 'sub')],
    );
  });

  test('ignores empty basenames and missing sources', () {
    // A trailing separator basename is empty; the entry is skipped.
    expect(
      FileService.detectConflicts(['${dest.path}${p.separator}'], dest.path),
      isEmpty,
    );
  });
}
