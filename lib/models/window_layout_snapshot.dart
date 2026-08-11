import 'layout_node.dart';

class PaneLayoutSnapshot {
  const PaneLayoutSnapshot({
    required this.currentPath,
    required this.tabs,
    required this.activeTabIndex,
    required this.backStack,
    required this.forwardStack,
    required this.sortColumn,
    required this.sortAscending,
    this.groupBy = 'none',
    this.groupAscending = true,
    required this.filterQuery,
    required this.entryFilter,
    this.filterMode = 'keyword',
    this.caseSensitive = false,
    required this.viewMode,
    this.showDetailsPane = false,
    this.showPreviewPane = false,
    required this.columnWidths,
  });

  factory PaneLayoutSnapshot.fromJson(Map<String, Object?> json) {
    final tabs = _stringList(json['tabs'], 'pane.tabs', requireNonEmpty: true);
    final activeTabIndex = _intValue(
      json['activeTabIndex'],
      'pane.activeTabIndex',
    );
    if (activeTabIndex < 0 || activeTabIndex >= tabs.length) {
      throw const FormatException('pane.activeTabIndex 超出标签页范围');
    }

    final currentPath = _stringValue(json['currentPath'], 'pane.currentPath');
    if (tabs[activeTabIndex] != currentPath) {
      throw const FormatException('pane.currentPath 与激活标签页不一致');
    }

    final sortColumn = _enumValue(json['sortColumn'], 'pane.sortColumn', const {
      'name',
      'dateModified',
      'type',
      'size',
    });
    final entryFilter = _enumValue(
      json['entryFilter'],
      'pane.entryFilter',
      const {'all', 'folders', 'files', 'images', 'documents'},
    );
    final viewMode = _enumValue(json['viewMode'], 'pane.viewMode', const {
      'details',
      'list',
      'compact',
      'extraLargeIcons',
      'largeIcons',
      'mediumIcons',
      'smallIcons',
      'tiles',
      'content',
    });

    final rawWidths = _listValue(json['columnWidths'], 'pane.columnWidths');
    if (rawWidths.length != 4) {
      throw const FormatException('pane.columnWidths 必须包含四列');
    }
    final columnWidths = <double>[];
    for (final width in rawWidths) {
      final value = _doubleValue(width, 'pane.columnWidths');
      if (value <= 0) {
        throw const FormatException('pane.columnWidths 必须为正数');
      }
      columnWidths.add(value);
    }

    return PaneLayoutSnapshot(
      currentPath: currentPath,
      tabs: tabs,
      activeTabIndex: activeTabIndex,
      backStack: _stringList(json['backStack'], 'pane.backStack'),
      forwardStack: _stringList(json['forwardStack'], 'pane.forwardStack'),
      sortColumn: sortColumn,
      sortAscending: _boolValue(json['sortAscending'], 'pane.sortAscending'),
      groupBy: switch (json['groupBy']) {
        'name' => 'name',
        'dateModified' => 'dateModified',
        'type' => 'type',
        'size' => 'size',
        _ => 'none',
      },
      groupAscending: json['groupAscending'] != false,
      filterQuery: _stringValue(
        json['filterQuery'],
        'pane.filterQuery',
        allowEmpty: true,
      ),
      entryFilter: entryFilter,
      filterMode: switch (json['filterMode']) {
        'glob' => 'glob',
        'regex' => 'regex',
        _ => 'keyword',
      },
      caseSensitive: json['caseSensitive'] == true,
      viewMode: viewMode,
      showDetailsPane: json['showDetailsPane'] == true,
      showPreviewPane: json['showPreviewPane'] == true,
      columnWidths: List.unmodifiable(columnWidths),
    );
  }

  final String currentPath;
  final List<String> tabs;
  final int activeTabIndex;
  final List<String> backStack;
  final List<String> forwardStack;
  final String sortColumn;
  final bool sortAscending;
  final String groupBy;
  final bool groupAscending;
  final String filterQuery;
  final String entryFilter;
  final String filterMode;
  final bool caseSensitive;
  final String viewMode;
  final bool showDetailsPane;
  final bool showPreviewPane;
  final List<double> columnWidths;

  Map<String, Object?> toJson() => {
    'currentPath': currentPath,
    'tabs': tabs,
    'activeTabIndex': activeTabIndex,
    'backStack': backStack,
    'forwardStack': forwardStack,
    'sortColumn': sortColumn,
    'sortAscending': sortAscending,
    'groupBy': groupBy,
    'groupAscending': groupAscending,
    'filterQuery': filterQuery,
    'entryFilter': entryFilter,
    'filterMode': filterMode,
    'caseSensitive': caseSensitive,
    'viewMode': viewMode,
    'showDetailsPane': showDetailsPane,
    'showPreviewPane': showPreviewPane,
    'columnWidths': columnWidths,
  };
}

