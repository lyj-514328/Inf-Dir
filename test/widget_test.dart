import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_entry.dart';

void main() {
  group('FileEntry', () {
    test('formattedSize for files', () {
      final entry = FileEntry(
        name: 'test.txt',
        path: 'C:\\test.txt',
        isDirectory: false,
        size: 1536,
        modified: DateTime(2025, 1, 1),
      );
      expect(entry.formattedSize, '2 KB');
    });

    test('formattedSize for directories is empty', () {
      final entry = FileEntry(
        name: 'folder',
        path: 'C:\\folder',
        isDirectory: true,
        size: 0,
        modified: DateTime(2025, 1, 1),
      );
      expect(entry.formattedSize, '');
    });

    test('type for directory', () {
      final entry = FileEntry(
        name: 'folder',
        path: 'C:\\folder',
        isDirectory: true,
        size: 0,
        modified: DateTime(2025, 1, 1),
      );
      expect(entry.type, '文件夹');
    });

    test('type for file with extension', () {
      final entry = FileEntry(
        name: 'video.mp4',
        path: 'C:\\video.mp4',
        isDirectory: false,
        size: 1024,
        modified: DateTime(2025, 1, 1),
      );
      expect(entry.type, 'MP4 文件');
    });
  });
}
