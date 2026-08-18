import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/directory_opener_resolver.dart';
import 'package:inf_dir/features/quick_view/plugin_manifest.dart';
import 'package:path/path.dart' as p;

PluginManifest _opener({
  List<String> executables = const [],
  List<String> appPaths = const [],
  List<String> installPaths = const [],
}) {
  return PluginManifest.fromJson({
    'manifestVersion': 1,
    'id': 'inf-dir.test-opener',
    'name': 'Test Opener',
    'version': '1.0.0',
    'capabilities': {
      'openDirectory': {
        if (executables.isNotEmpty) 'executables': executables,
        if (appPaths.isNotEmpty) 'appPaths': appPaths,
        if (installPaths.isNotEmpty) 'installPaths': installPaths,
      },
    },
  });
}

void main() {
  test('environment override wins over every other source', () {
    final temp = Directory.systemTemp.createTempSync('inf_dir_opener_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final exe = File(p.join(temp.path, 'override.exe'))
      ..writeAsStringSync('');
    var appPathsCalled = false;
    final resolver = DirectoryOpenerResolver(
      environment: {
        'INF_DIR_TEST_OPENER_PATH': exe.path,
        'PATH': temp.path,
      },
      appPathsLookup: (_) {
        appPathsCalled = true;
        return p.join(temp.path, 'app.exe');
      },
      fileExists: (path) => File(path).existsSync(),
    );

    final resolved = resolver.resolve(
      _opener(appPaths: ['app.exe'], executables: ['override.exe']),
    );

    expect(resolved, exe.path);
    expect(appPathsCalled, isFalse);
  });

  test('app paths lookup resolves before PATH scan', () {
    final temp = Directory.systemTemp.createTempSync('inf_dir_opener_');
    addTearDown(() => temp.deleteSync(recursive: true));
    File(p.join(temp.path, 'code.cmd')).writeAsStringSync('');
    File(p.join(temp.path, 'Code.exe')).writeAsStringSync('');
    final resolver = DirectoryOpenerResolver(
      environment: const {'PATH': ''},
      appPathsLookup: (name) =>
          name == 'Code.exe' ? p.join(temp.path, 'Code.exe') : null,
      pathDirectories: () => [temp.path],
      fileExists: (path) => File(path).existsSync(),
    );

    final resolved = resolver.resolve(
      _opener(appPaths: ['Code.exe'], executables: ['code.cmd']),
    );

    expect(resolved, p.join(temp.path, 'Code.exe'));
  });

  test('PATH scan finds executables in order', () {
    final temp = Directory.systemTemp.createTempSync('inf_dir_opener_');
    addTearDown(() => temp.deleteSync(recursive: true));
    File(p.join(temp.path, 'code.cmd')).writeAsStringSync('');
    final resolver = DirectoryOpenerResolver(
      environment: const {},
      appPathsLookup: (_) => null,
      pathDirectories: () => [temp.path],
      fileExists: (path) => File(path).existsSync(),
    );

    final resolved = resolver.resolve(
      _opener(executables: ['missing.exe', 'code.cmd']),
    );

    expect(resolved, p.join(temp.path, 'code.cmd'));
  });

  test('install paths expand environment variables', () {
    final temp = Directory.systemTemp.createTempSync('inf_dir_opener_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final exe = File(p.join(temp.path, 'tool.exe'))..writeAsStringSync('');
    final resolver = DirectoryOpenerResolver(
      environment: {'FAKEROOT': temp.path},
      appPathsLookup: (_) => null,
      pathDirectories: () => const [],
      fileExists: (path) => File(path).existsSync(),
    );

    final resolved = resolver.resolve(
      _opener(installPaths: [
        '%FAKEROOT%\\missing.exe',
        '%FAKEROOT%\\tool.exe',
        '%UNKNOWN_VAR%\\tool.exe',
      ]),
    );

    expect(resolved, exe.path);
  });

  test('returns null when nothing resolves', () {
    final resolver = DirectoryOpenerResolver(
      environment: const {},
      appPathsLookup: (_) => null,
      pathDirectories: () => const [],
      fileExists: (_) => false,
    );

    expect(
      resolver.resolve(
        _opener(
          appPaths: ['Code.exe'],
          executables: ['code.cmd'],
          installPaths: ['%LOCALAPPDATA%\\nope.exe'],
        ),
      ),
      isNull,
    );
  });

  test('default file existence check resolves real files', () {
    final temp = Directory.systemTemp.createTempSync('inf_dir_opener_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final exe = File(p.join(temp.path, 'real.exe'))..writeAsStringSync('');
    final resolver = DirectoryOpenerResolver(
      environment: const {},
      appPathsLookup: (_) => null,
      pathDirectories: () => [temp.path],
    );

    final resolved = resolver.resolve(_opener(executables: ['real.exe']));

    expect(resolved, exe.path);
  });

  test('override name normalizes plugin ids', () {
    expect(
      DirectoryOpenerResolver.environmentOverrideName(
        'inf-dir.vscode-open',
      ),
      'INF_DIR_VSCODE_OPEN_PATH',
    );
  });
}
