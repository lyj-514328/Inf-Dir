import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_items_');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('permanent delete fallback reports per-item outcomes and continues', () async {
    final keep = File(p.join(temp.path, 'keep.txt'))
      ..writeAsStringSync('x');
    final missing = p.join(temp.path, 'missing.txt');

    final results = await FileService.deleteEntries(
      [keep.path, missing],
      permanent: true,
    );

    expect(results.length, 2);
    expect(results[0].path, keep.path);
    expect(results[0].isSuccess, isTrue);
    expect(results[1].path, missing);
    expect(results[1].isSuccess, isFalse);
    expect(keep.existsSync(), isFalse);
  });

  test('copy fallback reports per-item outcomes and continues', () async {
    final src = Directory(p.join(temp.path, 'src'))..createSync();
    final dest = Directory(p.join(temp.path, 'dest'))..createSync();
    final good = File(p.join(src.path, 'good.txt'))..writeAsStringSync('ok');
    final missing = p.join(src.path, 'missing.txt');

    final results = await FileService.copyEntries(
      [good.path, missing],
      dest.path,
    );

    expect(results.length, 2);
    expect(results[0].isSuccess, isTrue);
    expect(results[1].isSuccess, isFalse);
    expect(File(p.join(dest.path, 'good.txt')).readAsStringSync(), 'ok');
  });
}
