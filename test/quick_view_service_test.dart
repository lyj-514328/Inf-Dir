import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/plugin_manifest.dart';
import 'package:inf_dir/features/quick_view/quick_view_service.dart';
import 'package:inf_dir/features/quick_view/viewer_association_config.dart';
import 'package:inf_dir/features/quick_view/viewer_file_facts.dart';
import 'package:inf_dir/features/quick_view/viewer_rule.dart';
import 'package:inf_dir/features/quick_view/viewer_window_controller.dart';
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
    test('round-trips incremental overrides and path rules', () {
      final config = ViewerAssociationConfig.empty();
      config.setOverride(
        ViewerAssociationKind.extension,
        '.PDF',
        enabled: true,
        viewerOrder: ['viewer.b', 'viewer.a'],
        excludedViewerIds: ['viewer.c'],
      );
      config.setOverride(
        ViewerAssociationKind.fileName,
        'Dockerfile',
        enabled: false,
        viewerOrder: const [],
        excludedViewerIds: const [],
      );
      config.addRule(
        ViewerPathRule(
          id: 'path-work',
          enabled: true,
          mode: ViewerPathMatchMode.glob,
          pattern: r'C:\Work\**\*.pdf',
          viewerIds: const ['viewer.a'],
        ),
      );

      final decoded = jsonDecode(jsonEncode(config.toJson()));
      final restored = ViewerAssociationConfig.fromJson(
        Map<String, Object?>.from(decoded as Map),
      );

      final extensionOverride = restored.overrideFor(
        ViewerAssociationKind.extension,
        '.pdf',
      );
      expect(extensionOverride?.viewerOrder, ['viewer.b', 'viewer.a']);
      expect(extensionOverride?.excludedViewerIds, {'viewer.c'});
      expect(
        restored
            .overrideFor(ViewerAssociationKind.fileName, 'dockerfile')
            ?.enabled,
        isFalse,
      );
      expect(restored.rules.single.id, 'path-work');
      expect(restored.toJson()['schemaVersion'], 2);
    });

    test('extracts compound suffixes and treats a dotfile as a file name', () {
      expect(ViewerFileFacts.fromPath(r'C:\Work\archive.tar.gz').suffixes, [
        '.tar.gz',
        '.gz',
      ]);
      expect(ViewerFileFacts.fromPath(r'C:\Work\.gitignore').suffixes, isEmpty);
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
      _writePlugin(
        pluginRoot,
        id: 'viewer.archive-long',
        name: 'Archive Long Viewer',
        extensions: ['.tar.gz'],
      );
      _writePlugin(
        pluginRoot,
        id: 'viewer.archive-short',
        name: 'Archive Short Viewer',
        extensions: ['.gz'],
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

    test('matches compound suffixes from longest to shortest', () {
      final candidates = service.resolveCandidates(
        r'C:\archives\source.tar.gz',
      );

      expect(candidates.map((candidate) => candidate.plugin.manifest.id), [
        'viewer.archive-long',
        'viewer.archive-short',
      ]);
      expect(candidates.map((candidate) => candidate.matchedValue), [
        '.tar.gz',
        '.gz',
      ]);
    });

    test('places ordered path rules before file name and suffix matches', () {
      final rule = service.addPathRule(
        pattern: r'C:\docs\**\*.md',
        mode: ViewerPathMatchMode.glob,
        viewerIds: ['viewer.c'],
      );

      final candidates = service.resolveCandidates(r'C:\docs\README.md');

      expect(candidates.map((candidate) => candidate.plugin.manifest.id), [
        'viewer.c',
        'viewer.a',
        'viewer.b',
      ]);
      expect(candidates.first.matchKind, ViewerMatchKind.pathRule);
      expect(candidates.first.ruleId, rule.id);

      service.setPathRuleEnabled(rule.id, false);
      expect(
        service
            .resolve(r'C:\docs\README.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.a', 'viewer.b', 'viewer.c'],
      );
    });

    test('matches exact paths case-insensitively', () {
      service.addPathRule(
        pattern: r'C:\Docs\README.md',
        mode: ViewerPathMatchMode.exact,
        viewerIds: ['viewer.c'],
      );

      expect(
        service.resolveCandidates(r'c:\docs\readme.md').first.matchKind,
        ViewerMatchKind.pathRule,
      );
    });

    test('migrates v1 exactly and appends plugins installed later', () {
      final configFile = File(p.join(temp.path, 'legacy-associations.json'))
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'associations': {
              'extensions': {
                '.md': ['viewer.b'],
              },
            },
          }),
        );
      final migratingService = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(filePath: configFile.path),
        mimeTypeResolver: (_) => null,
      );
      addTearDown(migratingService.dispose);

      expect(
        migratingService
            .resolve(r'C:\docs\guide.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.b'],
      );
      final migratedJson = jsonDecode(configFile.readAsStringSync()) as Map;
      expect(migratedJson['schemaVersion'], 2);

      _writePlugin(
        pluginRoot,
        id: 'viewer.new',
        name: 'New Viewer',
        extensions: ['.md'],
      );
      migratingService.reload();

      expect(
        migratingService
            .resolve(r'C:\docs\guide.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.b', 'viewer.new'],
      );
    });

    test('does not overwrite an unsupported future config', () {
      final configFile = File(p.join(temp.path, 'future-associations.json'));
      const original = '{"schemaVersion":99,"futureSetting":true}';
      configFile.writeAsStringSync(original);
      final futureService = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(filePath: configFile.path),
        mimeTypeResolver: (_) => null,
      );
      addTearDown(futureService.dispose);

      futureService.addPathRule(
        pattern: r'C:\docs\**\*.md',
        mode: ViewerPathMatchMode.glob,
        viewerIds: ['viewer.b'],
      );

      expect(configFile.readAsStringSync(), original);
      expect(
        futureService.issues.map((issue) => issue.message),
        contains(contains('不支持的关联配置版本')),
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
        final windows = _FakeViewerWindowController();
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
            return windows.createProcess();
          },
          windowController: windows,
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

    test('replaces the attached viewer and preserves its placement', () async {
      final firstFile = File(p.join(temp.path, 'first.md'))
        ..writeAsStringSync('first');
      final secondFile = File(p.join(temp.path, 'second.md'))
        ..writeAsStringSync('second');
      final windows = _FakeViewerWindowController();
      final starts = <List<String>>[];
      final launchingService = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(
          filePath: p.join(temp.path, 'replace-associations.json'),
        ),
        mimeTypeResolver: (_) => null,
        processStarter: (executable, arguments, workingDirectory) async {
          starts.add(arguments);
          return windows.createProcess();
        },
        windowController: windows,
      );
      addTearDown(launchingService.dispose);
      launchingService.setCandidates(ViewerAssociationKind.extension, '.md', [
        'viewer.b',
      ]);

      expect((await launchingService.open(firstFile.path)).started, isTrue);
      final firstWindow = windows.createdWindows.single;
      expect((await launchingService.open(secondFile.path)).started, isTrue);

      expect(starts.first, [p.absolute(firstFile.path)]);
      expect(starts.last.take(2), [
        p.absolute(secondFile.path),
        '--window-placement',
      ]);
      expect(jsonDecode(starts.last.last), {
        'version': 2,
        'x': 120,
        'y': 80,
        'clientWidth': 944,
        'clientHeight': 681,
        'maximized': false,
      });
      expect(windows.closeRequests, [firstWindow]);
      expect(launchingService.hasAttachedViewer, isTrue);
    });

    test('clears attached state when the viewer exits itself', () async {
      final file = File(p.join(temp.path, 'first.md'))
        ..writeAsStringSync('first');
      final windows = _FakeViewerWindowController();
      final launchingService = QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(
          filePath: p.join(temp.path, 'exit-associations.json'),
        ),
        mimeTypeResolver: (_) => null,
        processStarter: (executable, arguments, workingDirectory) async =>
            windows.createProcess(),
        windowController: windows,
      );
      addTearDown(launchingService.dispose);
      launchingService.setCandidates(ViewerAssociationKind.extension, '.md', [
        'viewer.b',
      ]);

      await launchingService.open(file.path);
      expect(launchingService.hasAttachedViewer, isTrue);

      windows.exitWindow(windows.createdWindows.single);
      await Future<void>.delayed(Duration.zero);

      expect(launchingService.hasAttachedViewer, isFalse);
    });

    test(
      'detach leaves the old viewer alive and the next open starts fresh',
      () async {
        final firstFile = File(p.join(temp.path, 'first.md'))
          ..writeAsStringSync('first');
        final secondFile = File(p.join(temp.path, 'second.md'))
          ..writeAsStringSync('second');
        final windows = _FakeViewerWindowController();
        final launchingService = QuickViewService(
          pluginRoots: [pluginRoot],
          associationStore: ViewerAssociationStore(
            filePath: p.join(temp.path, 'detach-associations.json'),
          ),
          mimeTypeResolver: (_) => null,
          processStarter: (executable, arguments, workingDirectory) async =>
              windows.createProcess(),
          windowController: windows,
        );
        addTearDown(launchingService.dispose);
        launchingService.setCandidates(ViewerAssociationKind.extension, '.md', [
          'viewer.b',
        ]);

        await launchingService.open(firstFile.path);
        final detachedWindow = windows.createdWindows.single;
        expect(await launchingService.detachViewer(), isTrue);
        expect(launchingService.hasAttachedViewer, isFalse);
        expect(windows.closeRequests, isEmpty);

        await launchingService.open(secondFile.path);
        expect(windows.createdWindows, hasLength(2));
        await launchingService.shutdown();
        expect(windows.closeRequests, [windows.createdWindows.last]);
        expect(windows.closeRequests, isNot(contains(detachedWindow)));
      },
    );
  });
}

