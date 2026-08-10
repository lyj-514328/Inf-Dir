import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/mime_type_service.dart';
import 'plugin_manifest.dart';
import 'viewer_association_config.dart';

typedef ViewerProcessStarter =
    Future<void> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

class PluginDiscoveryIssue {
  const PluginDiscoveryIssue(this.path, this.message);

  final String path;
  final String message;
}

class QuickViewOpenResult {
  const QuickViewOpenResult._({
    required this.started,
    required this.message,
    this.plugin,
  });

  factory QuickViewOpenResult.success(ViewerPlugin plugin) =>
      QuickViewOpenResult._(
        started: true,
        plugin: plugin,
        message: '已使用 ${plugin.manifest.name} 打开',
      );

  factory QuickViewOpenResult.failure(String message) =>
      QuickViewOpenResult._(started: false, message: message);

  final bool started;
  final String message;
  final ViewerPlugin? plugin;
}

class QuickViewService extends ChangeNotifier {
  QuickViewService({
    List<Directory>? pluginRoots,
    ViewerAssociationStore? associationStore,
    String? Function(String filePath)? mimeTypeResolver,
    ViewerProcessStarter? processStarter,
  }) : _pluginRoots = pluginRoots ?? defaultPluginRoots(),
       _associationStore = associationStore ?? ViewerAssociationStore() {
    _mimeTypeResolver = mimeTypeResolver ?? MimeTypeService.forPath;
    _processStarter = processStarter ?? _startProcess;
    reload(notify: false);
  }

  final List<Directory> _pluginRoots;
  final ViewerAssociationStore _associationStore;
  late final String? Function(String filePath) _mimeTypeResolver;
  late final ViewerProcessStarter _processStarter;
  final Map<String, ViewerPlugin> _plugins = {};
  final List<PluginDiscoveryIssue> _issues = [];
  late ViewerAssociationConfig _associations;

  List<ViewerPlugin> get plugins {
    final result = _plugins.values.toList()..sort(_comparePlugins);
    return List.unmodifiable(result);
  }

  List<PluginDiscoveryIssue> get issues => List.unmodifiable(_issues);

  static List<Directory> defaultPluginRoots() {
    final overridePath = Platform.environment['INF_DIR_PLUGIN_DIR'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final installedPlugins = p.join(
      p.dirname(Platform.resolvedExecutable),
      'plugins',
    );
    final developmentPlugins = p.join(
      Directory.current.path,
      'plugins',
      'dist',
    );
    final paths = <String>[
      ?overridePath?.isNotEmpty == true ? overridePath : null,
      Directory(installedPlugins).existsSync()
          ? installedPlugins
          : developmentPlugins,
      ?localAppData?.isNotEmpty == true
          ? p.join(localAppData!, 'Inf-Dir', 'plugins')
          : null,
    ];
    final seen = <String>{};
    return [
      for (final path in paths)
        if (seen.add(p.normalize(path).toLowerCase())) Directory(path),
    ];
  }

  void reload({bool notify = true}) {
    _plugins.clear();
    _issues.clear();

    for (final root in _pluginRoots) {
      if (!root.existsSync()) continue;
      final packageDirectories =
          root.listSync(followLinks: false).whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final packageDirectory in packageDirectories) {
        final manifestFile = File(p.join(packageDirectory.path, 'plugin.json'));
        if (!manifestFile.existsSync()) continue;
        try {
          if (!PluginManifest.declaresQuickView(manifestFile)) continue;
          final manifest = PluginManifest.read(manifestFile);
          if (_plugins.containsKey(manifest.id)) {
            _issues.add(
              PluginDiscoveryIssue(
                manifestFile.path,
                '插件 ID 重复：${manifest.id}',
              ),
            );
            continue;
          }
          final plugin = ViewerPlugin(
            manifest: manifest,
            directoryPath: packageDirectory.path,
          );
          _plugins[manifest.id] = plugin;
          if (!plugin.isAvailable) {
            _issues.add(
              PluginDiscoveryIssue(plugin.executablePath, '插件入口程序不存在'),
            );
          }
        } catch (error) {
          _issues.add(PluginDiscoveryIssue(manifestFile.path, '$error'));
        }
      }
    }

    try {
      _associations = _associationStore.load();
    } catch (error) {
      _associations = ViewerAssociationConfig.empty();
      _issues.add(
        PluginDiscoveryIssue(_associationStore.filePath, '关联配置加载失败：$error'),
      );
    }
    if (notify) notifyListeners();
  }

  List<String> associationKeys(ViewerAssociationKind kind) {
    final result = <String>{..._associations.keysFor(kind)};
    for (final plugin in _plugins.values) {
      result.addAll(plugin.manifest.quickView.valuesFor(kind));
    }
    final sorted = result.toList()..sort();
    return sorted;
  }

  bool hasOverride(ViewerAssociationKind kind, String key) =>
      _associations.hasOverride(kind, key);

