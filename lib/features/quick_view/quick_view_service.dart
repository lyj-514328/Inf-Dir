import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/mime_type_service.dart';
import 'plugin_manifest.dart';
import 'viewer_association_config.dart';
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

class QuickViewService extends ChangeNotifier {
  QuickViewService({
    List<Directory>? pluginRoots,
    ViewerAssociationStore? associationStore,
    String? Function(String filePath)? mimeTypeResolver,
    ViewerProcessStarter? processStarter,
    ViewerWindowController? windowController,
    Duration windowDiscoveryTimeout = const Duration(seconds: 12),
    Duration processExitTimeout = const Duration(milliseconds: 250),
  }) : _pluginRoots = pluginRoots ?? defaultPluginRoots(),
       _associationStore = associationStore ?? ViewerAssociationStore(),
       _windowController =
           windowController ??
           Win32ViewerWindowController(logger: _logViewerWindow),
       _windowDiscoveryTimeout = windowDiscoveryTimeout,
       _processExitTimeout = processExitTimeout {
    _mimeTypeResolver = mimeTypeResolver ?? MimeTypeService.forPath;
    _processStarter = processStarter ?? _startProcess;
    reload(notify: false);
  }

  final List<Directory> _pluginRoots;
  final ViewerAssociationStore _associationStore;
  final ViewerWindowController _windowController;
  final Duration _windowDiscoveryTimeout;
  final Duration _processExitTimeout;
  late final String? Function(String filePath) _mimeTypeResolver;
  late final ViewerProcessStarter _processStarter;
  final Map<String, ViewerPlugin> _plugins = {};
  final List<PluginDiscoveryIssue> _issues = [];
  late ViewerAssociationConfig _associations;
  _AttachedViewer? _attachedViewer;
  Future<void> _operationQueue = Future<void>.value();
  Future<void>? _shutdownFuture;
  bool _shuttingDown = false;
  bool _disposed = false;

  List<ViewerPlugin> get plugins {
    final result = _plugins.values.toList()..sort(_comparePlugins);
    return List.unmodifiable(result);
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
