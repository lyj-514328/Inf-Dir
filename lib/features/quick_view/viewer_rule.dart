import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';
import 'viewer_file_facts.dart';

enum ViewerPathMatchMode {
  exact('exact', '精确路径'),
  glob('glob', 'Glob');

  const ViewerPathMatchMode(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  static ViewerPathMatchMode parse(Object? value) => switch (value) {
    'exact' => ViewerPathMatchMode.exact,
    'glob' => ViewerPathMatchMode.glob,
    _ => throw FormatException('不支持的路径匹配方式：$value'),
  };
}

enum ViewerRuleType {
  path('path', '路径'),
  fileName('fileName', '文件名'),
  extension('extension', '扩展名'),
  mimeType('mimeType', 'MIME');

  const ViewerRuleType(this.jsonValue, this.label);

  final String jsonValue;
  final String label;

  ViewerAssociationKind? get associationKind => switch (this) {
    ViewerRuleType.path => null,
    ViewerRuleType.fileName => ViewerAssociationKind.fileName,
    ViewerRuleType.extension => ViewerAssociationKind.extension,
    ViewerRuleType.mimeType => ViewerAssociationKind.mimeType,
  };

  static ViewerRuleType parse(Object? value) => switch (value) {
    'path' => ViewerRuleType.path,
    'fileName' => ViewerRuleType.fileName,
    'extension' => ViewerRuleType.extension,
    'mimeType' => ViewerRuleType.mimeType,
    _ => throw FormatException('不支持的规则类型：$value'),
  };

  static ViewerRuleType fromAssociationKind(ViewerAssociationKind kind) =>
      switch (kind) {
        ViewerAssociationKind.fileName => ViewerRuleType.fileName,
        ViewerAssociationKind.extension => ViewerRuleType.extension,
        ViewerAssociationKind.mimeType => ViewerRuleType.mimeType,
      };
}

class ViewerRuleViewer {
  ViewerRuleViewer({
    required String id,
    required this.managed,
    required this.enabled,
  }) : id = normalizeId(id);

  factory ViewerRuleViewer.fromJson(Object? value) {
    if (value is String) {
      return ViewerRuleViewer(id: value, managed: false, enabled: true);
    }
    if (value is! Map<String, Object?>) {
      throw const FormatException('Viewer 条目必须是字符串或对象');
    }
    final id = value['id'];
    final enabled = value['enabled'];
    if (id is! String || enabled is! bool) {
      throw const FormatException('Viewer 条目字段无效');
    }
    // managed 已退役：兼容读取旧配置，新配置不再使用。
    return ViewerRuleViewer(id: id, managed: value['managed'] == true, enabled: enabled);
  }

  final String id;
  final bool managed;
  final bool enabled;

  ViewerRuleViewer copyWith({bool? enabled, bool? managed}) => ViewerRuleViewer(
    id: id,
    managed: managed ?? this.managed,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'enabled': enabled,
  };

  static String normalizeId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(normalized)) {
      throw FormatException('无效 Viewer ID：$value');
    }
    return normalized;
  }
}

class ViewerRule {
  ViewerRule({
    required String id,
    required this.managed,
    required this.enabled,
    required this.type,
    required String value,
    this.pathMode,
    Iterable<ViewerRule> rules = const [],
    Iterable<ViewerRuleViewer> viewers = const [],
  }) : id = normalizeId(id),
       value = normalizeValue(type, value, pathMode: pathMode),
       rules = List.of(rules),
       viewers = List.of(viewers) {
    if (type == ViewerRuleType.path && pathMode == null) {
      throw const FormatException('路径规则缺少匹配方式');
    }
    if (type != ViewerRuleType.path && pathMode != null) {
      throw const FormatException('只有路径规则可以设置匹配方式');
    }
    _validateUniqueViewerIds(this.viewers);
  }

  factory ViewerRule.fromJson(Map<String, Object?> json, {int depth = 0}) {
    if (depth > 16) throw const FormatException('规则嵌套层级超过限制');
    final id = json['id'];
    final enabled = json['enabled'];
    final type = ViewerRuleType.parse(json['type']);
    final value = json['value'];
    if (id is! String || enabled is! bool || value is! String) {
      throw const FormatException('规则字段无效');
    }
    final rawRules = json['rules'];
    final rawViewers = json['viewers'];
    if (rawRules is! List || rawViewers is! List) {
      throw const FormatException('规则的 rules 和 viewers 必须是数组');
    }
    final pathMode = type == ViewerRuleType.path
        ? ViewerPathMatchMode.parse(json['mode'])
        : null;
    return ViewerRule(
      id: id,
      // managed 已退役：兼容读取旧配置，新配置不再使用。
      managed: json['managed'] == true,
      enabled: enabled,
      type: type,
      value: value,
      pathMode: pathMode,
      rules: [
        for (final raw in rawRules)
          if (raw is Map<String, Object?>)
            ViewerRule.fromJson(raw, depth: depth + 1),
      ],
      viewers: [for (final raw in rawViewers) ViewerRuleViewer.fromJson(raw)],
    );
  }

