import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'search_plugin_resolver.dart';

enum ArchivePluginType {
  sevenZip('7zip', '7zip-cli-v1');

  const ArchivePluginType(this.manifestValue, this.protocol);

  final String manifestValue;
  final String protocol;
}

abstract final class ArchivePluginResolver {
  static String? resolve({
    required String pluginId,
    required ArchivePluginType type,
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
    return SearchPluginResolver.defaultPluginRoots();
  }

  static String? _resolveManifest(
    File manifestFile,
    String packagePath,
    String expectedId,
    ArchivePluginType expectedType,
  ) {
    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map || decoded['manifestVersion'] != 1) return null;
      if (decoded['id'] != expectedId) return null;

      final capabilities = decoded['capabilities'];
      final archive = capabilities is Map ? capabilities['archive'] : null;
      if (archive is! Map ||
          archive['type'] != expectedType.manifestValue ||
          archive['protocol'] != expectedType.protocol) {
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
}