class LayoutNodeSnapshot {
  const LayoutNodeSnapshot({
    required this.id,
    required this.type,
    required this.layout,
    required this.percent,
    required this.children,
    this.paneId,
    this.label,
  });

  factory LayoutNodeSnapshot.fromJson(Map<String, Object?> json) {
    final typeName = _enumValue(
      json['type'],
      'node.type',
      NodeType.values.map((value) => value.name).toSet(),
    );
    final layoutName = _enumValue(
      json['layout'],
      'node.layout',
      SplitDirection.values.map((value) => value.name).toSet(),
    );
    final children = _listValue(json['children'], 'node.children')
        .map(
          (child) =>
              LayoutNodeSnapshot.fromJson(_mapValue(child, 'node.children[]')),
        )
        .toList(growable: false);

    return LayoutNodeSnapshot(
      id: _stringValue(json['id'], 'node.id'),
      type: NodeType.values.byName(typeName),
      layout: SplitDirection.values.byName(layoutName),
      percent: _doubleValue(json['percent'], 'node.percent'),
      paneId: _optionalString(json['paneId'], 'node.paneId'),
      label: _optionalString(json['label'], 'node.label'),
      children: children,
    );
  }

  final String id;
  final NodeType type;
  final SplitDirection layout;
  final double percent;
  final String? paneId;
  final String? label;
  final List<LayoutNodeSnapshot> children;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'layout': layout.name,
    'percent': percent,
    if (paneId != null) 'paneId': paneId,
    if (label != null) 'label': label,
    'children': children.map((child) => child.toJson()).toList(),
  };
}

class WindowLayoutSnapshot {
  static const int currentSchemaVersion = 1;

  const WindowLayoutSnapshot({
    required this.workspaces,
    required this.activeWorkspaceIndex,
    required this.focusedNodeId,
    required this.nodeIdCounter,
    required this.nextPaneCounter,
    required this.sidebarWidth,
    required this.panes,
  });

