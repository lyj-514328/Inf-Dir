import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';
import 'viewer_rule.dart';

enum ViewerRuleGroupType {
  path('path', '路径'),
  extension('extension', '扩展名'),
  fileName('fileName', '文件名'),
  mimeType('mimeType', 'MIME');

  const ViewerRuleGroupType(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  ViewerAssociationKind? get associationKind => switch (this) {
    ViewerRuleGroupType.path => null,
    ViewerRuleGroupType.extension => ViewerAssociationKind.extension,
    ViewerRuleGroupType.fileName => ViewerAssociationKind.fileName,
    ViewerRuleGroupType.mimeType => ViewerAssociationKind.mimeType,
  };

  static ViewerRuleGroupType parse(Object? value) => switch (value) {
    'path' => ViewerRuleGroupType.path,
    'extension' => ViewerRuleGroupType.extension,
    'fileName' => ViewerRuleGroupType.fileName,
    'mimeType' => ViewerRuleGroupType.mimeType,
    _ => throw FormatException('不支持的规则组类型：$value'),
  };

  static ViewerRuleGroupType forAssociationKind(ViewerAssociationKind kind) =>
      switch (kind) {
        ViewerAssociationKind.extension => ViewerRuleGroupType.extension,
        ViewerAssociationKind.fileName => ViewerRuleGroupType.fileName,
        ViewerAssociationKind.mimeType => ViewerRuleGroupType.mimeType,
      };
}

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

  ViewerAssociationOverride copyWith({
    bool? enabled,
    Iterable<String>? viewerOrder,
    Iterable<String>? excludedViewerIds,
  }) => ViewerAssociationOverride(
    enabled: enabled ?? this.enabled,
    viewerOrder: viewerOrder ?? this.viewerOrder,
    excludedViewerIds: excludedViewerIds ?? this.excludedViewerIds,
  );

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

class ViewerRuleGroup {
  ViewerRuleGroup({
    required String id,
    required String name,
    required this.type,
    required this.builtIn,
    required this.enabled,
    Map<String, ViewerAssociationOverride>? overrides,
    Iterable<ViewerPathRule> rules = const [],
  }) : id = _normalizeId(id),
       name = _normalizeName(name),
       _overrides = Map.of(overrides ?? const {}),
       _rules = List.of(rules) {
    if (type == ViewerRuleGroupType.path && _overrides.isNotEmpty) {
      throw const FormatException('路径规则组不能包含普通关联');
    }
    if (type != ViewerRuleGroupType.path && _rules.isNotEmpty) {
      throw const FormatException('普通关联规则组不能包含路径规则');
    }
  }

  final String id;
  final String name;
  final ViewerRuleGroupType type;
  final bool builtIn;
  final bool enabled;
  final Map<String, ViewerAssociationOverride> _overrides;
  final List<ViewerPathRule> _rules;

  ViewerAssociationKind? get associationKind => type.associationKind;
  List<ViewerPathRule> get rules => List.unmodifiable(_rules);
  Set<String> get associationKeys => Set.unmodifiable(_overrides.keys);
  bool get isEmpty => _rules.isEmpty && _overrides.isEmpty;

  ViewerAssociationOverride? overrideFor(String key) => _overrides[key];

  ViewerRuleGroup copyWith({String? name, bool? enabled, bool? builtIn}) =>
      ViewerRuleGroup(
        id: id,
        name: name ?? this.name,
        type: type,
        builtIn: builtIn ?? this.builtIn,
        enabled: enabled ?? this.enabled,
        overrides: _overrides,
        rules: _rules,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.jsonValue,
    'builtIn': builtIn,
    'enabled': enabled,
    if (type == ViewerRuleGroupType.path)
      'rules': [for (final rule in _rules) rule.toJson()]
    else
      'associations': {
        for (final entry in _overrides.entries) entry.key: entry.value.toJson(),
      },
  };

  static String _normalizeId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(normalized)) {
      throw FormatException('无效规则组 ID：$value');
    }
    return normalized;
  }

  static String _normalizeName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw const FormatException('规则组名称不能为空');
    return normalized;
  }
}

class ViewerAssociationConfig {
  ViewerAssociationConfig._(this._groups, {bool needsMigration = false})
    : _needsMigration = needsMigration;

