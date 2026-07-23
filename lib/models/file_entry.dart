import 'package:path/path.dart' as p;

class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

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
