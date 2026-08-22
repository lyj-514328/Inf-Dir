import 'dart:typed_data';

import 'package:path/path.dart' as p;

class FileEntry {
  final String name;
  final Uint8List? nameSortKey;
  /// Filesystem path. Shell namespace items may not have one.
  final String? path;
  /// Opaque Shell identity (currently a native PIDL transport value).
  final String? shellId;
  final bool isDirectory;
  final bool hasChildren;
  final int size;
  final DateTime modified;

  // --- Recycle Bin specific fields (optional) ---

  /// Directory the item was deleted from (`System.Recycle.DeletedFrom`).
  final String? originalPath;

  /// Deletion date string from shell (e.g. "2026/07/24 15:30:00")
  final String? recycleDate;

  /// Full Shell parsing name used for Recycle Bin restore operations.
  final String? parsingName;
  final bool isRecycleBinEntry;

  const FileEntry({
    required this.name,
    this.nameSortKey,
    this.path,
    this.shellId,
    required this.isDirectory,
    this.hasChildren = false,
    required this.size,
    required this.modified,
    this.originalPath,
    this.recycleDate,
    this.parsingName,
    this.isRecycleBinEntry = false,
  });

  /// Identity used by selection, Shell operations, and item navigation.
  /// It is intentionally separate from [path], which is only a filesystem
  /// path when one exists.
  String get identity => shellId ?? path ?? '';

  bool get isShellItem => shellId != null;

  /// Whether this entry is inside the Recycle Bin.
  bool get isRecycleBinItem =>
      isRecycleBinEntry ||
      originalPath != null ||
      recycleDate != null ||
      parsingName != null;

  int compareNameTo(FileEntry other) {
    final thisKey = nameSortKey;
    final otherKey = other.nameSortKey;

    var comparison = 0;
    if (thisKey != null && otherKey != null) {
      comparison = _compareSortKeys(thisKey, otherKey);
    } else {
      comparison = name.toLowerCase().compareTo(other.name.toLowerCase());
    }

    if (comparison != 0) return comparison;

    comparison = name.compareTo(other.name);
    if (comparison != 0) return comparison;
    return identity.compareTo(other.identity);
  }

  static int _compareSortKeys(Uint8List a, Uint8List b) {
    final commonLength = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < commonLength; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return a.length.compareTo(b.length);
  }

  String get type {
    if (isDirectory) return '文件夹';
    final ext = p.extension(name).toLowerCase();
    if (ext.isEmpty) return '文件';
    final extName = ext.substring(1).toUpperCase();
    return '$extName 文件';
  }

  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    final y = modified.year;
    final m = modified.month.toString().padLeft(2, '0');
    final d = modified.day.toString().padLeft(2, '0');
    final h = modified.hour.toString().padLeft(2, '0');
    final min = modified.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  }
}
