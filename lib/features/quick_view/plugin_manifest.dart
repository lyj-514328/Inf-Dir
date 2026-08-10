import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum ViewerAssociationKind {
  extension('extensions', '扩展名'),
  fileName('fileNames', '文件名'),
  mimeType('mimeTypes', 'MIME');

  const ViewerAssociationKind(this.jsonKey, this.label);

  final String jsonKey;
  final String label;

  String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    switch (this) {
      case ViewerAssociationKind.extension:
        if (!normalized.startsWith('.') ||
            normalized.length < 2 ||
            normalized.contains(RegExp(r'[\\/]'))) {
          throw FormatException('无效扩展名：$value');
        }
        return normalized;
      case ViewerAssociationKind.fileName:
        if (normalized.isEmpty ||
            normalized == '.' ||
            normalized == '..' ||
            normalized.contains(RegExp(r'[\\/]'))) {
          throw FormatException('无效文件名：$value');
        }
        return normalized;
      case ViewerAssociationKind.mimeType:
        final mimePattern = RegExp(
          r'^[a-z0-9!#$&^_.+-]+/(?:[a-z0-9!#$&^_.+-]+|\*)$',
        );
        if (!mimePattern.hasMatch(normalized)) {
          throw FormatException('无效 MIME：$value');
        }
        return normalized;
    }
  }
}

class QuickViewCapability {
  const QuickViewCapability({
    required this.extensions,
    required this.fileNames,
    required this.mimeTypes,
  });

  final List<String> extensions;
  final List<String> fileNames;
  final List<String> mimeTypes;

  Iterable<String> valuesFor(ViewerAssociationKind kind) => switch (kind) {
    ViewerAssociationKind.extension => extensions,
    ViewerAssociationKind.fileName => fileNames,
    ViewerAssociationKind.mimeType => mimeTypes,
  };

  bool supports(ViewerAssociationKind kind, String rawValue) {
    final value = kind.normalize(rawValue);
    if (kind != ViewerAssociationKind.mimeType) {
      return valuesFor(kind).contains(value);
    }

    if (value.endsWith('/*')) return mimeTypes.contains(value);
    final slash = value.indexOf('/');
    final wildcard = '${value.substring(0, slash)}/*';
    return mimeTypes.contains(value) || mimeTypes.contains(wildcard);
  }
}

class PluginManifest {
  const PluginManifest({
    required this.manifestVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.entrypoint,
    required this.quickView,
  });

  final int manifestVersion;
  final String id;
  final String name;
  final String version;
  final String entrypoint;
  final QuickViewCapability quickView;

  factory PluginManifest.fromJson(Map<String, Object?> json) {
    final manifestVersion = json['manifestVersion'];
    if (manifestVersion is! int || manifestVersion != 1) {
      throw FormatException('不支持的 manifestVersion：$manifestVersion');
    }

    final id = _requiredString(json, 'id').toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$').hasMatch(id)) {
      throw FormatException('无效插件 ID：$id');
    }

    final entrypoint = _requiredString(json, 'entrypoint');
    final entrySegments = p.split(p.normalize(entrypoint));
    if (p.isAbsolute(entrypoint) || entrySegments.contains('..')) {
      throw FormatException('entrypoint 必须位于插件目录内：$entrypoint');
    }

    final capabilities = json['capabilities'];
    final quickViewJson = capabilities is Map<String, Object?>
        ? capabilities['quickView']
        : null;
    if (quickViewJson is! Map<String, Object?>) {
      throw const FormatException('缺少 capabilities.quickView');
    }

    final extensions = _normalizedList(
      quickViewJson['extensions'],
      ViewerAssociationKind.extension,
    );
    final fileNames = _normalizedList(
      quickViewJson['fileNames'],
      ViewerAssociationKind.fileName,
    );
    final mimeTypes = _normalizedList(
      quickViewJson['mimeTypes'],
      ViewerAssociationKind.mimeType,
    );
    if (extensions.isEmpty && fileNames.isEmpty && mimeTypes.isEmpty) {
      throw const FormatException('quickView 至少需要一个匹配项');
    }

    return PluginManifest(
      manifestVersion: manifestVersion,
      id: id,
      name: _requiredString(json, 'name'),
      version: _requiredString(json, 'version'),
      entrypoint: entrypoint,
      quickView: QuickViewCapability(
        extensions: extensions,
        fileNames: fileNames,
        mimeTypes: mimeTypes,
      ),
    );
  }

  static PluginManifest read(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Manifest 根节点必须是对象');
    }
    return PluginManifest.fromJson(decoded);
  }

  static bool declaresQuickView(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('Manifest 根节点必须是对象');
    }
    final capabilities = decoded['capabilities'];
    return capabilities is Map && capabilities.containsKey('quickView');
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('缺少字段：$key');
    }
    return value.trim();
  }

  static List<String> _normalizedList(Object? raw, ViewerAssociationKind kind) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw FormatException('${kind.jsonKey} 必须是数组');
    }
    final result = <String>{};
    for (final value in raw) {
      if (value is! String) {
        throw FormatException('${kind.jsonKey} 只能包含字符串');
      }
      result.add(kind.normalize(value));
    }
    return List.unmodifiable(result);
  }
}

class ViewerPlugin {
  const ViewerPlugin({required this.manifest, required this.directoryPath});

  final PluginManifest manifest;
  final String directoryPath;

  String get executablePath =>
      p.normalize(p.join(directoryPath, manifest.entrypoint));

  bool get isAvailable => File(executablePath).existsSync();
}
