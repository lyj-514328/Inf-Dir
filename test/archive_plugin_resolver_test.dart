import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/archive_plugin_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ArchivePluginResolver', () {
    late Directory temp;
    late Directory pluginRoot;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf_dir_archive_plugins_');
      pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('resolves a 7-Zip provider by manifest capability', () {
      final executable = _writeArchivePlugin(pluginRoot);

      expect(
        ArchivePluginResolver.resolve(
          pluginId: 'inf-dir.7z-archive',
          type: ArchivePluginType.sevenZip,
          roots: [pluginRoot],
        ),
        executable.path,
      );
    });

    test('rejects a mismatched protocol', () {
      _writeArchivePlugin(pluginRoot, protocol: 'unknown-v1');

      expect(
        ArchivePluginResolver.resolve(
          pluginId: 'inf-dir.7z-archive',
          type: ArchivePluginType.sevenZip,
          roots: [pluginRoot],
        ),
        isNull,
      );
    });

    test('rejects an entrypoint that escapes the package', () {
      _writeArchivePlugin(pluginRoot, entrypoint: '..\\7za.exe');

      expect(
        ArchivePluginResolver.resolve(
          pluginId: 'inf-dir.7z-archive',
          type: ArchivePluginType.sevenZip,
          roots: [pluginRoot],
        ),
        isNull,
      );
    });

    test('bundled manifest declares the pinned release and formats', () {
      final manifest =
          jsonDecode(
                File('plugins/archive/7zip/plugin.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(manifest['id'], 'inf-dir.7z-archive');
      expect(manifest['version'], '26.02');
      expect(manifest['entrypoint'], '7za.exe');
      expect(manifest['capabilities']['archive']['type'], '7zip');
      expect(manifest['capabilities']['archive']['protocol'], '7zip-cli-v1');
      expect(manifest['capabilities']['archive']['formats'], ['7z', 'zip']);
    });
  });
}

File _writeArchivePlugin(
  Directory root, {
  String entrypoint = '7za.exe',
  String protocol = '7zip-cli-v1',
}) {
  final directory = Directory(p.join(root.path, 'inf-dir.7z-archive'))
    ..createSync();
  final executable = File(p.join(directory.path, p.basename(entrypoint)))
    ..writeAsBytesSync(const []);
  File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
    jsonEncode({
      'manifestVersion': 1,
      'id': 'inf-dir.7z-archive',
      'name': '7-Zip archive operations',
      'version': '26.02',
      'entrypoint': entrypoint,
      'capabilities': {
        'archive': {'type': '7zip', 'protocol': protocol},
      },
    }),
  );
  return executable;
}