  List<ViewerPlugin> availablePluginsFor(
    ViewerAssociationKind kind,
    String rawKey,
  ) {
    final key = kind.normalize(rawKey);
    final result =
        _plugins.values
            .where(
              (plugin) =>
                  plugin.isAvailable &&
                  plugin.manifest.quickView.supports(kind, key),
            )
            .toList()
          ..sort(_comparePlugins);
    return result;
  }

  List<ViewerPlugin> candidatesForAssociation(
    ViewerAssociationKind kind,
    String rawKey,
  ) {
    final key = kind.normalize(rawKey);
    final available = availablePluginsFor(kind, key);
    final configuredIds = _associations.idsFor(kind, key);
    if (configuredIds == null) return available;

    final byId = {for (final plugin in available) plugin.manifest.id: plugin};
    return [for (final id in configuredIds) ?byId[id]];
  }

  void setCandidates(
    ViewerAssociationKind kind,
    String rawKey,
    Iterable<String> pluginIds,
  ) {
    final key = kind.normalize(rawKey);
    final ids = pluginIds.map((id) => id.toLowerCase()).toList();
    final validIds = {
      for (final plugin in availablePluginsFor(kind, key)) plugin.manifest.id,
    };
    final invalid = ids.where((id) => !validIds.contains(id)).toList();
    if (invalid.isNotEmpty) {
      throw ArgumentError('插件未声明支持 $key：${invalid.join(', ')}');
    }
    _associations.set(kind, key, ids);
    _saveAndNotify();
  }

  void disableAssociation(ViewerAssociationKind kind, String rawKey) {
    _associations.set(kind, rawKey, const []);
    _saveAndNotify();
  }

  void resetAssociation(ViewerAssociationKind kind, String rawKey) {
    _associations.reset(kind, rawKey);
    _saveAndNotify();
  }

  List<ViewerPlugin> resolve(String filePath, {String? mimeType}) {
    final candidateGroups = <List<ViewerPlugin>>[];
    final fileName = p.basename(filePath).toLowerCase();
    final extension = p.extension(fileName).toLowerCase();

    if (fileName.isNotEmpty) {
      candidateGroups.add(
        candidatesForAssociation(ViewerAssociationKind.fileName, fileName),
      );
    }
    if (extension.isNotEmpty) {
      candidateGroups.add(
        candidatesForAssociation(ViewerAssociationKind.extension, extension),
      );
    }
    final resolvedMime = mimeType ?? _mimeTypeResolver(filePath);
    if (resolvedMime != null && resolvedMime.trim().isNotEmpty) {
      try {
        final mime = ViewerAssociationKind.mimeType.normalize(
          resolvedMime.split(';').first,
        );
        candidateGroups.add(
          candidatesForAssociation(ViewerAssociationKind.mimeType, mime),
        );
        final slash = mime.indexOf('/');
        candidateGroups.add(
          candidatesForAssociation(
            ViewerAssociationKind.mimeType,
            '${mime.substring(0, slash)}/*',
          ),
        );
      } on FormatException {
        debugPrint('[QuickView] ignored invalid MIME: $resolvedMime');
      }
    }

    final seen = <String>{};
    return [
      for (final group in candidateGroups)
        for (final plugin in group)
          if (seen.add(plugin.manifest.id)) plugin,
    ];
  }

  Future<QuickViewOpenResult> open(String filePath, {String? mimeType}) async {
    FileSystemEntityType type;
    try {
      type = FileSystemEntity.typeSync(filePath, followLinks: true);
    } catch (error) {
      return QuickViewOpenResult.failure('无法访问文件：$error');
    }
    if (type == FileSystemEntityType.directory) {
      return QuickViewOpenResult.failure('文件夹不能使用快速查看');
    }
    if (type == FileSystemEntityType.notFound) {
      return QuickViewOpenResult.failure('文件不存在或当前不可访问');
    }

    final candidates = resolve(filePath, mimeType: mimeType);
    if (candidates.isEmpty) {
      final extension = p.extension(filePath).toLowerCase();
      return QuickViewOpenResult.failure(
        extension.isEmpty ? '没有适用于此文件的查看器' : '没有关联 $extension 查看器',
      );
    }

    Object? lastError;
    for (final plugin in candidates) {
      try {
        await _processStarter(plugin.executablePath, [
          p.absolute(filePath),
        ], plugin.directoryPath);
        return QuickViewOpenResult.success(plugin);
      } catch (error) {
        lastError = error;
        debugPrint('[QuickView] ${plugin.manifest.id} launch failed: $error');
      }
    }
    return QuickViewOpenResult.failure('查看器启动失败：$lastError');
  }

  void _saveAndNotify() {
    try {
      _associationStore.save(_associations);
    } catch (error) {
      _issues.add(
        PluginDiscoveryIssue(_associationStore.filePath, '关联配置保存失败：$error'),
      );
    }
    notifyListeners();
  }

  static int _comparePlugins(ViewerPlugin a, ViewerPlugin b) {
    final byName = a.manifest.name.compareTo(b.manifest.name);
    return byName != 0 ? byName : a.manifest.id.compareTo(b.manifest.id);
  }

  static Future<void> _startProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
  }
}
