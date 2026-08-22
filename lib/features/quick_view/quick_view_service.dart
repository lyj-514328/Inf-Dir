import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/mime_type_service.dart';
import 'directory_opener_resolver.dart';
import 'plugin_manifest.dart';
import 'viewer_association_config.dart';
import 'viewer_file_facts.dart';
import 'viewer_rule.dart';
import 'viewer_window_controller.dart';

File? _viewerWindowLogFile;

void _logViewerWindow(String message) {
  debugPrint(message);
  try {
    final file = _viewerWindowLogFile ??= _resolveViewerWindowLogFile();
    if (file.existsSync() && file.lengthSync() > 2 * 1024 * 1024) {
      file.writeAsStringSync('');
    }
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $message\r\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (error) {
    debugPrint('[QuickViewWindow] failed to write diagnostic log: $error');
  }
}

File _resolveViewerWindowLogFile() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final directory = Directory(
    localAppData == null || localAppData.isEmpty
        ? p.join(Directory.systemTemp.path, 'Inf-Dir')
        : p.join(localAppData, 'Inf-Dir'),
  )..createSync(recursive: true);
  return File(p.join(directory.path, 'quick_view.log'));
}

typedef ViewerProcessStarter =
    Future<ViewerProcessHandle> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

class ViewerProcessHandle {
  const ViewerProcessHandle({
    required this.processId,
    required this.exitCode,
    required this.terminate,
  });

  final int processId;
  final Future<int> exitCode;
  final bool Function() terminate;
}

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

class DirectoryOpenerPlugin {
  const DirectoryOpenerPlugin({
    required this.manifest,
    required this.executablePath,
  });

  final PluginManifest manifest;
  final String executablePath;
}

class DirectoryOpenResult {
  const DirectoryOpenResult._({required this.started, required this.message});

  factory DirectoryOpenResult.success(DirectoryOpenerPlugin opener) =>
      DirectoryOpenResult._(
        started: true,
        message: '已使用 ${opener.manifest.name} 打开',
      );

  factory DirectoryOpenResult.failure(String message) =>
      DirectoryOpenResult._(started: false, message: message);

  final bool started;
  final String message;
}

enum ViewerMatchKind { pathRule, fileName, suffix, mimeExact, mimeWildcard }

class ViewerResolutionCandidate {
  const ViewerResolutionCandidate({
    required this.plugin,
    required this.groupId,
    required this.matchKind,
    required this.matchedValue,
    this.ruleId,
  });

  final ViewerPlugin plugin;
  final String groupId;
  final ViewerMatchKind matchKind;
  final String matchedValue;
  final String? ruleId;
}

class QuickViewService extends ChangeNotifier {
  QuickViewService({
    List<Directory>? pluginRoots,
    ViewerAssociationStore? associationStore,
    File? defaultConfigFile,
    String? Function(String filePath)? mimeTypeResolver,
    ViewerProcessStarter? processStarter,
    DirectoryOpenerResolver? directoryOpenerResolver,
    ViewerProcessStarter? directoryOpenerStarter,
    ViewerWindowController? windowController,
    Duration windowDiscoveryTimeout = const Duration(seconds: 12),
    Duration processExitTimeout = const Duration(milliseconds: 250),
  }) : _pluginRoots = pluginRoots ?? defaultPluginRoots(),
       _associationStore = associationStore ?? ViewerAssociationStore(),
       _defaultConfigFile =
           defaultConfigFile ?? QuickViewService.discoverDefaultConfigFile(),
       _directoryOpenerResolver =
           directoryOpenerResolver ?? DirectoryOpenerResolver(),
       _windowController =
           windowController ??
           Win32ViewerWindowController(logger: _logViewerWindow),
       _windowDiscoveryTimeout = windowDiscoveryTimeout,
       _processExitTimeout = processExitTimeout {
    _mimeTypeResolver = mimeTypeResolver ?? MimeTypeService.forPath;
    _processStarter = processStarter ?? _startProcess;
    _directoryOpenerStarter = directoryOpenerStarter ?? _startDetachedProcess;
    reload(notify: false);
  }

