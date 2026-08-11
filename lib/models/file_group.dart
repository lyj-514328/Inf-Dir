import 'package:lpinyin/lpinyin.dart';

import 'file_entry.dart';

enum FileGroupBy { none, name, dateModified, type, size }

class FileEntryGroup {
  final String label;
  final List<FileEntry> entries;

  const FileEntryGroup({required this.label, required this.entries});
}

class _GroupDescriptor {
  final String key;
  final String label;
  final int order;

  const _GroupDescriptor(this.key, this.label, this.order);
}

List<FileEntryGroup> groupFileEntries(
  Iterable<FileEntry> entries,
  FileGroupBy groupBy, {
  bool ascending = true,
  DateTime? now,
}) {
  final source = entries.toList(growable: false);
  if (groupBy == FileGroupBy.none || source.isEmpty) {
    return [FileEntryGroup(label: '', entries: source)];
  }

  final reference = now ?? DateTime.now();
  final buckets =
      <String, ({_GroupDescriptor descriptor, List<FileEntry> entries})>{};
  for (final entry in source) {
    final descriptor = _descriptorFor(entry, groupBy, reference);
    final bucket = buckets.putIfAbsent(
      descriptor.key,
      () => (descriptor: descriptor, entries: <FileEntry>[]),
    );
    bucket.entries.add(entry);
  }

  final groups = buckets.values.toList(growable: false)
    ..sort((a, b) {
      var comparison = a.descriptor.order.compareTo(b.descriptor.order);
      if (comparison == 0) {
        comparison = a.descriptor.label.toLowerCase().compareTo(
          b.descriptor.label.toLowerCase(),
        );
      }
      return ascending ? comparison : -comparison;
    });

  return groups
      .map(
        (group) => FileEntryGroup(
          label: group.descriptor.label,
          entries: List.unmodifiable(group.entries),
        ),
      )
      .toList(growable: false);
}

_GroupDescriptor _descriptorFor(
  FileEntry entry,
  FileGroupBy groupBy,
  DateTime now,
) {
  return switch (groupBy) {
    FileGroupBy.none => const _GroupDescriptor('', '', 0),
    FileGroupBy.name => _nameDescriptor(entry.name),
    FileGroupBy.dateModified => _dateDescriptor(entry.modified, now),
    FileGroupBy.type => _typeDescriptor(entry),
    FileGroupBy.size => _sizeDescriptor(entry),
  };
}

_GroupDescriptor _nameDescriptor(String name) {
  if (name.isEmpty) return const _GroupDescriptor('other', '其他', 10);
  final first = name.codeUnitAt(0);
  if (first >= 0x30 && first <= 0x39) {
    return const _GroupDescriptor('0-9', '0 - 9', 0);
  }
  final letter = _englishInitial(name);
  if (letter != null) return _letterRange(letter);
  final pinyin = _pinyinInitial(name);
  if (pinyin != null) return _letterRange(pinyin, pinyin: true);
  return const _GroupDescriptor('other', '其他', 10);
}

// 英文按首字母归入字母区间；中文按拼音首字母归入独立的“拼音”区间。
_GroupDescriptor _letterRange(int letter, {bool pinyin = false}) {
  final (key, label, order) = switch (letter) {
    <= 0x66 => ('a-f', 'A - F', 1),
    <= 0x6C => ('g-l', 'G - L', 2),
    <= 0x73 => ('m-s', 'M - S', 3),
    _ => ('t-z', 'T - Z', 4),
  };
  if (!pinyin) return _GroupDescriptor(key, label, order);
  return _GroupDescriptor('py-$key', '拼音 $label', order + 5);
}

// 返回 a-z 码位，非英文字母返回 null。
int? _englishInitial(String name) {
  final code = name[0].toLowerCase().codeUnitAt(0);
  return (code >= 0x61 && code <= 0x7A) ? code : null;
}

// 中文转拼音取首字母，返回 a-z 码位。
int? _pinyinInitial(String name) {
  if (!ChineseHelper.isChinese(name[0])) return null;
  final pinyin = PinyinHelper.getFirstWordPinyin(name).toLowerCase();
  if (pinyin.isEmpty) return null;
  final initial = pinyin.codeUnitAt(0);
  return (initial >= 0x61 && initial <= 0x7A) ? initial : null;
}

_GroupDescriptor _dateDescriptor(DateTime modified, DateTime now) {
  final date = DateTime(modified.year, modified.month, modified.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
  final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
  final startOfMonth = DateTime(today.year, today.month);
  final startOfLastMonth = DateTime(today.year, today.month - 1);
  final startOfYear = DateTime(today.year);
  final startOfLastYear = DateTime(today.year - 1);

  if (!date.isBefore(today)) {
    return const _GroupDescriptor('today', '今天', 8);
  }
  if (!date.isBefore(yesterday)) {
    return const _GroupDescriptor('yesterday', '昨天', 7);
  }
  if (!date.isBefore(startOfWeek)) {
    return const _GroupDescriptor('this-week', '本周早些时候', 6);
  }
  if (!date.isBefore(startOfLastWeek)) {
    return const _GroupDescriptor('last-week', '上周', 5);
  }
  if (!date.isBefore(startOfMonth)) {
    return const _GroupDescriptor('this-month', '本月早些时候', 4);
  }
  if (!date.isBefore(startOfLastMonth)) {
    return const _GroupDescriptor('last-month', '上个月', 3);
  }
  if (!date.isBefore(startOfYear)) {
    return const _GroupDescriptor('this-year', '今年早些时候', 2);
  }
  if (!date.isBefore(startOfLastYear)) {
    return const _GroupDescriptor('last-year', '去年', 1);
  }
  return const _GroupDescriptor('long-ago', '很久以前', 0);
}

_GroupDescriptor _typeDescriptor(FileEntry entry) {
  final label = entry.type;
  return _GroupDescriptor(label.toLowerCase(), label, 0);
}

_GroupDescriptor _sizeDescriptor(FileEntry entry) {
  if (entry.isDirectory) {
    return const _GroupDescriptor('unspecified', '未指定', 0);
  }
  if (entry.size == 0) {
    return const _GroupDescriptor('empty', '空 (0 KB)', 1);
  }
  if (entry.size <= 16 * 1024) {
    return const _GroupDescriptor('tiny', '微小 (0 - 16 KB)', 2);
  }
  if (entry.size <= 1024 * 1024) {
    return const _GroupDescriptor('small', '小 (16 KB - 1 MB)', 3);
  }
  if (entry.size <= 128 * 1024 * 1024) {
    return const _GroupDescriptor('medium', '中等 (1 - 128 MB)', 4);
  }
  if (entry.size <= 1024 * 1024 * 1024) {
    return const _GroupDescriptor('large', '大 (128 MB - 1 GB)', 5);
  }
  if (entry.size <= 4 * 1024 * 1024 * 1024) {
    return const _GroupDescriptor('huge', '巨大 (1 - 4 GB)', 6);
  }
  return const _GroupDescriptor('gigantic', '超大 (> 4 GB)', 7);
}
