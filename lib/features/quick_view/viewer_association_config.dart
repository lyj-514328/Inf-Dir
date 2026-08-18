import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';
import 'viewer_rule.dart';

class ViewerRuleGroup {
  ViewerRuleGroup({
    required String id,
    required String name,
    required this.builtIn,
    required this.enabled,
    Iterable<ViewerRule> rules = const [],
  }) : id = normalizeId(id),
       name = normalizeName(name),
       rules = List.of(rules);

  final String id;
  final String name;
  final bool builtIn;
  final bool enabled;
  final List<ViewerRule> rules;

  ViewerRuleGroup copyWith({
    String? name,
    bool? enabled,
    bool? builtIn,
    Iterable<ViewerRule>? rules,
  }) => ViewerRuleGroup(
    id: id,
    name: name ?? this.name,
    builtIn: builtIn ?? this.builtIn,
    enabled: enabled ?? this.enabled,
    rules: rules ?? this.rules,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'builtIn': builtIn,
    'enabled': enabled,
    'rules': [for (final rule in rules) rule.toJson()],
  };

  static String normalizeId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(normalized)) {
      throw FormatException('无效规则组 ID：$value');
    }
    return normalized;
  }

  static String normalizeName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw const FormatException('规则组名称不能为空');
    return normalized;
  }
}

class ViewerAssociationConfig {
  ViewerAssociationConfig._(
    this._groups, {
    bool needsMigration = false,
    Set<String>? legacyExactRuleIds,
  }) : _needsMigration = needsMigration,
       _legacyExactRuleIds = legacyExactRuleIds ?? <String>{};

  static const String builtInPathGroupId = 'builtin-path';
  static const String builtInFileNameGroupId = 'builtin-file-name';
  static const String builtInExtensionGroupId = 'builtin-extension';
  static const String builtInMimeTypeGroupId = 'builtin-mime';

  static const Set<String> _builtInGroupIds = {
    builtInPathGroupId,
    builtInFileNameGroupId,
    builtInExtensionGroupId,
    builtInMimeTypeGroupId,
  };

  factory ViewerAssociationConfig.empty() =>
      ViewerAssociationConfig._(_defaultGroups());

