import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/directory_opener_resolver.dart';
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

    test('bundled email viewer claims the first-version mail formats', () {
      final manifest = PluginManifest.read(
        File(p.join('plugins', 'email-view', 'plugin.json')),
      );

      expect(manifest.id, 'inf-dir.email-view');
      expect(
        manifest.quickView!.extensions,
        containsAll(['.eml', '.emlx', '.msg', '.oft', '.dat']),
      );
      expect(manifest.quickView!.fileNames, contains('winmail.dat'));
      expect(manifest.quickView!.mimeTypes, contains('application/ms-tnef'));
    });

    test('bundled image viewer claims the supported RAW formats', () {
      final manifest = PluginManifest.read(
        File(p.join('plugins', 'img-view', 'plugin.json')),
      );

      expect(manifest.id, 'inf-dir.image-view');
      expect(
        manifest.quickView!.extensions,
        containsAll([
          '.ari', '.arw', '.cr2', '.crw', '.dng', '.nef', '.nrw', '.orf',
          '.pef', '.raf', '.rw2', '.srw', '.x3f',
        ]),
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

      final quickView = manifest.quickView!;
      expect(quickView.extensions, ['.pdf']);
      expect(quickView.fileNames, ['dockerfile']);
      expect(quickView.mimeTypes, ['application/pdf', 'image/*']);
      expect(
        quickView.supports(
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

    test('parses openDirectory manifests without entrypoint', () {
      final manifest = PluginManifest.fromJson({
        'manifestVersion': 1,
        'id': 'example.dir-open',
        'name': 'Example Open',
        'version': '1.0.0',
        'capabilities': {
          'openDirectory': {
            'executables': ['code.cmd'],
            'appPaths': ['Code.exe'],
            'installPaths': ['%ProgramFiles%\\Example\\example.exe'],
            'arguments': ['-d', '{dir}'],
          },
        },
      });

      expect(manifest.entrypoint, isNull);
      expect(manifest.quickView, isNull);
      expect(manifest.openDirectory!.executables, ['code.cmd']);
      expect(manifest.openDirectory!.appPaths, ['Code.exe']);
      expect(manifest.openDirectory!.arguments, ['-d', '{dir}']);
    });

    test('quickView capability still requires an entrypoint', () {
      expect(
        () => PluginManifest.fromJson({
          'manifestVersion': 1,
          'id': 'example.viewer',
          'name': 'Example',
          'version': '1.0.0',
          'capabilities': {
            'quickView': {
              'extensions': ['.txt'],
            },
          },
        }),
        throwsFormatException,
      );
    });

    test('rejects manifests without a supported capability', () {
      expect(
        () => PluginManifest.fromJson({
          'manifestVersion': 1,
          'id': 'example.none',
          'name': 'Example',
          'version': '1.0.0',
          'capabilities': {
            'search': {'type': 'fileName', 'protocol': 'fd-nul-v1'},
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('ViewerAssociationConfig', () {
    ViewerRuleGroup userGroup(String id) =>
        ViewerRuleGroup(id: id, name: '自定义', preset: false, enabled: true);

    test('round-trips user rules into schema V3 with a default stub', () {
      final config = ViewerAssociationConfig.empty();
      final custom = userGroup('custom-x');
      config.addGroup(custom);
      config.addRule(
        custom.id,
        ViewerRule(
          id: 'extension-bar',
          managed: false,
          enabled: true,
          type: ViewerRuleType.extension,
          value: '.bar',
          rules: [
            ViewerRule(
              id: 'mime-bar-v1',
              managed: false,
              enabled: true,
              type: ViewerRuleType.mimeType,
              value: 'application/x-bar-v1',
              viewers: [
                ViewerRuleViewer(id: 'viewer.c', managed: false, enabled: true),
              ],
            ),
          ],
          viewers: [
            ViewerRuleViewer(id: 'viewer.a', managed: false, enabled: false),
            ViewerRuleViewer(id: 'viewer.b', managed: false, enabled: true),
          ],
        ),
      );
      config.addRule(
        custom.id,
        ViewerRule(
          id: 'path-work',
          managed: false,
          enabled: true,
          type: ViewerRuleType.path,
          value: r'C:\Work\**\*.pdf',
          pathMode: ViewerPathMatchMode.glob,
        ),
      );

      final decoded = jsonDecode(jsonEncode(config.toJson()));
      final restored = ViewerAssociationConfig.fromJson(
        Map<String, Object?>.from(decoded as Map),
        defaultGroup: ViewerAssociationConfig.presetDefaultGroup(),
      );

      final extensionRule = restored.rule('extension-bar');
      expect(extensionRule.type, ViewerRuleType.extension);
      expect(extensionRule.viewers.map((viewer) => viewer.id), [
        'viewer.a',
        'viewer.b',
      ]);
      expect(extensionRule.viewers.first.enabled, isFalse);
      expect(extensionRule.rules.single.type, ViewerRuleType.mimeType);
      expect(extensionRule.rules.single.viewers.single.id, 'viewer.c');
      expect(restored.rule('path-work').type, ViewerRuleType.path);
      expect(restored.toJson()['schemaVersion'], 3);
      expect(restored.groups.map((group) => group.id), [
        ViewerAssociationConfig.defaultGroupId,
        'custom-x',
      ]);
      final savedGroups = restored.toJson()['groups']! as List;
      expect((savedGroups.first as Map)['preset'], isTrue);
      expect(savedGroups.first, isNot(contains('rules')));
    });

    test('migrates v2 built-in groups and keeps user rules', () {
      final defaultGroup = ViewerAssociationConfig.parsePresetGroup({
        'schemaVersion': 3,
        'id': 'default',
        'name': '默认',
        'rules': [
          _jsonRule('ext-pdf', 'extension', '.pdf', ['viewer.a']),
        ],
      });
      final restored = ViewerAssociationConfig.fromJson({
        'schemaVersion': 2,
        'groups': [
          {
            'id': ViewerAssociationConfig.builtInExtensionGroupId,
            'name': '扩展名',
            'builtIn': true,
            'enabled': true,
            'rules': [
              {
                'id': 'builtin-extension-2e706466',
                'managed': true,
                'enabled': true,
                'type': 'extension',
                'value': '.pdf',
                'rules': <Object?>[],
                'viewers': [
                  {'id': 'viewer.a', 'managed': true, 'enabled': true},
                  {'id': 'viewer.custom', 'managed': false, 'enabled': true},
                ],
              },
              {
                'id': 'extension-bar',
                'managed': false,
                'enabled': true,
                'type': 'extension',
                'value': '.bar',
                'rules': <Object?>[],
                'viewers': [
                  {'id': 'viewer.c', 'managed': false, 'enabled': true},
                ],
              },
            ],
          },
          {
            'id': 'team-rules',
            'name': '团队规则',
            'builtIn': false,
            'enabled': true,
            'rules': <Object?>[],
          },
        ],
      }, defaultGroup: defaultGroup);

      // 内置组丢弃；用户规则（.bar + .pdf 上的自定义 Viewer）迁移到"我的规则"，
      // 排在用户组与 default 之前。
      expect(restored.groups.map((group) => group.id), [
        ViewerAssociationConfig.migratedGroupId,
        'team-rules',
        ViewerAssociationConfig.defaultGroupId,
      ]);
      expect(restored.needsMigration, isTrue);
      final migrated = restored.group(ViewerAssociationConfig.migratedGroupId);
      expect(migrated.name, '我的规则');
      final barRule = migrated.rules.singleWhere((rule) => rule.value == '.bar');
      expect(barRule.viewers.single.id, 'viewer.c');
      final pdfRule = migrated.rules.singleWhere((rule) => rule.value == '.pdf');
      expect(pdfRule.viewers.map((viewer) => viewer.id), ['viewer.custom']);
      expect(restored.rule('extension-bar'), isNotNull);
      expect(restored.toJson()['schemaVersion'], 3);
    });

    test('preset group rejects all mutations but allows reordering', () {
      final config = ViewerAssociationConfig.empty(
        defaultGroup: ViewerAssociationConfig.parsePresetGroup({
          'schemaVersion': 3,
          'id': 'default',
          'name': '默认',
          'rules': [
            _jsonRule('ext-md', 'extension', '.md', ['viewer.a']),
          ],
        }),
      );
      final custom = userGroup('custom-x');
      config.addGroup(custom);

      expect(
        () => config.addRule(
          ViewerAssociationConfig.defaultGroupId,
          ViewerRule(
            id: 'new-rule',
            managed: false,
            enabled: true,
            type: ViewerRuleType.extension,
            value: '.txt',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => config.updateRule(
          ViewerRule(
            id: 'ext-md',
            managed: false,
            enabled: false,
            type: ViewerRuleType.extension,
            value: '.md',
          ),
        ),
        throwsArgumentError,
      );
      expect(() => config.removeRule('ext-md'), throwsArgumentError);
      expect(
        () => config.moveRuleBefore('ext-md', 'new-rule'),
        throwsArgumentError,
      );
      expect(
        () => config.removeGroup(ViewerAssociationConfig.defaultGroupId),
        throwsArgumentError,
      );
      expect(
        () => config.updateGroup(
          ViewerRuleGroup(
            id: ViewerAssociationConfig.defaultGroupId,
            name: '默认',
            preset: false,
            enabled: true,
          ),
        ),
        throwsArgumentError,
      );

      // 排序允许：default 可与其他组交换位置，顺序持久化。
      config.reorderGroup(1, 0);
      expect(config.groups.map((group) => group.id), [
        'custom-x',
        ViewerAssociationConfig.defaultGroupId,
      ]);
    });

    test('invalid drag targets do not remove the source rule', () {
      final config = ViewerAssociationConfig.empty();
      final custom = userGroup('user-x');
      config.addGroup(custom);
      final parent = ViewerRule(
        id: 'parent',
        managed: false,
        enabled: true,
        type: ViewerRuleType.extension,
        value: '.bar',
        rules: [
          ViewerRule(
            id: 'child',
            managed: false,
            enabled: true,
            type: ViewerRuleType.mimeType,
            value: 'application/x-bar',
          ),
        ],
      );
      config.addRule(custom.id, parent);

      expect(
        () => config.moveRuleBefore('parent', 'missing'),
        throwsArgumentError,
      );
      expect(() => config.moveRuleInto('parent', 'child'), throwsArgumentError);
      expect(
        () => config.moveRuleToGroup('parent', 'missing'),
        throwsArgumentError,
      );
      expect(config.rule('parent').rules.single.id, 'child');
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
    late File defaultConfigFile;
    late QuickViewService service;

    QuickViewService createService({
      required String associationFile,
      required File? defaultConfigFile,
      String? Function(String)? mimeTypeResolver = _noMime,
      ViewerProcessStarter? processStarter,
      ViewerWindowController? windowController,
    }) {
      return QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(filePath: associationFile),
        defaultConfigFile: defaultConfigFile,
        mimeTypeResolver: mimeTypeResolver,
        processStarter: processStarter,
        windowController: windowController,
      );
    }

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
      defaultConfigFile = _writeDefaultConfig(pluginRoot, [
        _jsonRule('name-readme', 'fileName', 'readme.md', [
          'viewer.a',
          'viewer.b',
        ]),
        _jsonRule('ext-md', 'extension', '.md', ['viewer.b', 'viewer.c']),
        _jsonRule('mime-image', 'mimeType', 'image/*', ['viewer.image']),
        _jsonRule('ext-tar-gz', 'extension', '.tar.gz', ['viewer.archive-long']),
        _jsonRule('ext-gz', 'extension', '.gz', ['viewer.archive-short']),
      ]);
      service = createService(
        associationFile: p.join(temp.path, 'associations.json'),
        defaultConfigFile: defaultConfigFile,
      );
    });

    tearDown(() {
      service.dispose();
      temp.deleteSync(recursive: true);
    });

    ViewerRuleGroup firstUserGroup() {
      final group = service.addRuleGroup(name: '我的规则组');
      return group;
    }

    test('merges file name and extension candidates without duplicates', () {
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

    test('resolves matching child rules before parent viewers', () {
      final group = service.addRuleGroup(name: 'Nested');
      final parent = service.addRule(
        groupId: group.id,
        type: ViewerRuleType.extension,
        value: '.bar',
        viewerIds: ['viewer.a', 'viewer.b'],
      );
      service.addRule(
        groupId: group.id,
        parentRuleId: parent.id,
        type: ViewerRuleType.mimeType,
        value: 'application/x-bar-v1',
        viewerIds: ['viewer.c'],
      );
      service.reorderRuleGroups(service.ruleGroups.length - 1, 0);

      expect(
        service
            .resolve(r'C:\data\sample.bar', mimeType: 'application/x-bar-v1')
            .map((plugin) => plugin.manifest.id),
        ['viewer.c', 'viewer.a', 'viewer.b'],
      );
      expect(
        service
            .resolve(
              r'C:\data\sample.bar',
              mimeType: 'application/octet-stream',
            )
            .map((plugin) => plugin.manifest.id),
        ['viewer.a', 'viewer.b'],
      );
    });

    test('preset default rules are completely read-only', () {
      final group = firstUserGroup();

      expect(() => service.setRuleEnabled('ext-md', false), throwsArgumentError);
      expect(
        () => service.moveRuleToGroup('ext-md', group.id),
        throwsArgumentError,
      );
      expect(
        () => service.addViewerToRule('ext-md', 'viewer.a'),
        throwsArgumentError,
      );
      expect(
        () => service.setRuleViewerEnabled('ext-md', 'viewer.b', false),
        throwsArgumentError,
      );
      expect(
        () => service.reorderRuleViewers('ext-md', 0, 1),
        throwsArgumentError,
      );
      expect(
        () => service.removeViewerFromRule('ext-md', 'viewer.b'),
        throwsArgumentError,
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
      final group = firstUserGroup();
      final rule = service.addRule(
        groupId: group.id,
        type: ViewerRuleType.path,
        value: r'C:\docs\**\*.md',
        pathMode: ViewerPathMatchMode.glob,
        viewerIds: ['viewer.c'],
      );
      service.reorderRuleGroups(service.ruleGroups.length - 1, 0);

      final candidates = service.resolveCandidates(r'C:\docs\README.md');

      expect(candidates.map((candidate) => candidate.plugin.manifest.id), [
        'viewer.c',
        'viewer.a',
        'viewer.b',
      ]);
      expect(candidates.first.matchKind, ViewerMatchKind.pathRule);
      expect(candidates.first.ruleId, rule.id);

      service.setRuleEnabled(rule.id, false);
      expect(
        service
            .resolve(r'C:\docs\README.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.a', 'viewer.b', 'viewer.c'],
      );
    });

    test('ordered custom groups change resolver priority and persist', () {
      final group = service.addRuleGroup(name: '优先 Markdown');
      service.addRule(
        groupId: group.id,
        type: ViewerRuleType.extension,
        value: '.md',
        viewerIds: ['viewer.c'],
      );

      final oldIndex = service.ruleGroups.indexWhere(
        (item) => item.id == group.id,
      );
      service.reorderRuleGroups(oldIndex, 0);

      final candidates = service.resolveCandidates(r'C:\docs\README.md');
      expect(candidates.map((candidate) => candidate.plugin.manifest.id), [
        'viewer.c',
        'viewer.a',
        'viewer.b',
      ]);
      expect(candidates.first.groupId, group.id);

      final saved =
          jsonDecode(
                File(p.join(temp.path, 'associations.json')).readAsStringSync(),
              )
              as Map;
      final savedGroups = saved['groups']! as List;
      expect((savedGroups.first as Map)['id'], group.id);
      // 用户配置只记 default 引用（preset stub），不存默认规则。
      expect(savedGroups.map((entry) => (entry as Map)['id']), [
        group.id,
        'default',
      ]);
      expect((savedGroups.last as Map)['preset'], isTrue);
      expect(savedGroups.last, isNot(contains('rules')));
      final ids = savedGroups.map((entry) => (entry as Map)['id']).toSet();
      expect(ids, isNot(contains('ext-md')));
    });

    test('matches exact paths case-insensitively', () {
      final group = firstUserGroup();
      service.addRule(
        groupId: group.id,
        type: ViewerRuleType.path,
        value: r'C:\Docs\README.md',
        pathMode: ViewerPathMatchMode.exact,
        viewerIds: ['viewer.c'],
      );
      service.reorderRuleGroups(service.ruleGroups.length - 1, 0);

      expect(
        service.resolveCandidates(r'c:\docs\readme.md').first.matchKind,
        ViewerMatchKind.pathRule,
      );
    });

    test('migrates v1 associations away and keeps static defaults stable', () {
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
      final migratingService = createService(
        associationFile: configFile.path,
        defaultConfigFile: defaultConfigFile,
      );
      addTearDown(migratingService.dispose);

      // v1 内置关联被丢弃，默认规则来自 plugins 静态配置。
      expect(
        migratingService
            .resolve(r'C:\docs\guide.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.b', 'viewer.c'],
      );
      final migratedJson = jsonDecode(configFile.readAsStringSync()) as Map;
      expect(migratedJson['schemaVersion'], 3);
      final groups = migratedJson['groups']! as List;
      expect((groups.first as Map)['id'], 'default');
      expect((groups.first as Map)['preset'], isTrue);
      expect(groups.first, isNot(contains('rules')));
      expect(groups.first, isNot(contains('associations')));

      // 静态默认规则不随插件变化：reload 不追加新 Viewer。
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
        ['viewer.b', 'viewer.c'],
      );
    });

    test('migrates v2 user rules into 我的规则 before the default group', () {
      final configFile = File(p.join(temp.path, 'v2-associations.json'))
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': 2,
            'groups': [
              {
                'id': 'builtin-extension',
                'name': '扩展名',
                'builtIn': true,
                'enabled': true,
                'rules': [
                  {
                    'id': 'extension-bar',
                    'managed': false,
                    'enabled': true,
                    'type': 'extension',
                    'value': '.bar',
                    'rules': <Object?>[],
                    'viewers': [
                      {'id': 'viewer.c', 'managed': false, 'enabled': true},
                    ],
                  },
                ],
              },
            ],
          }),
        );
      final migratingService = createService(
        associationFile: configFile.path,
        defaultConfigFile: defaultConfigFile,
      );
      addTearDown(migratingService.dispose);

      expect(migratingService.ruleGroups.map((group) => group.id), [
        ViewerAssociationConfig.migratedGroupId,
        ViewerAssociationConfig.defaultGroupId,
      ]);
      expect(
        migratingService.ruleGroup('migrated-rules').rules.single.value,
        '.bar',
      );
      final saved = jsonDecode(configFile.readAsStringSync()) as Map;
      expect(saved['schemaVersion'], 3);
    });

    test('does not overwrite an unsupported future config', () {
      final configFile = File(p.join(temp.path, 'future-associations.json'));
      const original = '{"schemaVersion":99,"futureSetting":true}';
      configFile.writeAsStringSync(original);
      final futureService = createService(
        associationFile: configFile.path,
        defaultConfigFile: defaultConfigFile,
      );
      addTearDown(futureService.dispose);

      futureService.addRuleGroup(name: '不可保存组');

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
      final resolvingService = createService(
        associationFile: p.join(temp.path, 'mime-associations.json'),
        defaultConfigFile: defaultConfigFile,
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

    test('rejects a viewer not known to a user rule', () {
      final group = firstUserGroup();
      expect(
        () => service.addRule(
          groupId: group.id,
          type: ViewerRuleType.extension,
          value: '.md',
          viewerIds: ['viewer.nope'],
        ),
        throwsArgumentError,
      );
    });

    test('discovers the plugins default config when none is injected', () {
      final discovered = createService(
        associationFile: p.join(temp.path, 'discovered.json'),
        defaultConfigFile: null,
      );
      addTearDown(discovered.dispose);

      final preset = discovered.ruleGroups.firstWhere((group) => group.preset);
      expect(preset.id, ViewerAssociationConfig.defaultGroupId);
      // 仓库根目录的 plugins/quick-view.default.json 应被自动发现。
      expect(preset.rules, isNotEmpty);
    });

    test('user rule viewer edits persist order and disabled state', () {
      final group = firstUserGroup();
      final rule = service.addRule(
        groupId: group.id,
        type: ViewerRuleType.extension,
        value: '.md',
        viewerIds: ['viewer.c', 'viewer.b'],
      );
      service.reorderRuleGroups(service.ruleGroups.length - 1, 0);

      expect(
        service
            .resolve(r'C:\docs\guide.md')
            .map((plugin) => plugin.manifest.id),
        ['viewer.c', 'viewer.b'],
      );

      service.setRuleViewerEnabled(rule.id, 'viewer.c', false);
      service.addViewerToRule(rule.id, 'viewer.a');
      expect(
        service.rule(rule.id).viewers.map((viewer) => viewer.id),
        ['viewer.c', 'viewer.b', 'viewer.a'],
      );
      final saved =
          jsonDecode(
                File(p.join(temp.path, 'associations.json')).readAsStringSync(),
              )
              as Map;
      final groups = saved['groups']! as List;
      final customGroup = groups.cast<Map>().singleWhere(
        (candidate) => candidate['id'] == group.id,
      );
      final savedRule = (customGroup['rules']! as List).cast<Map>().single;
      expect(
        (savedRule['viewers'] as List).cast<Map>().map(
          (viewer) => viewer['id'],
        ),
        ['viewer.c', 'viewer.b', 'viewer.a'],
      );
      expect(
        ((savedRule['viewers'] as List).cast<Map>().first)['enabled'],
        isFalse,
      );
    });

    test('preserves a temporarily missing viewer ID on user edits', () {
      final configFile = File(p.join(temp.path, 'missing-viewer.json'))
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': 3,
            'groups': [
              {'id': 'default', 'preset': true},
              {
                'id': 'custom-md',
                'name': '自定义 Markdown',
                'enabled': true,
                'rules': [
                  {
                    'id': 'ext-md-user',
                    'enabled': true,
                    'type': 'extension',
                    'value': '.md',
                    'rules': <Object?>[],
                    'viewers': [
                      {'id': 'viewer.b', 'enabled': true},
                      {'id': 'viewer.missing', 'enabled': true},
                    ],
                  },
                ],
              },
            ],
          }),
        );
      final preservingService = createService(
        associationFile: configFile.path,
        defaultConfigFile: defaultConfigFile,
      );
      addTearDown(preservingService.dispose);

      preservingService.addViewerToRule('ext-md-user', 'viewer.c');

      final saved = jsonDecode(configFile.readAsStringSync()) as Map;
      final groups = saved['groups']! as List;
      final customGroup = groups.cast<Map>().singleWhere(
        (group) => group['id'] == 'custom-md',
      );
      final markdownRule = (customGroup['rules']! as List)
          .cast<Map>()
          .singleWhere((rule) => rule['id'] == 'ext-md-user');
      expect(
        (markdownRule['viewers'] as List).cast<Map>().map(
          (viewer) => viewer['id'],
        ),
        ['viewer.b', 'viewer.missing', 'viewer.c'],
      );
    });

    test(
      'keeps a spaced path in one argument and falls back on start failure',
      () async {
        final file = File(p.join(temp.path, 'report with spaces.md'))
          ..writeAsStringSync('test');
        final starts = <(String, List<String>, String)>[];
        final windows = _FakeViewerWindowController();
        final launchingService = createService(
          associationFile: p.join(temp.path, 'launch-associations.json'),
          defaultConfigFile: defaultConfigFile,
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
      final launchingService = createService(
        associationFile: p.join(temp.path, 'replace-associations.json'),
        defaultConfigFile: defaultConfigFile,
        processStarter: (executable, arguments, workingDirectory) async {
          starts.add(arguments);
          return windows.createProcess();
        },
        windowController: windows,
      );
      addTearDown(launchingService.dispose);

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
      final launchingService = createService(
        associationFile: p.join(temp.path, 'exit-associations.json'),
        defaultConfigFile: defaultConfigFile,
        processStarter: (executable, arguments, workingDirectory) async =>
            windows.createProcess(),
        windowController: windows,
      );
      addTearDown(launchingService.dispose);

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
        final launchingService = createService(
          associationFile: p.join(temp.path, 'detach-associations.json'),
          defaultConfigFile: defaultConfigFile,
          processStarter: (executable, arguments, workingDirectory) async =>
              windows.createProcess(),
          windowController: windows,
        );
        addTearDown(launchingService.dispose);

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

  group('directory openers', () {
    late Directory temp;
    late Directory pluginRoot;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('inf_dir_openers_');
      pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
      _writeOpenerPlugin(
        pluginRoot,
        id: 'test.opener',
        name: 'Test Opener',
        appPaths: ['Code.exe'],
      );
      _writeOpenerPlugin(
        pluginRoot,
        id: 'test.missing',
        name: 'Missing Opener',
        appPaths: ['NotInstalled.exe'],
      );
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    QuickViewService createService(
      List<(String, List<String>, String)> starts, {
      bool failStart = false,
    }) {
      return QuickViewService(
        pluginRoots: [pluginRoot],
        associationStore: ViewerAssociationStore(
          filePath: p.join(temp.path, 'associations.json'),
        ),
        defaultConfigFile: _writeDefaultConfig(pluginRoot, []),
        mimeTypeResolver: (_) => null,
        directoryOpenerResolver: DirectoryOpenerResolver(
          environment: const {},
          appPathsLookup: (name) =>
              name == 'Code.exe' ? r'C:\fake\code.cmd' : null,
          pathDirectories: () => const [],
          fileExists: (path) => path == r'C:\fake\code.cmd',
        ),
        directoryOpenerStarter: (executable, arguments, workingDirectory) {
          if (failStart) {
            throw const ProcessException('opener', [], 'failed');
          }
          starts.add((executable, arguments, workingDirectory));
          return Future.value(
            ViewerProcessHandle(
              processId: 1,
              exitCode: Future.value(-1),
              terminate: () => false,
            ),
          );
        },
      );
    }

    test('reload collects resolved openers and reports unresolved ones', () {
      final service = createService(const []);
      addTearDown(service.dispose);

      expect(
        service.directoryOpeners.map((opener) => opener.manifest.id),
        ['test.opener'],
      );
      expect(
        service.directoryOpeners.single.executablePath,
        r'C:\fake\code.cmd',
      );
      expect(
        service.issues.map((issue) => issue.message),
        contains('未找到可执行程序：test.missing'),
      );
    });

    test(
      'openDirectoryWith launches detached with the directory path',
      () async {
        final starts = <(String, List<String>, String)>[];
        final service = createService(starts);
        addTearDown(service.dispose);
        final directory = Directory(p.join(temp.path, 'project'))
          ..createSync();

        final result = await service.openDirectoryWith(
          'test.opener',
          directory.path,
        );

        expect(result.started, isTrue);
        expect(result.message, '已使用 Test Opener 打开');
        expect(starts.single.$1, r'C:\fake\code.cmd');
        expect(starts.single.$2, [p.absolute(directory.path)]);
        expect(starts.single.$3, p.absolute(directory.path));
      },
    );

    test('openDirectoryWith substitutes the arguments template', () async {
      _writeOpenerPlugin(
        pluginRoot,
        id: 'test.opener.args',
        name: 'Argument Opener',
        appPaths: ['Code.exe'],
        arguments: ['-d', '{dir}'],
      );
      final starts = <(String, List<String>, String)>[];
      final service = createService(starts);
      addTearDown(service.dispose);
      final directory = Directory(p.join(temp.path, 'project'))
        ..createSync();

      final result = await service.openDirectoryWith(
        'test.opener.args',
        directory.path,
      );

      expect(result.started, isTrue);
      expect(starts.single.$1, r'C:\fake\code.cmd');
      expect(starts.single.$2, ['-d', p.absolute(directory.path)]);
      expect(starts.single.$3, p.absolute(directory.path));
    });

    test('openDirectoryWith fails for a missing directory', () async {
      final service = createService(const []);
      addTearDown(service.dispose);

      final result = await service.openDirectoryWith(
        'test.opener',
        p.join(temp.path, 'nope'),
      );

      expect(result.started, isFalse);
    });

    test('openDirectoryWith reports starter failures', () async {
      final service = createService(const [], failStart: true);
      addTearDown(service.dispose);
      final directory = Directory(p.join(temp.path, 'project'))..createSync();

      final result = await service.openDirectoryWith(
        'test.opener',
        directory.path,
      );

      expect(result.started, isFalse);
      expect(result.message, startsWith('启动失败'));
    });
  });
}

String? _noMime(String path) => null;

Map<String, Object?> _jsonRule(
  String id,
  String type,
  String value,
  List<String> viewerIds, {
  List<Map<String, Object?>>? rules,
}) => {
  'id': id,
  'enabled': true,
  'type': type,
  'value': value,
  'rules': rules ?? const <Object?>[],
  'viewers': [
    for (final viewerId in viewerIds) {'id': viewerId, 'enabled': true},
  ],
};

File _writeDefaultConfig(Directory root, List<Map<String, Object?>> rules) {
  final file = File(p.join(root.path, 'quick-view.default.json'));
  file.writeAsStringSync(
    jsonEncode({
      'schemaVersion': 3,
      'id': 'default',
      'name': '默认',
      'rules': rules,
    }),
  );
  return file;
}

void _writeOpenerPlugin(
  Directory root, {
  required String id,
  required String name,
  required List<String> appPaths,
  List<String> arguments = const [],
}) {
  final directory = Directory(p.join(root.path, id))..createSync();
  File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
    jsonEncode({
      'manifestVersion': 1,
      'id': id,
      'name': name,
      'version': '1.0.0',
      'capabilities': {
        'openDirectory': {
          'appPaths': appPaths,
          if (arguments.isNotEmpty) 'arguments': arguments,
        },
      },
    }),
  );
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
