import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/search_plugin_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SearchPluginResolver', () {
    late Directory temp;
    late Directory pluginRoot;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf_dir_search_plugins_');
      pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('resolves an available provider by manifest capability', () {
      final executable = _writeSearchPlugin(
        pluginRoot,
        id: 'inf-dir.fd-search',
        type: 'fileName',
        entrypoint: 'fd.exe',
      );

      expect(
        SearchPluginResolver.resolve(
          pluginId: 'inf-dir.fd-search',
          type: SearchPluginType.fileName,
          roots: [pluginRoot],
        ),
        executable.path,
      );
    });

    test('rejects a mismatched capability protocol', () {
      _writeSearchPlugin(
        pluginRoot,
        id: 'inf-dir.ripgrep-search',
        type: 'content',
        protocol: 'unknown-v1',
        entrypoint: 'rg.exe',
      );

      expect(
        SearchPluginResolver.resolve(
          pluginId: 'inf-dir.ripgrep-search',
          type: SearchPluginType.content,
          roots: [pluginRoot],
        ),
        isNull,
      );
    });

    test('rejects an entrypoint that escapes its package', () {
      _writeSearchPlugin(
        pluginRoot,
        id: 'inf-dir.ripgrep-search',
        type: 'content',
        entrypoint: '..\\rg.exe',
      );

      expect(
        SearchPluginResolver.resolve(
          pluginId: 'inf-dir.ripgrep-search',
          type: SearchPluginType.content,
          roots: [pluginRoot],
        ),
        isNull,
      );
    });

    test('bundled search manifests declare the expected versions', () {
      final fd =
          jsonDecode(File('plugins/search/fd/plugin.json').readAsStringSync())
              as Map<String, dynamic>;
      final rg =
          jsonDecode(
                File('plugins/search/ripgrep/plugin.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(fd['id'], 'inf-dir.fd-search');
      expect(fd['version'], '10.4.2');
      expect(fd['capabilities']['search']['type'], 'fileName');
      expect(fd['capabilities']['search']['protocol'], 'fd-nul-v1');
      expect(rg['id'], 'inf-dir.ripgrep-search');
      expect(rg['version'], '15.2.0');
      expect(rg['capabilities']['search']['type'], 'content');
      expect(rg['capabilities']['search']['protocol'], 'ripgrep-json-v1');
    });
  });
}

File _writeSearchPlugin(
  Directory root, {
  required String id,
  required String type,
  required String entrypoint,
  String? protocol,
}) {
  final directory = Directory(p.join(root.path, id))..createSync();
  final executable = File(p.join(directory.path, p.basename(entrypoint)))
    ..writeAsBytesSync(const []);
  File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
    jsonEncode({
      'manifestVersion': 1,
      'id': id,
      'name': id,
      'version': '1.0.0',
      'entrypoint': entrypoint,
      'capabilities': {
        'search': {
          'type': type,
          'protocol':
              protocol ??
              (type == 'fileName' ? 'fd-nul-v1' : 'ripgrep-json-v1'),
        },
      },
    }),
  );
  return executable;
}