class _FakeViewerWindowController implements ViewerWindowController {
  final ViewerWindowPlacement initialPlacement = const ViewerWindowPlacement(
    left: 120,
    top: 80,
    right: 1080,
    bottom: 800,
    clientWidth: 944,
    clientHeight: 681,
    maximized: false,
  );
  final List<int> createdWindows = [];
  final List<int> closeRequests = [];

  final Map<int, int> _windowByProcess = {};
  final Map<int, int> _processByWindow = {};
  final Map<int, ViewerWindowPlacement> _placementByWindow = {};
  final Map<int, Completer<int>> _exitByProcess = {};
  int _nextProcessId = 1000;
  int _nextWindowHandle = 5000;

  ViewerProcessHandle createProcess() {
    final processId = _nextProcessId++;
    final windowHandle = _nextWindowHandle++;
    final exit = Completer<int>();
    _windowByProcess[processId] = windowHandle;
    _processByWindow[windowHandle] = processId;
    _placementByWindow[windowHandle] = initialPlacement;
    _exitByProcess[processId] = exit;
    createdWindows.add(windowHandle);
    return ViewerProcessHandle(
      processId: processId,
      exitCode: exit.future,
      terminate: () {
        if (!exit.isCompleted) exit.complete(-1);
        return true;
      },
    );
  }

  void exitWindow(int windowHandle) {
    final processId = _processByWindow[windowHandle];
    final exit = processId == null ? null : _exitByProcess[processId];
    if (exit != null && !exit.isCompleted) exit.complete(0);
  }

  @override
  ViewerWindowPlacement? capturePlacement(
    int windowHandle, {
    String? logLabel,
  }) => _placementByWindow[windowHandle];

  @override
  bool requestClose(int windowHandle) {
    closeRequests.add(windowHandle);
    final processId = _processByWindow[windowHandle];
    final exit = processId == null ? null : _exitByProcess[processId];
    if (exit != null && !exit.isCompleted) exit.complete(0);
    return processId != null;
  }

  @override
  Future<int?> waitForTopLevelWindow(
    int processId, {
    required Duration timeout,
  }) async => _windowByProcess[processId];
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
