import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum SearchPluginType {
  fileName('fileName', 'fd-nul-v1'),
  content('content', 'ripgrep-json-v1');

  const SearchPluginType(this.manifestValue, this.protocol);

  final String manifestValue;
  final String protocol;
}

abstract final class SearchPluginResolver {
  static String? resolve({
    required String pluginId,
    required SearchPluginType type,
    List<Directory>? roots,
  }) {
    for (final root in roots ?? defaultPluginRoots()) {
      if (!root.existsSync()) continue;
      final packages =
          root.listSync(followLinks: false).whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final package in packages) {
        final manifestFile = File(p.join(package.path, 'plugin.json'));
        if (!manifestFile.existsSync()) continue;
        final executable = _resolveManifest(
          manifestFile,
          package.path,
          pluginId,
          type,
        );
        if (executable != null) return executable;
      }
    }
    return null;
  }

  static List<Directory> defaultPluginRoots() {
    final overridePath = Platform.environment['INF_DIR_PLUGIN_DIR'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final appDirectory = p.dirname(Platform.resolvedExecutable);
    final paths = <String>[
      if (overridePath?.trim().isNotEmpty == true) overridePath!.trim(),
      p.join(appDirectory, 'plugins'),
      p.join(Directory.current.path, 'plugins', 'dist'),
      if (localAppData?.trim().isNotEmpty == true)
        p.join(localAppData!.trim(), 'Inf-Dir', 'plugins'),
    ];
    final seen = <String>{};
    return [
      for (final path in paths)
        if (seen.add(_pathKey(path))) Directory(path),
    ];
  }

  static String? _resolveManifest(
    File manifestFile,
    String packagePath,
    String expectedId,
    SearchPluginType expectedType,
  ) {
    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map || decoded['manifestVersion'] != 1) return null;
      if (decoded['id'] != expectedId) return null;

      final capabilities = decoded['capabilities'];
      final search = capabilities is Map ? capabilities['search'] : null;
      if (search is! Map ||
          search['type'] != expectedType.manifestValue ||
          search['protocol'] != expectedType.protocol) {
        return null;
      }

      final entrypoint = decoded['entrypoint'];
      if (entrypoint is! String || entrypoint.trim().isEmpty) return null;
      final normalized = p.normalize(entrypoint.trim());
      if (p.isAbsolute(normalized) || p.split(normalized).contains('..')) {
        return null;
      }

      final executable = File(p.join(packagePath, normalized));
      return executable.existsSync() ? executable.path : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String _pathKey(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
