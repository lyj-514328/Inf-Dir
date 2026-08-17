import 'package:path/path.dart' as p;

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

class ViewerPathRule {
  ViewerPathRule({
    required this.id,
    required this.enabled,
    required this.mode,
    required String pattern,
    required Iterable<String> viewerIds,
  }) : pattern = normalizePattern(pattern, mode: mode),
       viewerIds = List.unmodifiable(_normalizeIds(viewerIds)) {
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$').hasMatch(id)) {
      throw FormatException('无效规则 ID：$id');
    }
  }

  factory ViewerPathRule.fromJson(Map<String, Object?> json) {
    if (json['type'] != 'path') {
      throw FormatException('不支持的规则类型：${json['type']}');
    }
    final id = json['id'];
    final enabled = json['enabled'];
    final mode = ViewerPathMatchMode.parse(json['mode']);
    final pattern = json['pattern'];
    final viewerIds = json['viewerIds'];
    if (id is! String || enabled is! bool || pattern is! String) {
      throw const FormatException('路径规则字段无效');
    }
    if (viewerIds is! List) {
      throw const FormatException('路径规则 viewerIds 必须是数组');
    }
    return ViewerPathRule(
      id: id.toLowerCase(),
      enabled: enabled,
      mode: mode,
      pattern: pattern,
      viewerIds: viewerIds.whereType<String>(),
    );
  }

  final String id;
  final bool enabled;
  final ViewerPathMatchMode mode;
  final String pattern;
  final List<String> viewerIds;

  bool matches(ViewerFileFacts facts) {
    if (!enabled) return false;
    final normalizedPattern = pattern.toLowerCase();
    return switch (mode) {
      ViewerPathMatchMode.exact => facts.normalizedPath == normalizedPattern,
      ViewerPathMatchMode.glob => _globRegExp(
        normalizedPattern,
      ).hasMatch(facts.normalizedPath),
    };
  }

  ViewerPathRule copyWith({
    bool? enabled,
    ViewerPathMatchMode? mode,
    String? pattern,
    Iterable<String>? viewerIds,
  }) => ViewerPathRule(
    id: id,
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    pattern: pattern ?? this.pattern,
    viewerIds: viewerIds ?? this.viewerIds,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'enabled': enabled,
    'type': 'path',
    'mode': mode.jsonValue,
    'pattern': pattern,
    'viewerIds': viewerIds,
  };

  static String normalizePattern(
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

  static List<String> _normalizeIds(Iterable<String> ids) => ids
      .map((id) => id.trim().toLowerCase())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

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
