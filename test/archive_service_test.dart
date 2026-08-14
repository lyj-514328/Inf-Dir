import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/archive_service.dart';

void main() {
  group('ArchiveService', () {
    test('builds 7z arguments without shell quoting', () {
      expect(
        ArchiveService.buildArguments(
          [r'C:\work\report.txt', r'C:\work\folder with spaces'],
          r'C:\work\report.7z',
          ArchiveFormat.sevenZip,
        ),
        [
          'a',
          '-t7z',
          '-y',
          r'C:\work\report.7z',
          r'C:\work\report.txt',
          r'C:\work\folder with spaces',
        ],
      );
    });

    test(
      'runs the resolved plugin for ZIP and forwards working directory',
      () async {
        String? executable;
        List<String>? arguments;
        String? capturedWorkingDirectory;
        final service = ArchiveService(
          executable: '7za-test.exe',
          runner: (value, args, {workingDirectory}) async {
            executable = value;
            arguments = args;
            capturedWorkingDirectory = workingDirectory;
            return ProcessResult(1, 0, '', '');
          },
        );

        await service.createArchive(
          [r'C:\work\report.txt'],
          r'C:\work\report.zip',
          format: ArchiveFormat.zip,
        );

        expect(executable, '7za-test.exe');
        expect(arguments, containsAllInOrder(['a', '-tzip', '-y']));
        expect(arguments, contains(r'C:\work\report.zip'));
        expect(capturedWorkingDirectory, r'C:\work');
      },
    );

    test('surfaces a non-zero 7-Zip exit code', () async {
      final service = ArchiveService(
        executable: '7za-test.exe',
        runner: (value, args, {workingDirectory}) async =>
            ProcessResult(1, 2, '', 'archive is corrupt'),
      );

      await expectLater(
        service.createArchive(
          [r'C:\work\report.txt'],
          r'C:\work\report.7z',
          format: ArchiveFormat.sevenZip,
        ),
        throwsA(
          isA<ArchiveException>().having(
            (error) => error.message,
            'message',
            contains('archive is corrupt'),
          ),
        ),
      );
    });

    test('rejects an empty input list before starting the process', () async {
      var called = false;
      final service = ArchiveService(
        executable: '7za-test.exe',
        runner: (value, args, {workingDirectory}) async {
          called = true;
          return ProcessResult(1, 0, '', '');
        },
      );

      await expectLater(
        service.createArchive(
          const [],
          r'C:\work\report.7z',
          format: ArchiveFormat.sevenZip,
        ),
        throwsA(isA<ArchiveException>()),
      );
      expect(called, isFalse);
    });

    test(
      'asks the user to configure the plugin when it is unavailable',
      () async {
        final service = ArchiveService(discoverExecutable: false);

        await expectLater(
          service.createArchive(
            [r'C:\work\report.txt'],
            r'C:\work\report.zip',
            format: ArchiveFormat.zip,
          ),
          throwsA(
            isA<ArchiveException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('plugins/archive/build.bat'),
                contains('INF_DIR_7Z_PATH'),
              ),
            ),
          ),
        );
      },
    );
  });
}
