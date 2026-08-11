import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';
import 'package:inf_dir/models/file_group.dart';

FileEntry entry(
  String name, {
  int size = 0,
  bool isDirectory = false,
  DateTime? modified,
}) {
  return FileEntry(
    name: name,
    path: 'C:\\$name',
    isDirectory: isDirectory,
    size: size,
    modified: modified ?? DateTime(2026, 8, 11),
  );
}

void main() {
  test('groups names into Explorer-style pinyin ranges', () {
    final groups = groupFileEntries([
      entry('z.txt'),
      entry('2.txt'),
      entry('alpha.txt'),
      entry('note.txt'),
      entry('百度网盘同步空间', isDirectory: true),
      entry('简历', isDirectory: true),
      entry('赛博清明上河图', isDirectory: true),
    ], FileGroupBy.name);

    expect(groups.map((group) => group.label), [
      '0 - 9',
      'A - F',
      'M - S',
      'T - Z',
      '拼音 A - F',
      '拼音 G - L',
      '拼音 M - S',
    ]);
    expect(groups.expand((group) => group.entries).map((item) => item.name), [
      '2.txt',
      'alpha.txt',
      'note.txt',
      'z.txt',
      '百度网盘同步空间',
      '简历',
      '赛博清明上河图',
    ]);
  });

  test('groups modified dates into relative Explorer buckets', () {
    final groups = groupFileEntries(
      [
        entry('today.txt', modified: DateTime(2026, 8, 11, 9)),
        entry('yesterday.txt', modified: DateTime(2026, 8, 10, 9)),
        entry('old.txt', modified: DateTime(2024, 3, 2)),
      ],
      FileGroupBy.dateModified,
      ascending: false,
      now: DateTime(2026, 8, 11, 12),
    );

    expect(groups.map((group) => group.label), ['今天', '昨天', '很久以前']);
  });

  test('groups sizes and reverses group order independently', () {
    final groups = groupFileEntries(
      [
        entry('folder', isDirectory: true),
        entry('empty.txt'),
        entry('tiny.txt', size: 1024),
        entry('huge.bin', size: 2 * 1024 * 1024 * 1024),
      ],
      FileGroupBy.size,
      ascending: false,
    );

    expect(groups.map((group) => group.label), [
      '巨大 (1 - 4 GB)',
      '微小 (0 - 16 KB)',
      '空 (0 KB)',
      '未指定',
    ]);
  });
}
