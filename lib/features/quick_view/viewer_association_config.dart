import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';
import 'viewer_rule.dart';

class ViewerAssociationOverride {
  ViewerAssociationOverride({
    required this.enabled,
    required Iterable<String> viewerOrder,
    required Iterable<String> excludedViewerIds,
    this.legacyExact = false,
  }) : viewerOrder = List.unmodifiable(_normalizeIds(viewerOrder)),
       excludedViewerIds = Set.unmodifiable(_normalizeIds(excludedViewerIds));

  factory ViewerAssociationOverride.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final viewerOrder = json['viewerOrder'];
    final excludedViewerIds = json['excludedViewerIds'];
    if (enabled is! bool ||
        viewerOrder is! List ||
        excludedViewerIds is! List) {
      throw const FormatException('关联覆盖字段无效');
    }
    return ViewerAssociationOverride(
      enabled: enabled,
      viewerOrder: viewerOrder.whereType<String>(),
      excludedViewerIds: excludedViewerIds.whereType<String>(),
    );
  }

  final bool enabled;
  final List<String> viewerOrder;
  final Set<String> excludedViewerIds;
  final bool legacyExact;

  ViewerAssociationOverride finishLegacyMigration(
    Iterable<String> availableViewerIds,
  ) => ViewerAssociationOverride(
    enabled: enabled,
    viewerOrder: viewerOrder,
    excludedViewerIds: availableViewerIds.where(
      (id) => !viewerOrder.contains(id.toLowerCase()),
    ),
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'viewerOrder': viewerOrder,
    'excludedViewerIds': excludedViewerIds.toList()..sort(),
  };

  static List<String> _normalizeIds(Iterable<String> ids) => ids
      .map((id) => id.trim().toLowerCase())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
}

class ViewerAssociationConfig {
  ViewerAssociationConfig._(
    this._overrides,
    this._rules, {
    bool needsMigration = false,
  }) : _needsMigration = needsMigration;

  factory ViewerAssociationConfig.empty() => ViewerAssociationConfig._({
    for (final kind in ViewerAssociationKind.values)
      kind: <String, ViewerAssociationOverride>{},
  }, <ViewerPathRule>[]);

  factory ViewerAssociationConfig.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    return switch (version) {
      1 => _fromVersion1(json),
      2 => _fromVersion2(json),
      _ => throw FormatException('不支持的关联配置版本：$version'),
    };
  }

  static ViewerAssociationConfig _fromVersion1(Map<String, Object?> json) {
    final result = ViewerAssociationConfig._(
      {
        for (final kind in ViewerAssociationKind.values)
          kind: <String, ViewerAssociationOverride>{},
      },
      <ViewerPathRule>[],
      needsMigration: true,
    );
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
          final viewerIds = ids.whereType<String>();
          result._overrides[kind]![key] = ViewerAssociationOverride(
            enabled: ids.isNotEmpty,
            viewerOrder: viewerIds,
            excludedViewerIds: const [],
            legacyExact: true,
          );
        } on FormatException {
          // Keep valid entries when one legacy association is malformed.
        }
      }
    }
    return result;
  }

  static ViewerAssociationConfig _fromVersion2(Map<String, Object?> json) {
    final result = ViewerAssociationConfig.empty();
    final associations = json['associations'];
    if (associations is Map<String, Object?>) {
      for (final kind in ViewerAssociationKind.values) {
        final group = associations[kind.jsonKey];
        if (group is! Map<String, Object?>) continue;
        for (final entry in group.entries) {
          if (entry.value is! Map<String, Object?>) continue;
          try {
            final key = kind.normalize(entry.key);
            result._overrides[kind]![key] = ViewerAssociationOverride.fromJson(
              entry.value! as Map<String, Object?>,
            );
          } on FormatException {
            // Keep valid entries when one override is malformed.
          }
        }
      }
    }

    final rules = json['rules'];
    if (rules is List) {
      final ids = <String>{};
      for (final rawRule in rules.whereType<Map<String, Object?>>()) {
        try {
          final rule = ViewerPathRule.fromJson(rawRule);
          if (ids.add(rule.id)) result._rules.add(rule);
        } on FormatException {
          // Keep valid entries when one rule is malformed.
        }
      }
    }
    return result;
  }

  final Map<ViewerAssociationKind, Map<String, ViewerAssociationOverride>>
  _overrides;
  final List<ViewerPathRule> _rules;
  bool _needsMigration;

  List<ViewerPathRule> get rules => List.unmodifiable(_rules);

  bool get needsMigration => _needsMigration;

  bool hasOverride(ViewerAssociationKind kind, String rawKey) =>
      _overrides[kind]!.containsKey(kind.normalize(rawKey));

  ViewerAssociationOverride? overrideFor(
    ViewerAssociationKind kind,
    String rawKey,
  ) => _overrides[kind]![kind.normalize(rawKey)];

  Set<String> keysFor(ViewerAssociationKind kind) =>
      Set.unmodifiable(_overrides[kind]!.keys);

  void setOverride(
    ViewerAssociationKind kind,
    String rawKey, {
    required bool enabled,
    required Iterable<String> viewerOrder,
    required Iterable<String> excludedViewerIds,
  }) {
    final key = kind.normalize(rawKey);
    _overrides[kind]![key] = ViewerAssociationOverride(
      enabled: enabled,
      viewerOrder: viewerOrder,
      excludedViewerIds: excludedViewerIds,
    );
  }

  void reset(ViewerAssociationKind kind, String rawKey) {
    _overrides[kind]!.remove(kind.normalize(rawKey));
  }

  void finishLegacyMigration(
    Iterable<String> Function(ViewerAssociationKind kind, String key)
    availableViewerIds,
  ) {
    for (final kind in ViewerAssociationKind.values) {
      final group = _overrides[kind]!;
      for (final entry in group.entries.toList()) {
        if (!entry.value.legacyExact) continue;
        group[entry.key] = entry.value.finishLegacyMigration(
          availableViewerIds(kind, entry.key),
        );
      }
    }
    _needsMigration = false;
  }

  void addRule(ViewerPathRule rule) {
    if (_rules.any((item) => item.id == rule.id)) {
      throw ArgumentError('规则 ID 已存在：${rule.id}');
    }
    _rules.add(rule);
  }

  void updateRule(ViewerPathRule rule) {
    final index = _rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) throw ArgumentError('规则不存在：${rule.id}');
    _rules[index] = rule;
  }

  void removeRule(String id) {
    _rules.removeWhere((rule) => rule.id == id);
  }

  void moveRule(String id, int offset) {
    final from = _rules.indexWhere((rule) => rule.id == id);
    if (from < 0) throw ArgumentError('规则不存在：$id');
    final to = (from + offset).clamp(0, _rules.length - 1);
    if (from == to) return;
    final rule = _rules.removeAt(from);
    _rules.insert(to, rule);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'rules': [for (final rule in _rules) rule.toJson()],
    'associations': {
      for (final kind in ViewerAssociationKind.values)
        kind.jsonKey: {
          for (final entry in _overrides[kind]!.entries)
            entry.key: entry.value.toJson(),
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
