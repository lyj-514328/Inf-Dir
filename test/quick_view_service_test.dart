import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/plugin_manifest.dart';
import 'package:inf_dir/features/quick_view/quick_view_service.dart';
import 'package:inf_dir/features/quick_view/viewer_association_config.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PluginManifest', () {
    test('all bundled manifests are valid and have unique IDs', () {
      final manifests = Directory('plugins')
          .listSync()
          .whereType<Directory>()
          .map((directory) => File(p.join(directory.path, 'plugin.json')))
          .where((file) => file.existsSync())
          .map(PluginManifest.read)
          .toList();

      expect(manifests, isNotEmpty);
      expect(
        manifests.map((manifest) => manifest.id).toSet(),
        hasLength(manifests.length),
      );
    });

    test('normalizes all three match groups', () {
      final manifest = PluginManifest.fromJson({
        'manifestVersion': 1,
        'id': 'example.viewer',
        'name': 'Example',
        'version': '1.0.0',
        'entrypoint': 'viewer.exe',
        'capabilities': {
          'quickView': {
            'extensions': ['.PDF', '.pdf'],
            'fileNames': ['Dockerfile'],
            'mimeTypes': ['Application/PDF', 'image/*'],
          },
        },
      });

      expect(manifest.quickView.extensions, ['.pdf']);
      expect(manifest.quickView.fileNames, ['dockerfile']);
      expect(manifest.quickView.mimeTypes, ['application/pdf', 'image/*']);
      expect(
        manifest.quickView.supports(
          ViewerAssociationKind.mimeType,
          'image/png',
        ),
        isTrue,
      );
    });

    test('rejects an entrypoint outside the plugin package', () {
      expect(
        () => PluginManifest.fromJson({
          'manifestVersion': 1,
          'id': 'example.viewer',
          'name': 'Example',
          'version': '1.0.0',
          'entrypoint': '..\\viewer.exe',
          'capabilities': {
            'quickView': {
              'extensions': ['.txt'],
            },
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('ViewerAssociationConfig', () {
    test('round-trips candidate order and explicit empty lists', () {
      final config = ViewerAssociationConfig.empty();
      config.set(ViewerAssociationKind.extension, '.PDF', [
        'viewer.b',
        'viewer.a',
      ]);
      config.set(ViewerAssociationKind.fileName, 'Dockerfile', const []);

      final decoded = jsonDecode(jsonEncode(config.toJson()));
      final restored = ViewerAssociationConfig.fromJson(
        Map<String, Object?>.from(decoded as Map),
      );

      expect(restored.idsFor(ViewerAssociationKind.extension, '.pdf'), [
        'viewer.b',
        'viewer.a',
      ]);
      expect(
        restored.idsFor(ViewerAssociationKind.fileName, 'dockerfile'),
        isEmpty,
      );
    });
  });

  group('QuickViewService resolver', () {
    late Directory temp;
    late Directory pluginRoot;
    late QuickViewService service;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf_dir_plugins_');
      pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
      _writePlugin(
        pluginRoot,
        id: 'viewer.a',
        name: 'A Viewer',
        fileNames: ['readme.md'],
      );
      _writePlugin(
        pluginRoot,
        id: 'viewer.b',
        name: 'B Viewer',
        extensions: ['.md'],
        fileNames: ['readme.md'],
      );
      _writePlugin(
        pluginRoot,
        id: 'viewer.c',
        name: 'C Viewer',
        extensions: ['.md'],
      );
      _writePlugin(
        pluginRoot,
        id: 'viewer.image',
        name: 'Image Viewer',
        mimeTypes: ['image/*'],
      );
      service = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(
          filePath: p.join(temp.path, 'associations.json'),
        ),
        mimeTypeResolver: (_) => null,
      );
    });

    tearDown(() {
      service.dispose();
      temp.deleteSync(recursive: true);
    });

    test('merges file name and extension candidates without duplicates', () {
      service.setCandidates(ViewerAssociationKind.fileName, 'README.md', [
        'viewer.a',
        'viewer.b',
      ]);
      service.setCandidates(ViewerAssociationKind.extension, '.md', [
        'viewer.b',
        'viewer.c',
      ]);

      expect(
        service
            .resolve(r'C:\docs\README.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.a', 'viewer.b', 'viewer.c'],
      );
    });

    test('uses MIME wildcard candidates after extension candidates', () {
      expect(
        service
            .resolve(r'C:\images\photo', mimeType: 'image/png')
            .map((plugin) => plugin.manifest.id),
        ['viewer.image'],
      );
    });

    test('ignores manifests that only declare search capability', () {
      final directory = Directory(p.join(pluginRoot.path, 'inf-dir.fd-search'))
        ..createSync();
      File(p.join(directory.path, 'fd.exe')).writeAsBytesSync(const []);
      File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
        jsonEncode({
          'manifestVersion': 1,
          'id': 'inf-dir.fd-search',
          'name': 'fd',
          'version': '10.4.2',
          'entrypoint': 'fd.exe',
          'capabilities': {
            'search': {'type': 'fileName', 'protocol': 'fd-nul-v1'},
          },
        }),
      );

      service.reload();

      expect(
        service.plugins.map((plugin) => plugin.manifest.id),
        isNot(contains('inf-dir.fd-search')),
      );
      expect(service.issues, isEmpty);
    });

    test('uses the platform MIME resolver when no MIME is supplied', () {
      final resolvingService = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(
          filePath: p.join(temp.path, 'mime-associations.json'),
        ),
        mimeTypeResolver: (_) => 'image/png',
      );
      addTearDown(resolvingService.dispose);

      expect(
        resolvingService
            .resolve(r'C:\\images\\photo')
            .map((plugin) => plugin.manifest.id),
        ['viewer.image'],
      );
    });

    test('rejects a configured plugin not declared by its manifest', () {
      expect(
        () => service.setCandidates(ViewerAssociationKind.extension, '.md', [
          'viewer.a',
        ]),
        throwsArgumentError,
      );
    });

    test('explicit empty list disables and reset restores auto candidates', () {
      service.disableAssociation(ViewerAssociationKind.extension, '.md');
      expect(
        service.candidatesForAssociation(
          ViewerAssociationKind.extension,
          '.md',
        ),
        isEmpty,
      );

      service.resetAssociation(ViewerAssociationKind.extension, '.md');
      expect(
        service
            .candidatesForAssociation(ViewerAssociationKind.extension, '.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.b', 'viewer.c'],
      );
    });

    test(
      'keeps a spaced path in one argument and falls back on start failure',
      () async {
        final file = File(p.join(temp.path, 'report with spaces.md'))
          ..writeAsStringSync('test');
        final starts = <(String, List<String>, String)>[];
        final launchingService = QuickViewService(
          pluginRoots: [pluginRoot],
          associationStore: ViewerAssociationStore(
            filePath: p.join(temp.path, 'launch-associations.json'),
          ),
          mimeTypeResolver: (_) => null,
          processStarter: (executable, arguments, workingDirectory) async {
            starts.add((executable, arguments, workingDirectory));
            if (executable.contains('viewer.b')) {
              throw const ProcessException('viewer.b', [], 'failed');
            }
          },
        );
        addTearDown(launchingService.dispose);
        launchingService.setCandidates(ViewerAssociationKind.extension, '.md', [
          'viewer.b',
          'viewer.c',
        ]);

        final result = await launchingService.open(file.path);

        expect(result.started, isTrue);
        expect(result.plugin?.manifest.id, 'viewer.c');
        expect(starts, hasLength(2));
        expect(starts.first.$2, [p.absolute(file.path)]);
      },
    );
  });
}

void _writePlugin(
  Directory root, {
  required String id,
  required String name,
  List<String> extensions = const [],
  List<String> fileNames = const [],
  List<String> mimeTypes = const [],
}) {
  final directory = Directory(p.join(root.path, id))..createSync();
  File(p.join(directory.path, 'viewer.exe')).writeAsBytesSync(const []);
  File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
    jsonEncode({
      'manifestVersion': 1,
      'id': id,
      'name': name,
      'version': '1.0.0',
      'entrypoint': 'viewer.exe',
      'capabilities': {
        'quickView': {
          if (extensions.isNotEmpty) 'extensions': extensions,
          if (fileNames.isNotEmpty) 'fileNames': fileNames,
          if (mimeTypes.isNotEmpty) 'mimeTypes': mimeTypes,
        },
      },
    }),
  );
}