  factory WindowLayoutSnapshot.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != currentSchemaVersion) {
      throw FormatException('不支持的窗口布局版本：${json['schemaVersion']}');
    }

    final workspaces = _listValue(json['workspaces'], 'workspaces')
        .map(
          (workspace) =>
              LayoutNodeSnapshot.fromJson(_mapValue(workspace, 'workspaces[]')),
        )
        .toList(growable: false);
    if (workspaces.isEmpty) {
      throw const FormatException('窗口布局至少需要一个 workspace');
    }

    final rawPanes = _mapValue(json['panes'], 'panes');
    final panes = <String, PaneLayoutSnapshot>{};
    for (final entry in rawPanes.entries) {
      panes[entry.key] = PaneLayoutSnapshot.fromJson(
        _mapValue(entry.value, 'panes.${entry.key}'),
      );
    }

    final activeWorkspaceIndex = _intValue(
      json['activeWorkspaceIndex'],
      'activeWorkspaceIndex',
    );
    if (activeWorkspaceIndex < 0 || activeWorkspaceIndex >= workspaces.length) {
      throw const FormatException('activeWorkspaceIndex 超出范围');
    }

    final snapshot = WindowLayoutSnapshot(
      workspaces: workspaces,
      activeWorkspaceIndex: activeWorkspaceIndex,
      focusedNodeId: _stringValue(json['focusedNodeId'], 'focusedNodeId'),
      nodeIdCounter: _intValue(json['nodeIdCounter'], 'nodeIdCounter'),
      nextPaneCounter: _intValue(json['nextPaneCounter'], 'nextPaneCounter'),
      sidebarWidth: _doubleValue(json['sidebarWidth'], 'sidebarWidth'),
      panes: Map.unmodifiable(panes),
    );
    snapshot._validate();
    return snapshot;
  }

  final List<LayoutNodeSnapshot> workspaces;
  final int activeWorkspaceIndex;
  final String focusedNodeId;
  final int nodeIdCounter;
  final int nextPaneCounter;
  final double sidebarWidth;
  final Map<String, PaneLayoutSnapshot> panes;

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'activeWorkspaceIndex': activeWorkspaceIndex,
    'focusedNodeId': focusedNodeId,
    'nodeIdCounter': nodeIdCounter,
    'nextPaneCounter': nextPaneCounter,
    'sidebarWidth': sidebarWidth,
    'workspaces': workspaces.map((workspace) => workspace.toJson()).toList(),
    'panes': {
      for (final entry in panes.entries) entry.key: entry.value.toJson(),
    },
  };

  void _validate() {
    if (nodeIdCounter < 0 || nextPaneCounter < 0) {
      throw const FormatException('布局 ID 计数器不能为负数');
    }
    if (sidebarWidth < 150) {
      throw const FormatException('sidebarWidth 小于允许值');
    }

    final nodeIds = <String>{};
    final paneIds = <String>{};
    var maxNodeCounter = 0;
    var maxPaneIndex = -1;

    void visit(LayoutNodeSnapshot node, {required bool isRoot}) {
      if (!nodeIds.add(node.id)) {
        throw FormatException('布局节点 ID 重复：${node.id}');
      }
      if (!node.percent.isFinite || node.percent < 0 || node.percent > 1) {
        throw FormatException('布局节点比例无效：${node.id}');
      }

      final nodeMatch = RegExp(r'^n(\d+)$').firstMatch(node.id);
      if (nodeMatch != null) {
        final value = int.parse(nodeMatch.group(1)!);
        if (value > maxNodeCounter) maxNodeCounter = value;
      }

      if (isRoot != (node.type == NodeType.workspace)) {
        throw FormatException('workspace 节点层级无效：${node.id}');
      }
      if (node.type == NodeType.pane) {
        if (node.paneId == null || node.children.isNotEmpty) {
          throw FormatException('pane 节点结构无效：${node.id}');
        }
        if (!paneIds.add(node.paneId!)) {
          throw FormatException('pane ID 重复：${node.paneId}');
        }
        final paneMatch = RegExp(r'^pane_(\d+)$').firstMatch(node.paneId!);
        if (paneMatch != null) {
          final value = int.parse(paneMatch.group(1)!);
          if (value > maxPaneIndex) maxPaneIndex = value;
        }
      } else {
        if (node.paneId != null || node.children.isEmpty) {
          throw FormatException('容器节点结构无效：${node.id}');
        }
        if (node.type == NodeType.workspace &&
            (node.label == null || node.label!.isEmpty)) {
          throw FormatException('workspace 缺少名称：${node.id}');
        }
        if (node.type == NodeType.split && node.children.length < 2) {
          throw FormatException('split 节点至少需要两个子节点：${node.id}');
        }
      }
      for (final child in node.children) {
        visit(child, isRoot: false);
      }
    }

    for (final workspace in workspaces) {
      visit(workspace, isRoot: true);
    }

    if (paneIds.length != panes.length || !paneIds.containsAll(panes.keys)) {
      throw const FormatException('布局树与 pane 快照不一致');
    }
    if (nodeIdCounter < maxNodeCounter || nextPaneCounter <= maxPaneIndex) {
      throw const FormatException('布局 ID 计数器落后于现有节点');
    }

    final activeNodeIds = <String>{};
    void collectActive(LayoutNodeSnapshot node) {
      activeNodeIds.add(node.id);
      for (final child in node.children) {
        collectActive(child);
      }
    }

    collectActive(workspaces[activeWorkspaceIndex]);
    if (!activeNodeIds.contains(focusedNodeId)) {
      throw const FormatException('焦点节点不属于激活 workspace');
    }
  }
}

Map<String, Object?> _mapValue(Object? value, String name) {
  if (value is! Map) throw FormatException('$name 必须是对象');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('$name 的键必须是字符串');
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _listValue(Object? value, String name) {
  if (value is! List) throw FormatException('$name 必须是数组');
  return List<Object?>.from(value);
}

String _stringValue(Object? value, String name, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException('$name 必须是${allowEmpty ? '' : '非空'}字符串');
  }
  return value;
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  return _stringValue(value, name);
}

List<String> _stringList(
  Object? value,
  String name, {
  bool requireNonEmpty = false,
}) {
  final raw = _listValue(value, name);
  if (requireNonEmpty && raw.isEmpty) {
    throw FormatException('$name 不能为空');
  }
  return List.unmodifiable(
    raw.map((item) => _stringValue(item, '$name[]')).toList(),
  );
}

int _intValue(Object? value, String name) {
  if (value is! int) throw FormatException('$name 必须是整数');
  return value;
}

double _doubleValue(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$name 必须是有限数值');
  }
  return value.toDouble();
}

bool _boolValue(Object? value, String name) {
  if (value is! bool) throw FormatException('$name 必须是布尔值');
  return value;
}

String _enumValue(Object? value, String name, Set<String> allowed) {
  final result = _stringValue(value, name);
  if (!allowed.contains(result)) throw FormatException('$name 的枚举值无效');
  return result;
}