  final List<Directory> _pluginRoots;
  final ViewerAssociationStore _associationStore;
  final File? _defaultConfigFile;
  final DirectoryOpenerResolver _directoryOpenerResolver;
  final ViewerWindowController _windowController;
  final Duration _windowDiscoveryTimeout;
  final Duration _processExitTimeout;
  late final String? Function(String filePath) _mimeTypeResolver;
  late final ViewerProcessStarter _processStarter;
  late final ViewerProcessStarter _directoryOpenerStarter;
  final Map<String, ViewerPlugin> _plugins = {};
  final Map<String, DirectoryOpenerPlugin> _directoryOpeners = {};
  final List<PluginDiscoveryIssue> _issues = [];
  late ViewerAssociationConfig _associations;
  bool _associationStoreWritable = true;
  _AttachedViewer? _attachedViewer;
  Future<void> _operationQueue = Future<void>.value();
  Future<void>? _shutdownFuture;
  bool _shuttingDown = false;
  bool _disposed = false;

  List<ViewerPlugin> get plugins {
    final result = _plugins.values.toList()..sort(_comparePlugins);
    return List.unmodifiable(result);
  }

  List<DirectoryOpenerPlugin> get directoryOpeners {
    final result = _directoryOpeners.values.toList()
      ..sort((a, b) {
        final byName = a.manifest.name.compareTo(b.manifest.name);
        return byName != 0 ? byName : a.manifest.id.compareTo(b.manifest.id);
      });
    return List.unmodifiable(result);
  }

  /// 以分离进程启动目录打开器，传入目录绝对路径；不纳入 attached 管理。
  Future<DirectoryOpenResult> openDirectoryWith(
    String pluginId,
    String directoryPath,
  ) async {
    final opener = _directoryOpeners[pluginId];
    if (opener == null) {
      return DirectoryOpenResult.failure('未找到目录打开器：$pluginId');
    }
    final absolute = p.absolute(directoryPath);
    if (FileSystemEntity.typeSync(absolute) !=
        FileSystemEntityType.directory) {
      return DirectoryOpenResult.failure('目录不存在：$absolute');
    }
    try {
      final template = opener.manifest.openDirectory?.arguments ?? const [];
      final arguments = template.isEmpty
          ? [absolute]
          : [
              for (final argument in template)
                argument == '{dir}' ? absolute : argument,
            ];
      await _directoryOpenerStarter(opener.executablePath, arguments, absolute);
    } on Object catch (error) {
      return DirectoryOpenResult.failure('启动失败：$error');
    }
    return DirectoryOpenResult.success(opener);
  }

  List<PluginDiscoveryIssue> get issues => List.unmodifiable(_issues);

  bool get hasAttachedViewer => _attachedViewer != null;

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
    _directoryOpeners.clear();
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
          if (!PluginManifest.declaresSupportedCapability(manifestFile)) {
            continue;
          }
          final manifest = PluginManifest.read(manifestFile);
          if (_plugins.containsKey(manifest.id) ||
              _directoryOpeners.containsKey(manifest.id)) {
            _issues.add(
              PluginDiscoveryIssue(
                manifestFile.path,
                '插件 ID 重复：${manifest.id}',
              ),
            );
            continue;
          }
          if (manifest.openDirectory != null) {
            final executable = _directoryOpenerResolver.resolve(manifest);
            if (executable == null) {
              _issues.add(
                PluginDiscoveryIssue(
                  manifestFile.path,
                  '未找到可执行程序：${manifest.id}',
                ),
              );
              continue;
            }
            _directoryOpeners[manifest.id] = DirectoryOpenerPlugin(
              manifest: manifest,
              executablePath: executable,
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

    _associationStoreWritable = true;
    final defaultGroup = _loadDefaultGroup();
    try {
      _associations = _associationStore.load(defaultGroup: defaultGroup);
    } catch (error) {
      _associations = ViewerAssociationConfig.empty(defaultGroup: defaultGroup);
      _associationStoreWritable = false;
      _issues.add(
        PluginDiscoveryIssue(_associationStore.filePath, '关联配置加载失败：$error'),
      );
    }
    if (_associationStoreWritable && _associations.needsMigration) {
      try {
        _associationStore.save(_associations);
      } catch (error) {
        _issues.add(
          PluginDiscoveryIssue(
            _associationStore.filePath,
            '关联配置迁移保存失败：$error',
          ),
        );
      }
    }
    if (notify) notifyListeners();
  }

  /// 解析 plugins 静态默认配置（schema v3 的预置分组文档）。缺失或损坏
  /// 时回退为空的预设组，保证配置界面仍可用。
  ViewerRuleGroup _loadDefaultGroup() {
    final file = _defaultConfigFile;
    if (file == null || !file.existsSync()) {
      return ViewerAssociationConfig.presetDefaultGroup();
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('默认配置根节点必须是对象');
      }
      return ViewerAssociationConfig.parsePresetGroup(decoded);
    } catch (error) {
      _issues.add(
        PluginDiscoveryIssue(file.path, '默认关联配置加载失败：$error'),
      );
      return ViewerAssociationConfig.presetDefaultGroup();
    }
  }

