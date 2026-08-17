import 'package:path/path.dart' as p;

class ViewerFileFacts {
  const ViewerFileFacts({
    required this.normalizedPath,
    required this.fileName,
    required this.suffixes,
    this.mimeType,
  });

  factory ViewerFileFacts.fromPath(String filePath, {String? mimeType}) {
    final absolutePath = p.windows.isAbsolute(filePath)
        ? filePath
        : p.absolute(filePath);
    final normalizedPath = p.windows
        .normalize(absolutePath)
        .replaceAll('/', r'\')
        .toLowerCase();
    final fileName = p.windows.basename(normalizedPath).toLowerCase();

    return ViewerFileFacts(
      normalizedPath: normalizedPath,
      fileName: fileName,
      suffixes: _suffixesFor(fileName),
      mimeType: _normalizeMime(mimeType),
    );
  }

  final String normalizedPath;
  final String fileName;
  final List<String> suffixes;
  final String? mimeType;

  static List<String> _suffixesFor(String fileName) {
    final result = <String>[];
    var dot = fileName.indexOf('.', 1);
    while (dot >= 0) {
      final suffix = fileName.substring(dot);
      if (suffix.length > 1) result.add(suffix);
      dot = fileName.indexOf('.', dot + 1);
    }
    return List.unmodifiable(result);
  }

  static String? _normalizeMime(String? value) {
    if (value == null) return null;
    final normalized = value.split(';').first.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
