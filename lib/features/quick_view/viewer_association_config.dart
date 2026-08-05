import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';

class ViewerAssociationConfig {
  ViewerAssociationConfig._(this._values);

  factory ViewerAssociationConfig.empty() => ViewerAssociationConfig._({
    for (final kind in ViewerAssociationKind.values)
      kind: <String, List<String>>{},
  });

  factory ViewerAssociationConfig.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw FormatException('不支持的关联配置版本：${json['schemaVersion']}');
    }

    final result = ViewerAssociationConfig.empty();
    final associations = json['associations'];
    if (associations is! Map<String, Object?>) return result;

    for (final kind in ViewerAssociationKind.values) {
      final group = associations[kind.jsonKey];
      if (group is! Map<String, Object?>) continue;
      for (final entry in group.entries) {
        final ids = entry.value;
        if (ids is! List) continue;
        try {
          final key = kind.normalize(entry.key);
          result._values[kind]![key] = List.unmodifiable(
            ids.whereType<String>().map((id) => id.toLowerCase()).toSet(),
          );
        } on FormatException {
          // Ignore malformed keys without discarding the remaining settings.
        }
      }
    }
    return result;
  }

  final Map<ViewerAssociationKind, Map<String, List<String>>> _values;

  bool hasOverride(ViewerAssociationKind kind, String rawKey) =>
      _values[kind]!.containsKey(kind.normalize(rawKey));

  List<String>? idsFor(ViewerAssociationKind kind, String rawKey) =>
      _values[kind]![kind.normalize(rawKey)];

  Set<String> keysFor(ViewerAssociationKind kind) =>
      Set.unmodifiable(_values[kind]!.keys);

  void set(
    ViewerAssociationKind kind,
    String rawKey,
    Iterable<String> pluginIds,
  ) {
    final key = kind.normalize(rawKey);
    _values[kind]![key] = List.unmodifiable(
      pluginIds.map((id) => id.toLowerCase()).toSet(),
    );
  }

  void reset(ViewerAssociationKind kind, String rawKey) {
    _values[kind]!.remove(kind.normalize(rawKey));
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'associations': {
      for (final kind in ViewerAssociationKind.values)
        kind.jsonKey: {
          for (final entry in _values[kind]!.entries) entry.key: entry.value,
        },
    },
  };
}

class ViewerAssociationStore {
  ViewerAssociationStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'viewer_associations.json');
  }

  ViewerAssociationConfig load() {
    final file = File(filePath);
    if (!file.existsSync()) return ViewerAssociationConfig.empty();
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('关联配置根节点必须是对象');
    }
    return ViewerAssociationConfig.fromJson(decoded);
  }

  void save(ViewerAssociationConfig config) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(config.toJson())}\n');
  }
}
