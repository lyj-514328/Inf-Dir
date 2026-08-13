import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/file_service.dart';

void main() {
  test(
    'recycle delete never falls back to permanent dart:io deletion',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'inf-dir-recycle-safety-',
      );
      final file = File('${tempDirectory.path}\\keep.txt');
      await file.writeAsString('keep');

      try {
        await expectLater(
          FileService.deleteEntry(file.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.exists(), isTrue);
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    },
  );
}
