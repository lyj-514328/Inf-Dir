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
          '-mx5',
          '-y',
          r'C:\work\report.7z',
          r'C:\work\report.txt',
          r'C:\work\folder with spaces',
        ],
      );
    });

    test('builds create arguments with password and header encryption', () {
      expect(
        ArchiveService.buildArguments(
          ['a.txt'],
          'out.7z',
          ArchiveFormat.sevenZip,
          password: 'secret',
          compressionLevel: 9,
          encryptHeaders: true,
        ),
        ['a', '-t7z', '-mx9', '-psecret', '-mhe=on', '-y', 'out.7z', 'a.txt'],
      );
    });

    test('does not emit -mhe for ZIP archives', () {
      expect(
        ArchiveService.buildArguments(
          ['a.txt'],
          'out.zip',
          ArchiveFormat.zip,
          password: 'secret',
          encryptHeaders: true,
        ),
        isNot(contains('-mhe=on')),
      );
    });

    test('builds extract arguments for each overwrite mode', () {
      expect(
        ArchiveService.buildExtractArguments(
          'in.zip',
          r'C:\out',
          overwrite: ArchiveOverwriteMode.skip,
          password: 'pw',
          codePage: 936,
        ),
        ['x', r'-oC:\out', '-aos', '-mcp=936', '-ppw', '-y', 'in.zip'],
      );
      expect(
        ArchiveService.buildExtractArguments(
          'in.7z',
          r'C:\out',
          overwrite: ArchiveOverwriteMode.keepBoth,
        ),
        ['x', r'-oC:\out', '-aou', '-y', 'in.7z'],
      );
    });

    test('recognizes archive file names by extension', () {
      expect(isArchiveName('report.zip'), isTrue);
      expect(isArchiveName('report.7z'), isTrue);
      expect(isArchiveName('report.tar.gz'), isTrue);
      expect(isArchiveName('report.txt'), isFalse);
      expect(isArchiveName('report'), isFalse);
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