  factory ViewerAssociationConfig.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    return switch (version) {
      1 => _fromVersion1(json),
      2 => _fromVersion2(json),
      _ => throw FormatException('不支持的关联配置版本：$version'),
    };
  }

  final List<ViewerRuleGroup> _groups;
  final Set<String> _legacyExactRuleIds;
  bool _needsMigration;

  List<ViewerRuleGroup> get groups => List.unmodifiable(_groups);
  bool get needsMigration => _needsMigration;
  List<ViewerRule> get allRules => List.unmodifiable([
    for (final group in _groups) ..._flatten(group.rules),
  ]);

  ViewerRuleGroup group(String id) => _groupById(id);

  List<ViewerRule> rulesForGroup(String groupId) =>
      List.unmodifiable(_groupById(groupId).rules);

  ViewerRule rule(String id) => _ruleLocation(id).rule;

  ViewerRuleGroup groupForRule(String id) => _ruleLocation(id).group;

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
    if (_groups[index].builtIn != group.builtIn) {
      throw ArgumentError('规则组内置状态不能修改');
    }
    _groups[index] = group;
  }

  void removeGroup(String id) {
    final value = _groupById(id);
    if (value.builtIn) throw ArgumentError('内置规则组不能删除');
    _groups.remove(value);
  }

  void reorderGroup(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _groups.length) {
      throw RangeError.index(oldIndex, _groups, 'oldIndex');
    }
    final target = newIndex.clamp(0, _groups.length - 1);
    if (target == oldIndex) return;
    final value = _groups.removeAt(oldIndex);
    _groups.insert(target, value);
  }

  void addRule(String groupId, ViewerRule rule, {String? parentRuleId}) {
    _ensureRuleIdsAvailable(rule);
    final target = parentRuleId == null
        ? _groupById(groupId).rules
        : _ruleLocation(parentRuleId).rule.rules;
    if (parentRuleId != null &&
        _ruleLocation(parentRuleId).group.id !=
            ViewerRuleGroup.normalizeId(groupId)) {
      throw ArgumentError('父规则不在目标规则组中');
    }
    target.add(rule);
  }

  void updateRule(ViewerRule next) {
    final location = _ruleLocation(next.id);
    final current = location.rule;
    if (current.managed &&
        (next.type != current.type ||
            next.value != current.value ||
            next.pathMode != current.pathMode ||
            !next.managed)) {
      throw ArgumentError('默认规则的类型和匹配值不能修改');
    }
    location.siblings[location.index] = next;
  }

  void removeRule(String id) {
    final location = _ruleLocation(id);
    if (location.rule.managed) throw ArgumentError('默认规则不能删除');
    location.siblings.removeAt(location.index);
  }

  void moveRuleBefore(String id, String targetId) {
    if (id == targetId) return;
    final source = _ruleLocation(id);
    _ruleLocation(targetId);
    if (_containsRule(source.rule, targetId)) {
      throw ArgumentError('不能把规则移动到自己的子树中');
    }
    final value = source.siblings.removeAt(source.index);
    final target = _ruleLocation(targetId);
    target.siblings.insert(target.index, value);
  }

  void moveRuleInto(String id, String parentId) {
    if (id == parentId) throw ArgumentError('规则不能成为自己的子规则');
    final source = _ruleLocation(id);
    _ruleLocation(parentId);
    if (_containsRule(source.rule, parentId)) {
      throw ArgumentError('不能把规则移动到自己的子树中');
    }
    final value = source.siblings.removeAt(source.index);
    _ruleLocation(parentId).rule.rules.add(value);
  }

  void moveRuleToGroup(String id, String groupId) {
    final target = _groupById(groupId);
    final source = _ruleLocation(id);
    final value = source.siblings.removeAt(source.index);
    target.rules.add(value);
  }

  bool reconcileManifestPlugins(Iterable<PluginManifest> manifests) {
    var changed = _needsMigration;
    final declarations =
        <(ViewerAssociationKind, String), List<PluginManifest>>{};
    for (final manifest in manifests) {
      for (final kind in ViewerAssociationKind.values) {
        for (final value in manifest.quickView.valuesFor(kind)) {
          declarations.putIfAbsent((kind, value), () => []).add(manifest);
        }
      }
    }

    final entries = declarations.entries.toList()
      ..sort((a, b) => _compareDeclarations(a.key, b.key));
    for (final entry in entries) {
      final kind = entry.key.$1;
      final value = entry.key.$2;
      final id = defaultRuleId(kind, value);
      final manifestsForRule = entry.value
        ..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });
      final existing = _tryRuleLocation(id);
      if (existing == null) {
        _groupById(builtInGroupIdFor(kind)).rules.add(
          ViewerRule(
            id: id,
            managed: true,
            enabled: true,
            type: ViewerRuleType.fromAssociationKind(kind),
            value: value,
            viewers: [
              for (final manifest in manifestsForRule)
                ViewerRuleViewer(id: manifest.id, managed: true, enabled: true),
            ],
          ),
        );
        changed = true;
        continue;
      }

      final expectedType = ViewerRuleType.fromAssociationKind(kind);
      var valueRule = existing.rule;
      if (!valueRule.managed ||
          valueRule.type != expectedType ||
          valueRule.value != value ||
          valueRule.pathMode != null) {
        valueRule = ViewerRule(
          id: id,
          managed: true,
          enabled: valueRule.enabled,
          type: expectedType,
          value: value,
          rules: valueRule.rules,
          viewers: valueRule.viewers,
        );
        existing.siblings[existing.index] = valueRule;
        changed = true;
      }

      final exactLegacy = _legacyExactRuleIds.contains(id);
      final manifestIds = manifestsForRule
          .map((manifest) => manifest.id)
          .toSet();
      for (var index = 0; index < valueRule.viewers.length; index++) {
        final viewer = valueRule.viewers[index];
        if (manifestIds.contains(viewer.id) && !viewer.managed) {
          valueRule.viewers[index] = viewer.copyWith(managed: true);
          changed = true;
        }
      }
      final ids = valueRule.viewers.map((viewer) => viewer.id).toSet();
      for (final manifest in manifestsForRule) {
        if (!ids.add(manifest.id)) continue;
        valueRule.viewers.add(
          ViewerRuleViewer(
            id: manifest.id,
            managed: true,
            enabled: !exactLegacy,
          ),
        );
        changed = true;
      }
    }

    _legacyExactRuleIds.clear();
    _needsMigration = false;
    return changed;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'groups': [for (final group in _groups) group.toJson()],
  };

  static String builtInGroupIdFor(ViewerAssociationKind kind) => switch (kind) {
    ViewerAssociationKind.fileName => builtInFileNameGroupId,
    ViewerAssociationKind.extension => builtInExtensionGroupId,
    ViewerAssociationKind.mimeType => builtInMimeTypeGroupId,
  };

  static String defaultRuleId(ViewerAssociationKind kind, String rawValue) {
    final value = kind.normalize(rawValue);
    final encoded = utf8
        .encode(value)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final type = ViewerRuleType.fromAssociationKind(
      kind,
    ).jsonValue.toLowerCase();
    return 'builtin-$type-$encoded';
  }

  static ViewerAssociationConfig _fromVersion2(Map<String, Object?> json) {
    final rawGroups = json['groups'];
    if (rawGroups is! List) return _fromLegacyVersion2(json);
    final latest = rawGroups.whereType<Map<String, Object?>>().every(
      (group) =>
          !group.containsKey('type') && !group.containsKey('associations'),
    );
    return latest
        ? _fromTreeVersion2(rawGroups)
        : _fromGroupedLegacyVersion2(rawGroups);
  }

  static ViewerAssociationConfig _fromTreeVersion2(List<Object?> source) {
    final groups = <ViewerRuleGroup>[];
    final groupIds = <String>{};
    final ruleIds = <String>{};
    var repaired = false;
    for (final raw in source) {
      if (raw is! Map<String, Object?>) {
        repaired = true;
        continue;
      }
      try {
        final idValue = raw['id'];
        final nameValue = raw['name'];
        final enabledValue = raw['enabled'];
        final rawRules = raw['rules'];
        if (idValue is! String ||
            nameValue is! String ||
            enabledValue is! bool ||
            rawRules is! List) {
          throw const FormatException('规则组字段无效');
        }
        final id = ViewerRuleGroup.normalizeId(idValue);
        if (groupIds.contains(id)) throw FormatException('重复规则组 ID：$id');
        final rules = <ViewerRule>[];
        final groupRuleIds = <String>{};
        for (final rawRule in rawRules) {
          if (rawRule is! Map<String, Object?>) {
            repaired = true;
            continue;
          }
          try {
            final rule = ViewerRule.fromJson(rawRule);
            final subtreeIds = <String>{};
            if (!_collectRuleIds(rule, subtreeIds) ||
                subtreeIds.any(ruleIds.contains) ||
                subtreeIds.any(groupRuleIds.contains)) {
              repaired = true;
              continue;
            }
            groupRuleIds.addAll(subtreeIds);
            rules.add(rule);
          } on FormatException {
            repaired = true;
          }
        }
        final builtIn = _builtInGroupIds.contains(id);
        if ((raw['builtIn'] == true) != builtIn) repaired = true;
        final group = ViewerRuleGroup(
          id: id,
          name: nameValue,
          builtIn: builtIn,
          enabled: enabledValue,
          rules: rules,
        );
        groupIds.add(id);
        ruleIds.addAll(groupRuleIds);
        groups.add(group);
      } on FormatException {
        repaired = true;
      }
    }
    _appendMissingDefaultGroups(
      groups,
      groupIds,
      onRepair: () => repaired = true,
    );
    return ViewerAssociationConfig._(groups, needsMigration: repaired);
  }

  static ViewerAssociationConfig _fromGroupedLegacyVersion2(
    List<Object?> source,
  ) {
    final groups = <ViewerRuleGroup>[];
    final groupIds = <String>{};
    final ruleIds = <String>{};
    for (final raw in source.whereType<Map<String, Object?>>()) {
      try {
        final idValue = raw['id'];
        final nameValue = raw['name'];
        final enabledValue = raw['enabled'];
        final type = ViewerRuleType.parse(raw['type']);
        if (idValue is! String ||
            nameValue is! String ||
            enabledValue is! bool) {
          throw const FormatException('规则组字段无效');
        }
        final id = ViewerRuleGroup.normalizeId(idValue);
        ViewerRuleGroup.normalizeName(nameValue);
        if (groupIds.contains(id)) continue;
        final builtIn = _builtInGroupIds.contains(id);
        final rules = <ViewerRule>[];
        if (type == ViewerRuleType.path) {
          _decodeLegacyPathRules(raw['rules'], rules, ruleIds, managed: false);
        } else {
          _decodeLegacyAssociations(
            raw['associations'],
            type.associationKind!,
            rules,
            ruleIds,
            groupId: id,
            managed: builtIn,
          );
        }
        final group = ViewerRuleGroup(
          id: id,
          name: nameValue,
          builtIn: builtIn,
          enabled: enabledValue,
          rules: rules,
        );
        groupIds.add(id);
        groups.add(group);
      } on FormatException {
        // Keep valid groups when one legacy group is malformed.
      }
    }
    _appendMissingDefaultGroups(groups, groupIds);
    return ViewerAssociationConfig._(groups, needsMigration: true);
  }

  static ViewerAssociationConfig _fromLegacyVersion2(
    Map<String, Object?> json,
  ) {
    final groups = _defaultGroups();
    final ids = <String>{};
    _decodeLegacyPathRules(
      json['rules'],
      groups.firstWhere((group) => group.id == builtInPathGroupId).rules,
      ids,
      managed: false,
    );
    final associations = json['associations'];
    if (associations is Map<String, Object?>) {
      for (final kind in ViewerAssociationKind.values) {
        _decodeLegacyAssociations(
          associations[kind.jsonKey],
          kind,
          groups
              .firstWhere((group) => group.id == builtInGroupIdFor(kind))
              .rules,
          ids,
          groupId: builtInGroupIdFor(kind),
          managed: true,
        );
      }
    }
    return ViewerAssociationConfig._(groups, needsMigration: true);
  }

  static ViewerAssociationConfig _fromVersion1(Map<String, Object?> json) {
    final groups = _defaultGroups();
    final ruleIds = <String>{};
    final exact = <String>{};
    final associations = json['associations'];
    if (associations is Map<String, Object?>) {
      for (final kind in ViewerAssociationKind.values) {
        final rawEntries = associations[kind.jsonKey];
        if (rawEntries is! Map<String, Object?>) continue;
        final target = groups.firstWhere(
          (group) => group.id == builtInGroupIdFor(kind),
        );
        for (final entry in rawEntries.entries) {
          if (entry.value is! List) continue;
          try {
            final value = kind.normalize(entry.key);
            final id = defaultRuleId(kind, value);
            if (!ruleIds.add(id)) continue;
            target.rules.add(
              ViewerRule(
                id: id,
                managed: true,
                enabled: (entry.value! as List).isNotEmpty,
                type: ViewerRuleType.fromAssociationKind(kind),
                value: value,
                viewers: [
                  for (final viewerId
                      in (entry.value! as List).whereType<String>())
                    ViewerRuleViewer(
                      id: viewerId,
                      managed: true,
                      enabled: true,
                    ),
                ],
              ),
            );
            exact.add(id);
          } on FormatException {
            // Keep valid associations when one v1 entry is malformed.
          }
        }
      }
    }
    return ViewerAssociationConfig._(
      groups,
      needsMigration: true,
      legacyExactRuleIds: exact,
    );
  }

  static void _decodeLegacyAssociations(
    Object? source,
    ViewerAssociationKind kind,
    List<ViewerRule> target,
    Set<String> ruleIds, {
    required String groupId,
    required bool managed,
  }) {
    if (source is! Map<String, Object?>) return;
    for (final entry in source.entries) {
      if (entry.value is! Map<String, Object?>) continue;
      try {
        final raw = entry.value! as Map<String, Object?>;
        final enabled = raw['enabled'];
        final viewerOrder = raw['viewerOrder'];
        final excluded = raw['excludedViewerIds'];
        if (enabled is! bool || viewerOrder is! List || excluded is! List) {
          throw const FormatException('旧关联字段无效');
        }
        final value = kind.normalize(entry.key);
        var id = managed
            ? defaultRuleId(kind, value)
            : _legacyRuleId(groupId, kind, value);
        var suffix = 2;
        final base = id;
        while (!ruleIds.add(id)) {
          id = '$base-$suffix';
          suffix++;
        }
        final viewers = <ViewerRuleViewer>[];
        final viewerIds = <String>{};
        for (final viewerId in viewerOrder.whereType<String>()) {
          final normalized = ViewerRuleViewer.normalizeId(viewerId);
          if (viewerIds.add(normalized)) {
            viewers.add(
              ViewerRuleViewer(id: normalized, managed: managed, enabled: true),
            );
          }
        }
        for (final viewerId in excluded.whereType<String>()) {
          final normalized = ViewerRuleViewer.normalizeId(viewerId);
          if (viewerIds.add(normalized)) {
            viewers.add(
              ViewerRuleViewer(
                id: normalized,
                managed: managed,
                enabled: false,
              ),
            );
          }
        }
        target.add(
          ViewerRule(
            id: id,
            managed: managed,
            enabled: enabled,
            type: ViewerRuleType.fromAssociationKind(kind),
            value: value,
            viewers: viewers,
          ),
        );
      } on FormatException {
        // Keep valid entries when one legacy association is malformed.
      }
    }
  }

  static void _decodeLegacyPathRules(
    Object? source,
    List<ViewerRule> target,
    Set<String> ruleIds, {
    required bool managed,
  }) {
    if (source is! List) return;
    for (final raw in source.whereType<Map<String, Object?>>()) {
      try {
        final idValue = raw['id'];
        final enabled = raw['enabled'];
        final pattern = raw['pattern'];
        final viewerIds = raw['viewerIds'];
        if (idValue is! String ||
            enabled is! bool ||
            pattern is! String ||
            viewerIds is! List) {
          throw const FormatException('旧路径规则字段无效');
        }
        final id = ViewerRule.normalizeId(idValue);
        if (!ruleIds.add(id)) continue;
        target.add(
          ViewerRule(
            id: id,
            managed: managed,
            enabled: enabled,
            type: ViewerRuleType.path,
            value: pattern,
            pathMode: ViewerPathMatchMode.parse(raw['mode']),
            viewers: [
              for (final viewerId in viewerIds.whereType<String>())
                ViewerRuleViewer(id: viewerId, managed: false, enabled: true),
            ],
          ),
        );
      } on FormatException {
        // Keep valid entries when one legacy path rule is malformed.
      }
    }
  }

  void _ensureRuleIdsAvailable(ViewerRule rule) {
    final existing = allRules.map((item) => item.id).toSet();
    final incoming = <String>{};
    if (!_collectRuleIds(rule, incoming)) {
      throw ArgumentError('新增规则树中存在重复 ID');
    }
    final duplicate = incoming.where(existing.contains).firstOrNull;
    if (duplicate != null) throw ArgumentError('规则 ID 已存在：$duplicate');
  }

  ViewerRuleGroup _groupById(String id) {
    final normalized = ViewerRuleGroup.normalizeId(id);
    for (final group in _groups) {
      if (group.id == normalized) return group;
    }
    throw ArgumentError('规则组不存在：$id');
  }

  _ViewerRuleLocation _ruleLocation(String id) {
    final result = _tryRuleLocation(ViewerRule.normalizeId(id));
    if (result == null) throw ArgumentError('规则不存在：$id');
    return result;
  }

  _ViewerRuleLocation? _tryRuleLocation(String id) {
    for (final group in _groups) {
      final result = _findRule(group, group.rules, id);
      if (result != null) return result;
    }
    return null;
  }

  static _ViewerRuleLocation? _findRule(
    ViewerRuleGroup group,
    List<ViewerRule> siblings,
    String id,
  ) {
    for (var index = 0; index < siblings.length; index++) {
      final rule = siblings[index];
      if (rule.id == id) {
        return _ViewerRuleLocation(group, siblings, index, rule);
      }
      final nested = _findRule(group, rule.rules, id);
      if (nested != null) return nested;
    }
    return null;
  }

  static bool _containsRule(ViewerRule root, String id) =>
      root.rules.any((child) => child.id == id || _containsRule(child, id));

  static Iterable<ViewerRule> _flatten(Iterable<ViewerRule> source) sync* {
    for (final rule in source) {
      yield rule;
      yield* _flatten(rule.rules);
    }
  }

  static bool _collectRuleIds(ViewerRule rule, Set<String> ids) {
    if (!ids.add(rule.id)) return false;
    for (final child in rule.rules) {
      if (!_collectRuleIds(child, ids)) return false;
    }
    return true;
  }

  static String _legacyRuleId(
    String groupId,
    ViewerAssociationKind kind,
    String value,
  ) {
    final encoded = utf8
        .encode(value)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$groupId-${ViewerRuleType.fromAssociationKind(kind).jsonValue}-$encoded';
  }

  static int _compareDeclarations(
    (ViewerAssociationKind, String) a,
    (ViewerAssociationKind, String) b,
  ) {
    final kind = a.$1.index.compareTo(b.$1.index);
    if (kind != 0) return kind;
    if (a.$1 == ViewerAssociationKind.extension) {
      final specificity = b.$2.length.compareTo(a.$2.length);
      if (specificity != 0) return specificity;
    }
    if (a.$1 == ViewerAssociationKind.mimeType) {
      final wildcard = (a.$2.endsWith('/*') ? 1 : 0).compareTo(
        b.$2.endsWith('/*') ? 1 : 0,
      );
      if (wildcard != 0) return wildcard;
    }
    return a.$2.compareTo(b.$2);
  }

  static void _appendMissingDefaultGroups(
    List<ViewerRuleGroup> groups,
    Set<String> ids, {
    void Function()? onRepair,
  }) {
    for (final group in _defaultGroups()) {
      if (!ids.add(group.id)) continue;
      groups.add(group);
      onRepair?.call();
    }
  }

  static List<ViewerRuleGroup> _defaultGroups() => [
    ViewerRuleGroup(
      id: builtInPathGroupId,
      name: '路径',
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInFileNameGroupId,
      name: '文件名',
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInExtensionGroupId,
      name: '扩展名',
      builtIn: true,
      enabled: true,
    ),
    ViewerRuleGroup(
      id: builtInMimeTypeGroupId,
      name: 'MIME',
      builtIn: true,
      enabled: true,
    ),
  ];
}

class _ViewerRuleLocation {
  const _ViewerRuleLocation(this.group, this.siblings, this.index, this.rule);

  final ViewerRuleGroup group;
  final List<ViewerRule> siblings;
  final int index;
  final ViewerRule rule;
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