  /// 定位 plugins 目录下的默认关联配置：优先开发目录 `plugins/`，
  /// 其次各插件根目录（发布时位于程序旁 `plugins/`）。
  static File? discoverDefaultConfigFile() {
    final candidates = <String>[
      p.join(Directory.current.path, 'plugins', 'quick-view.default.json'),
      for (final root in defaultPluginRoots())
        p.join(root.path, 'quick-view.default.json'),
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) return file;
    }
    return null;
  }

  List<ViewerRuleGroup> get ruleGroups => _associations.groups;

  ViewerRuleGroup ruleGroup(String id) => _associations.group(id);

  ViewerRuleGroup addRuleGroup({required String name}) {
    final group = ViewerRuleGroup(
      id: _newRuleGroupId(),
      name: name,
      preset: false,
      enabled: true,
    );
    _associations.addGroup(group);
    _saveAndNotify();
    return group;
  }

  void renameRuleGroup(String id, String name) {
    final group = ruleGroup(id);
    _associations.updateGroup(group.copyWith(name: name));
    _saveAndNotify();
  }

  void setRuleGroupEnabled(String id, bool enabled) {
    final group = ruleGroup(id);
    _associations.updateGroup(group.copyWith(enabled: enabled));
    _saveAndNotify();
  }

  void removeRuleGroup(String id) {
    _associations.removeGroup(id);
    _saveAndNotify();
  }

  void reorderRuleGroups(int oldIndex, int newIndex) {
    _associations.reorderGroup(oldIndex, newIndex);
    _saveAndNotify();
  }

  List<ViewerRule> rulesForGroup(String groupId) =>
      _associations.rulesForGroup(groupId);

  List<ViewerRule> get rules => _associations.allRules;

  ViewerRule rule(String id) => _associations.rule(id);

  ViewerRule addRule({
    required String groupId,
    String? parentRuleId,
    required ViewerRuleType type,
    required String value,
    ViewerPathMatchMode? pathMode,
    Iterable<String> viewerIds = const [],
  }) {
    final valueRule = ViewerRule(
      id: _newRuleId(type),
      managed: false,
      enabled: true,
      type: type,
      value: value,
      pathMode: type == ViewerRuleType.path
          ? (pathMode ?? ViewerPathMatchMode.glob)
          : null,
      viewers: [
        for (final id in _validateViewerIds(viewerIds))
          ViewerRuleViewer(id: id, managed: false, enabled: true),
      ],
    );
    _associations.addRule(groupId, valueRule, parentRuleId: parentRuleId);
    _saveAndNotify();
    return valueRule;
  }

  void updateRule(
    String id, {
    ViewerRuleType? type,
    String? value,
    ViewerPathMatchMode? pathMode,
  }) {
    final current = rule(id);
    _associations.updateRule(
      current.copyWith(type: type, value: value, pathMode: pathMode),
    );
    _saveAndNotify();
  }

  void setRuleEnabled(String id, bool enabled) {
    final current = rule(id);
    _associations.updateRule(current.copyWith(enabled: enabled));
    _saveAndNotify();
  }

  void removeRule(String id) {
    _associations.removeRule(id);
    _saveAndNotify();
  }

  void moveRuleBefore(String id, String targetId) {
    _associations.moveRuleBefore(id, targetId);
    _saveAndNotify();
  }

  void moveRuleInto(String id, String parentId) {
    _associations.moveRuleInto(id, parentId);
    _saveAndNotify();
  }

  void moveRuleToGroup(String id, String groupId) {
    _associations.moveRuleToGroup(id, groupId);
    _saveAndNotify();
  }

  ViewerRuleGroup groupForRule(String ruleId) =>
      _associations.groupForRule(ruleId);

  List<ViewerPlugin> availablePluginsForRule(ViewerRule valueRule) {
    final existing = valueRule.viewers.map((viewer) => viewer.id).toSet();
    return plugins
        .where(
          (plugin) =>
              plugin.isAvailable && !existing.contains(plugin.manifest.id),
        )
        .toList();
  }

  ViewerPlugin? pluginById(String id) => _plugins[id.trim().toLowerCase()];

  List<ViewerPlugin> viewersForRule(
    ViewerRule valueRule, {
    bool includeDisabled = false,
  }) => [
    for (final viewer in valueRule.viewers)
      if (includeDisabled || viewer.enabled) ?_plugins[viewer.id],
  ];

  void _ensureRuleEditable(String ruleId) {
    if (groupForRule(ruleId).preset) {
      throw ArgumentError('预置规则不能修改');
    }
  }

  void addViewerToRule(String ruleId, String pluginId) {
    _ensureRuleEditable(ruleId);
    final current = rule(ruleId);
    final normalized = ViewerRuleViewer.normalizeId(pluginId);
    if (!_plugins.containsKey(normalized)) {
      throw ArgumentError('Viewer 不存在：$pluginId');
    }
    final index = current.viewers.indexWhere(
      (viewer) => viewer.id == normalized,
    );
    if (index >= 0) {
      current.viewers[index] = current.viewers[index].copyWith(enabled: true);
    } else {
      current.viewers.add(
        ViewerRuleViewer(id: normalized, managed: false, enabled: true),
      );
    }
    _saveAndNotify();
  }

  void setRuleViewerEnabled(String ruleId, String pluginId, bool enabled) {
    _ensureRuleEditable(ruleId);
    final current = rule(ruleId);
    final normalized = ViewerRuleViewer.normalizeId(pluginId);
    final index = current.viewers.indexWhere(
      (viewer) => viewer.id == normalized,
    );
    if (index < 0) throw ArgumentError('规则中不存在 Viewer：$pluginId');
    current.viewers[index] = current.viewers[index].copyWith(enabled: enabled);
    _saveAndNotify();
  }

  void reorderRuleViewers(String ruleId, int oldIndex, int newIndex) {
    _ensureRuleEditable(ruleId);
    final viewers = rule(ruleId).viewers;
    if (oldIndex < 0 || oldIndex >= viewers.length) {
      throw RangeError.index(oldIndex, viewers, 'oldIndex');
    }
    final target = newIndex.clamp(0, viewers.length - 1);
    if (target == oldIndex) return;
    final viewer = viewers.removeAt(oldIndex);
    viewers.insert(target, viewer);
    _saveAndNotify();
  }

  void removeViewerFromRule(String ruleId, String pluginId) {
    _ensureRuleEditable(ruleId);
    final current = rule(ruleId);
    final normalized = ViewerRuleViewer.normalizeId(pluginId);
    final index = current.viewers.indexWhere(
      (viewer) => viewer.id == normalized,
    );
    if (index < 0) throw ArgumentError('规则中不存在 Viewer：$pluginId');
    if (current.viewers[index].managed) {
      throw ArgumentError('默认 Viewer 不能删除，请改为禁用');
    }
    current.viewers.removeAt(index);
    _saveAndNotify();
  }

  List<ViewerPlugin> resolve(String filePath, {String? mimeType}) {
    return resolveCandidates(
      filePath,
      mimeType: mimeType,
    ).map((candidate) => candidate.plugin).toList();
  }

  List<ViewerResolutionCandidate> resolveCandidates(
    String filePath, {
    String? mimeType,
  }) {
    final resolvedMime = mimeType ?? _mimeTypeResolver(filePath);
    final facts = ViewerFileFacts.fromPath(filePath, mimeType: resolvedMime);
    final candidates = <ViewerResolutionCandidate>[];

    for (final group in ruleGroups) {
      if (!group.enabled) continue;
      for (final valueRule in group.rules) {
        _collectRuleCandidates(group.id, valueRule, facts, candidates);
      }
    }

    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.plugin.manifest.id)) candidate,
    ];
  }

  Future<QuickViewOpenResult> open(String filePath, {String? mimeType}) {
    return _serialize(() => _open(filePath, mimeType: mimeType));
  }

  Future<QuickViewOpenResult> _open(String filePath, {String? mimeType}) async {
    if (_shuttingDown) {
      return QuickViewOpenResult.failure('应用正在退出，无法打开快速查看');
    }

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
    final previous = _attachedViewer;
    final placement = previous == null
        ? null
        : _windowController.capturePlacement(
            previous.windowHandle,
            logLabel:
                'capture-old plugin=${previous.plugin.manifest.id} '
                'pid=${previous.process.processId}',
          );
    if (previous != null) {
      debugPrint(
        '[QuickViewWindow] captured old plugin=${previous.plugin.manifest.id} '
        'pid=${previous.process.processId} hwnd=${previous.windowHandle} '
        'placement=$placement',
      );
    }
    for (final plugin in candidates) {
      ViewerProcessHandle? process;
      int? windowHandle;
      try {
        final arguments = <String>[p.absolute(filePath)];
        if (placement != null) {
          arguments.addAll([
            '--window-placement',
            jsonEncode(placement.toProtocolV2Json()),
          ]);
        }
        _logViewerWindow(
          '[QuickViewWindow] starting plugin=${plugin.manifest.id} '
          'placementArgument=${arguments.length == 3 ? arguments.last : 'none'}',
        );
        process = await _processStarter(
          plugin.executablePath,
          arguments,
          plugin.directoryPath,
        );

        windowHandle = await Future.any<int?>([
          _windowController.waitForTopLevelWindow(
            process.processId,
            timeout: _windowDiscoveryTimeout,
          ),
          process.exitCode.then<int?>((_) => null),
        ]);
        if (windowHandle == null) {
          throw StateError('查看器未能创建窗口');
        }
        debugPrint(
          '[QuickViewWindow] launched new plugin=${plugin.manifest.id} '
          'pid=${process.processId} hwnd=$windowHandle inherit=$placement',
        );
        final viewer = _AttachedViewer(
          plugin: plugin,
          process: process,
          windowHandle: windowHandle,
        );
        _attachedViewer = viewer;
        _watchExit(viewer);
        _notify();

        if (previous != null) await _closeViewer(previous);
        return QuickViewOpenResult.success(plugin);
      } catch (error) {
        if (windowHandle != null) {
          _windowController.requestClose(windowHandle);
        }
        process?.terminate();
        lastError = error;
        debugPrint('[QuickView] ${plugin.manifest.id} launch failed: $error');
      }
    }
    return QuickViewOpenResult.failure('查看器启动失败：$lastError');
  }

  Future<bool> detachViewer() {
    return _serialize(() async {
      final viewer = _attachedViewer;
      if (viewer == null) return false;
      _attachedViewer = null;
      debugPrint(
        '[QuickView] detached ${viewer.plugin.manifest.id} '
        '(pid ${viewer.process.processId})',
      );
      _notify();
      return true;
    });
  }

  Future<void> shutdown() {
    _shuttingDown = true;
    return _shutdownFuture ??= _serialize(() async {
      final viewer = _attachedViewer;
      _attachedViewer = null;
      _notify();
      if (viewer != null) await _closeViewer(viewer);
    });
  }

  void _collectRuleCandidates(
    String groupId,
    ViewerRule valueRule,
    ViewerFileFacts facts,
    List<ViewerResolutionCandidate> target,
  ) {
    if (!valueRule.matches(facts)) return;
    for (final child in valueRule.rules) {
      _collectRuleCandidates(groupId, child, facts, target);
    }
    final matchKind = switch (valueRule.type) {
      ViewerRuleType.path => ViewerMatchKind.pathRule,
      ViewerRuleType.fileName => ViewerMatchKind.fileName,
      ViewerRuleType.extension => ViewerMatchKind.suffix,
      ViewerRuleType.mimeType when valueRule.value.endsWith('/*') =>
        ViewerMatchKind.mimeWildcard,
      ViewerRuleType.mimeType => ViewerMatchKind.mimeExact,
    };
    for (final viewer in valueRule.viewers) {
      if (!viewer.enabled) continue;
      final plugin = _plugins[viewer.id];
      if (plugin == null || !plugin.isAvailable) continue;
      target.add(
        ViewerResolutionCandidate(
          plugin: plugin,
          groupId: groupId,
          matchKind: matchKind,
          matchedValue: valueRule.value,
          ruleId: valueRule.id,
        ),
      );
    }
  }

  List<String> _validateViewerIds(Iterable<String> viewerIds) {
    final ids = viewerIds.map((id) => id.trim().toLowerCase()).toSet().toList();
    final invalid = ids.where((id) => !_plugins.containsKey(id)).toList();
    if (invalid.isNotEmpty) {
      throw ArgumentError('Viewer 不存在：${invalid.join(', ')}');
    }
    return ids;
  }

  String _newRuleGroupId() {
    final base = 'group-${DateTime.now().microsecondsSinceEpoch}';
    var id = base;
    var suffix = 2;
    final existing = ruleGroups.map((group) => group.id).toSet();
    while (existing.contains(id)) {
      id = '$base-$suffix';
      suffix++;
    }
    return id;
  }

  String _newRuleId(ViewerRuleType type) {
    final base = '${type.jsonValue}-${DateTime.now().microsecondsSinceEpoch}';
    var id = base;
    var suffix = 2;
    final existing = rules.map((rule) => rule.id).toSet();
    while (existing.contains(id)) {
      id = '$base-$suffix';
      suffix++;
    }
    return id;
  }

  void _saveAndNotify() {
    if (_associationStoreWritable) {
      try {
        _associationStore.save(_associations);
      } catch (error) {
        _issues.add(
          PluginDiscoveryIssue(_associationStore.filePath, '关联配置保存失败：$error'),
        );
      }
    }
    notifyListeners();
  }

  static int _comparePlugins(ViewerPlugin a, ViewerPlugin b) {
    final byName = a.manifest.name.compareTo(b.manifest.name);
    return byName != 0 ? byName : a.manifest.id.compareTo(b.manifest.id);
  }

  Future<void> _closeViewer(_AttachedViewer viewer) async {
    _windowController.requestClose(viewer.windowHandle);
    try {
      await viewer.process.exitCode.timeout(_processExitTimeout);
    } on TimeoutException {
      viewer.process.terminate();
    } catch (error) {
      debugPrint('[QuickView] viewer exit failed: $error');
      viewer.process.terminate();
    }
  }

  void _watchExit(_AttachedViewer viewer) {
    unawaited(
      viewer.process.exitCode.then<void>(
        (exitCode) {
          if (!identical(_attachedViewer, viewer)) return;
          _attachedViewer = null;
          debugPrint(
            '[QuickView] ${viewer.plugin.manifest.id} exited with $exitCode',
          );
          _notify();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!identical(_attachedViewer, viewer)) return;
          _attachedViewer = null;
          debugPrint('[QuickView] viewer exit observation failed: $error');
          _notify();
        },
      ),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final viewer = _attachedViewer;
    _attachedViewer = null;
    if (viewer != null) {
      _windowController.requestClose(viewer.windowHandle);
      viewer.process.terminate();
    }
    super.dispose();
  }

  static Future<ViewerProcessHandle> _startProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.normal,
    );
    unawaited(
      process.stdout.drain<void>().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    unawaited(
      process.stderr.drain<void>().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    return ViewerProcessHandle(
      processId: process.pid,
      exitCode: process.exitCode,
      terminate: process.kill,
    );
  }

  static Future<ViewerProcessHandle> _startDetachedProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
    return ViewerProcessHandle(
      processId: process.pid,
      exitCode: Future.value(-1),
      terminate: () => false,
    );
  }
}

class _AttachedViewer {
  const _AttachedViewer({
    required this.plugin,
    required this.process,
    required this.windowHandle,
  });

  final ViewerPlugin plugin;
  final ViewerProcessHandle process;
  final int windowHandle;
}