  final String id;
  final bool managed;
  final bool enabled;
  final ViewerRuleType type;
  final String value;
  final ViewerPathMatchMode? pathMode;
  final List<ViewerRule> rules;
  final List<ViewerRuleViewer> viewers;

  bool matches(ViewerFileFacts facts) {
    if (!enabled) return false;
    return switch (type) {
      ViewerRuleType.path => switch (pathMode!) {
        ViewerPathMatchMode.exact =>
          facts.normalizedPath == value.toLowerCase(),
        ViewerPathMatchMode.glob => _globRegExp(
          value.toLowerCase(),
        ).hasMatch(facts.normalizedPath),
      },
      ViewerRuleType.fileName => facts.fileName == value,
      ViewerRuleType.extension => facts.suffixes.contains(value),
      ViewerRuleType.mimeType =>
        facts.mimeType != null && _matchesMime(value, facts.mimeType!),
    };
  }

  ViewerRule copyWith({
    bool? managed,
    bool? enabled,
    ViewerRuleType? type,
    String? value,
    ViewerPathMatchMode? pathMode,
    Iterable<ViewerRule>? rules,
    Iterable<ViewerRuleViewer>? viewers,
  }) {
    final nextType = type ?? this.type;
    return ViewerRule(
      id: id,
      managed: managed ?? this.managed,
      enabled: enabled ?? this.enabled,
      type: nextType,
      value: value ?? this.value,
      pathMode: nextType == ViewerRuleType.path
          ? (pathMode ?? this.pathMode ?? ViewerPathMatchMode.glob)
          : null,
      rules: rules ?? this.rules,
      viewers: viewers ?? this.viewers,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'enabled': enabled,
    'type': type.jsonValue,
    'value': value,
    if (type == ViewerRuleType.path) 'mode': pathMode!.jsonValue,
    'rules': [for (final rule in rules) rule.toJson()],
    'viewers': [for (final viewer in viewers) viewer.toJson()],
  };

  static String normalizeId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(normalized)) {
      throw FormatException('无效规则 ID：$value');
    }
    return normalized;
  }

  static String normalizeValue(
    ViewerRuleType type,
    String value, {
    ViewerPathMatchMode? pathMode,
  }) => switch (type) {
    ViewerRuleType.path => normalizePath(
      value,
      mode: pathMode ?? ViewerPathMatchMode.glob,
    ),
    final type => type.associationKind!.normalize(value),
  };

  static String normalizePath(
    String value, {
    required ViewerPathMatchMode mode,
  }) {
    final trimmed = value.trim().replaceAll('/', r'\');
    if (trimmed.isEmpty || !p.windows.isAbsolute(trimmed)) {
      throw FormatException('路径规则必须使用绝对路径：$value');
    }
    if (mode == ViewerPathMatchMode.exact &&
        trimmed.contains(RegExp(r'[*?]'))) {
      throw const FormatException('精确路径不能包含 * 或 ?');
    }
    return p.windows.normalize(trimmed);
  }

  static bool _matchesMime(String pattern, String mime) {
    if (!pattern.endsWith('/*')) return pattern == mime;
    return mime.startsWith(pattern.substring(0, pattern.length - 1));
  }

  static void _validateUniqueViewerIds(List<ViewerRuleViewer> viewers) {
    final ids = <String>{};
    for (final viewer in viewers) {
      if (!ids.add(viewer.id)) {
        throw FormatException('规则中存在重复 Viewer：${viewer.id}');
      }
    }
  }

  static RegExp _globRegExp(String pattern) {
    final buffer = StringBuffer('^');
    const separator = r'\';
    final escapedSeparator = RegExp.escape(separator);
    var index = 0;
    while (index < pattern.length) {
      final character = pattern[index];
      if (character == '*') {
        final recursive =
            index + 1 < pattern.length && pattern[index + 1] == '*';
        if (recursive) {
          index += 2;
          if (index < pattern.length && pattern[index] == separator) {
            buffer.write('(?:.*$escapedSeparator)?');
            index++;
          } else {
            buffer.write('.*');
          }
          continue;
        }
        buffer.write('[^$escapedSeparator]*');
      } else if (character == '?') {
        buffer.write('[^$escapedSeparator]');
      } else if (character == separator) {
        buffer.write(escapedSeparator);
      } else {
        buffer.write(RegExp.escape(character));
      }
      index++;
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }
}