  static const String builtInPathGroupId = 'builtin-path';
  static const String builtInExtensionGroupId = 'builtin-extension';
  static const String builtInFileNameGroupId = 'builtin-file-name';
  static const String builtInMimeTypeGroupId = 'builtin-mime';

  factory ViewerAssociationConfig.empty() =>
      ViewerAssociationConfig._(_defaultGroups());

  factory ViewerAssociationConfig.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    return switch (version) {
      1 => _fromVersion1(json),
      2 =>
        json['groups'] is List
            ? _fromGroupedVersion2(json)
            : _fromLegacyVersion2(json),
      _ => throw FormatException('不支持的关联配置版本：$version'),
    };
  }

  static ViewerAssociationConfig _fromVersion1(Map<String, Object?> json) {
    final result = ViewerAssociationConfig._(
      _defaultGroups(),
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
          result
              ._builtInAssociationGroup(kind)
              ._overrides[key] = ViewerAssociationOverride(
            enabled: ids.isNotEmpty,
            viewerOrder: ids.whereType<String>(),
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

  static ViewerAssociationConfig _fromLegacyVersion2(
    Map<String, Object?> json,
  ) {
    final result = ViewerAssociationConfig._(
      _defaultGroups(),
      needsMigration: true,
    );
    final associations = json['associations'];
    if (associations is Map<String, Object?>) {
      for (final kind in ViewerAssociationKind.values) {
        final group = associations[kind.jsonKey];
        if (group is! Map<String, Object?>) continue;
        _decodeOverrides(
          group,
          kind,
          result._builtInAssociationGroup(kind)._overrides,
        );
      }
    }

    final rules = json['rules'];
    if (rules is List) {
      _decodePathRules(
        rules,
        result._groupById(builtInPathGroupId)._rules,
        <String>{},
      );
    }
    return result;
  }

  static ViewerAssociationConfig _fromGroupedVersion2(
    Map<String, Object?> json,
  ) {
    final groups = <ViewerRuleGroup>[];
    final groupIds = <String>{};
    final ruleIds = <String>{};
    var repaired = false;

    for (final raw in (json['groups']! as List)) {
      if (raw is! Map<String, Object?>) {
        repaired = true;
        continue;
      }
      try {
        final idValue = raw['id'];
        final nameValue = raw['name'];
        final enabledValue = raw['enabled'];
        if (idValue is! String ||
            nameValue is! String ||
            enabledValue is! bool) {
          throw const FormatException('规则组字段无效');
        }
        final id = ViewerRuleGroup._normalizeId(idValue);
        if (groupIds.contains(id)) {
          repaired = true;
          continue;
        }

        final declaredType = ViewerRuleGroupType.parse(raw['type']);
        final builtInType = _builtInTypes[id];
        if (builtInType != null && declaredType != builtInType) {
          throw FormatException('内置规则组 $id 的类型不能修改');
        }
        final type = builtInType ?? declaredType;
        final overrides = <String, ViewerAssociationOverride>{};
        final rules = <ViewerPathRule>[];
        if (type == ViewerRuleGroupType.path) {
          final rawRules = raw['rules'];
          if (rawRules is List) {
            _decodePathRules(rawRules, rules, ruleIds);
          }
        } else {
          final rawAssociations = raw['associations'];
          if (rawAssociations is Map<String, Object?>) {
            _decodeOverrides(rawAssociations, type.associationKind!, overrides);
          }
        }
        final group = ViewerRuleGroup(
          id: id,
          name: nameValue,
          type: type,
          builtIn: builtInType != null,
          enabled: enabledValue,
          overrides: overrides,
          rules: rules,
        );
        groups.add(group);
        groupIds.add(id);
        if ((raw['builtIn'] == true) != (builtInType != null)) repaired = true;
      } on FormatException {
        repaired = true;
      }
    }

    for (final defaultGroup in _defaultGroups()) {
      if (groupIds.add(defaultGroup.id)) {
        groups.add(defaultGroup);
        repaired = true;
      }
    }
    return ViewerAssociationConfig._(groups, needsMigration: repaired);
  }

  final List<ViewerRuleGroup> _groups;
  bool _needsMigration;

  static const Map<String, ViewerRuleGroupType> _builtInTypes = {
    builtInPathGroupId: ViewerRuleGroupType.path,
    builtInExtensionGroupId: ViewerRuleGroupType.extension,
    builtInFileNameGroupId: ViewerRuleGroupType.fileName,
    builtInMimeTypeGroupId: ViewerRuleGroupType.mimeType,
  };

  List<ViewerRuleGroup> get groups => List.unmodifiable(_groups);
  bool get needsMigration => _needsMigration;
  List<ViewerPathRule> get rules => List.unmodifiable([
    for (final group in _groups)
      if (group.type == ViewerRuleGroupType.path) ...group._rules,
  ]);

  static String builtInGroupIdFor(ViewerAssociationKind kind) => switch (kind) {
    ViewerAssociationKind.extension => builtInExtensionGroupId,
    ViewerAssociationKind.fileName => builtInFileNameGroupId,
    ViewerAssociationKind.mimeType => builtInMimeTypeGroupId,
  };

  ViewerRuleGroup group(String id) => _groupById(id);

  void addGroup(ViewerRuleGroup group) {
    if (_groups.any((item) => item.id == group.id)) {
      throw ArgumentError('规则组 ID 已存在：${group.id}');
    }
    if (group.builtIn) throw ArgumentError('不能添加自定义内置规则组');
    _groups.add(group);
  }

  void updateGroup(ViewerRuleGroup group) {
    final index = _groups.indexWhere((item) => item.id == group.id);
    if (index < 0) throw ArgumentError('规则组不存在：${group.id}');
    final current = _groups[index];
    if (group.type != current.type || group.builtIn != current.builtIn) {
      throw ArgumentError('规则组类型和内置状态不能修改');
    }
    _groups[index] = group;
  }

  void removeGroup(String id) {
    final group = _groupById(id);
    if (group.builtIn) throw ArgumentError('内置规则组不能删除');
    _groups.remove(group);
  }

  void reorderGroup(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _groups.length) {
      throw RangeError.index(oldIndex, _groups, 'oldIndex');
    }
    if (newIndex > oldIndex) newIndex--;
    final target = newIndex.clamp(0, _groups.length - 1);
    if (target == oldIndex) return;
    final group = _groups.removeAt(oldIndex);
    _groups.insert(target, group);
  }

  bool hasOverride(ViewerAssociationKind kind, String rawKey) =>
      hasOverrideForGroup(builtInGroupIdFor(kind), rawKey);

  bool hasOverrideForGroup(String groupId, String rawKey) {
    final group = _associationGroup(groupId);
    final key = group.associationKind!.normalize(rawKey);
    return group._overrides.containsKey(key);
  }

  ViewerAssociationOverride? overrideFor(
    ViewerAssociationKind kind,
    String rawKey,
  ) => overrideForGroup(builtInGroupIdFor(kind), rawKey);

  ViewerAssociationOverride? overrideForGroup(String groupId, String rawKey) {
    final group = _associationGroup(groupId);
    return group._overrides[group.associationKind!.normalize(rawKey)];
  }

  Set<String> keysFor(ViewerAssociationKind kind) =>
      keysForGroup(builtInGroupIdFor(kind));

  Set<String> keysForGroup(String groupId) =>
      _associationGroup(groupId).associationKeys;

  void setOverride(
    ViewerAssociationKind kind,
    String rawKey, {
    required bool enabled,
    required Iterable<String> viewerOrder,
    required Iterable<String> excludedViewerIds,
  }) => setOverrideForGroup(
    builtInGroupIdFor(kind),
    rawKey,
    enabled: enabled,
    viewerOrder: viewerOrder,
    excludedViewerIds: excludedViewerIds,
  );

  void setOverrideForGroup(
    String groupId,
    String rawKey, {
    required bool enabled,
    required Iterable<String> viewerOrder,
    required Iterable<String> excludedViewerIds,
  }) {
    final group = _associationGroup(groupId);
    final key = group.associationKind!.normalize(rawKey);
    group._overrides[key] = ViewerAssociationOverride(
      enabled: enabled,
      viewerOrder: viewerOrder,
      excludedViewerIds: excludedViewerIds,
    );
  }

  void reset(ViewerAssociationKind kind, String rawKey) =>
      resetForGroup(builtInGroupIdFor(kind), rawKey);

  void resetForGroup(String groupId, String rawKey) {
    final group = _associationGroup(groupId);
    group._overrides.remove(group.associationKind!.normalize(rawKey));
  }

  void finishLegacyMigration(
    Iterable<String> Function(ViewerAssociationKind kind, String key)
    availableViewerIds,
  ) {
    for (final group in _groups) {
      final kind = group.associationKind;
      if (kind == null) continue;
      for (final entry in group._overrides.entries.toList()) {
        if (!entry.value.legacyExact) continue;
        group._overrides[entry.key] = entry.value.finishLegacyMigration(
          availableViewerIds(kind, entry.key),
        );
      }
    }
    _needsMigration = false;
  }

  List<ViewerPathRule> rulesForGroup(String groupId) {
    final group = _pathGroup(groupId);
    return group.rules;
  }

  void addRule(ViewerPathRule rule, {String? groupId}) {
    if (rules.any((item) => item.id == rule.id)) {
      throw ArgumentError('规则 ID 已存在：${rule.id}');
    }
    _pathGroup(groupId ?? builtInPathGroupId)._rules.add(rule);
  }

  void updateRule(ViewerPathRule rule) {
    final location = _ruleLocation(rule.id);
    location.$1._rules[location.$2] = rule;
  }

  void removeRule(String id) {
    final location = _ruleLocation(id);
    location.$1._rules.removeAt(location.$2);
  }

  void moveRule(String id, int offset) {
    final location = _ruleLocation(id);
    final rules = location.$1._rules;
    final from = location.$2;
    final to = (from + offset).clamp(0, rules.length - 1);
    if (from == to) return;
    final rule = rules.removeAt(from);
    rules.insert(to, rule);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'groups': [for (final group in _groups) group.toJson()],
  };

  ViewerRuleGroup _groupById(String id) {
    final normalized = id.trim().toLowerCase();
    for (final group in _groups) {
      if (group.id == normalized) return group;
    }
    throw ArgumentError('规则组不存在：$id');
  }

  ViewerRuleGroup _associationGroup(String id) {
    final group = _groupById(id);
    if (group.type == ViewerRuleGroupType.path) {
      throw ArgumentError('路径规则组不包含普通关联：$id');
    }
    return group;
  }

  ViewerRuleGroup _pathGroup(String id) {
    final group = _groupById(id);
    if (group.type != ViewerRuleGroupType.path) {
      throw ArgumentError('规则组不是路径类型：$id');
    }
    return group;
  }

  ViewerRuleGroup _builtInAssociationGroup(ViewerAssociationKind kind) =>
      _associationGroup(builtInGroupIdFor(kind));

  (ViewerRuleGroup, int) _ruleLocation(String id) {
    for (final group in _groups) {
      if (group.type != ViewerRuleGroupType.path) continue;
      final index = group._rules.indexWhere((rule) => rule.id == id);
      if (index >= 0) return (group, index);
    }
    throw ArgumentError('规则不存在：$id');
  }

  static List<ViewerRuleGroup> _defaultGroups() => [
    ViewerRuleGroup(
      id: builtInPathGroupId,
      name: '路径',
      type: ViewerRuleGroupType.path,
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInExtensionGroupId,
      name: '扩展名',
      type: ViewerRuleGroupType.extension,
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInFileNameGroupId,
      name: '文件名',
      type: ViewerRuleGroupType.fileName,
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInMimeTypeGroupId,
      name: 'MIME',
      type: ViewerRuleGroupType.mimeType,
      builtIn: true,
      enabled: true,
    ),
  ];

  static void _decodeOverrides(
    Map<String, Object?> source,
    ViewerAssociationKind kind,
    Map<String, ViewerAssociationOverride> target,
  ) {
    for (final entry in source.entries) {
      if (entry.value is! Map<String, Object?>) continue;
      try {
        final key = kind.normalize(entry.key);
        target[key] = ViewerAssociationOverride.fromJson(
          entry.value! as Map<String, Object?>,
        );
      } on FormatException {
        // Keep valid entries when one override is malformed.
      }
    }
  }

  static void _decodePathRules(
    List<Object?> source,
    List<ViewerPathRule> target,
    Set<String> ids,
  ) {
    for (final rawRule in source.whereType<Map<String, Object?>>()) {
      try {
        final rule = ViewerPathRule.fromJson(rawRule);
        if (ids.add(rule.id)) target.add(rule);
      } on FormatException {
        // Keep valid entries when one rule is malformed.
      }
    }
  }
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
