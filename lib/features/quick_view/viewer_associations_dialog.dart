import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/app_theme.dart';
import 'plugin_manifest.dart';
import 'quick_view_service.dart';
import 'viewer_association_config.dart';
import 'viewer_rule.dart';

Future<void> showViewerAssociationsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ViewerAssociationsDialog(),
  );
}

class ViewerAssociationsDialog extends StatelessWidget {
  const ViewerAssociationsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: (viewport.width - 48).clamp(620.0, 1040.0),
        height: (viewport.height - 48).clamp(420.0, 680.0),
        child: Column(
          children: [
            _DialogHeader(onClose: () => Navigator.of(context).pop()),
            const Expanded(child: ViewerAssociationsView()),
          ],
        ),
      ),
    );
  }
}

class ViewerAssociationsView extends StatefulWidget {
  const ViewerAssociationsView({super.key});

  @override
  State<ViewerAssociationsView> createState() => _ViewerAssociationsViewState();
}

class _ViewerAssociationsViewState extends State<ViewerAssociationsView> {
  String? _selectedGroupId;
  String? _selectedRuleId;
  final Set<String> _collapsedRuleIds = {};
  double _groupsWidth = 190;
  double _rulesWidth = 310;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<QuickViewService>();
    final groups = service.ruleGroups;
    final activeGroup = groups.firstWhere(
      (group) => group.id == _selectedGroupId,
      orElse: () => groups.first,
    );
    _selectedGroupId = activeGroup.id;

    final flattened = _flattenRules(activeGroup.rules, _collapsedRuleIds);
    final selectedRule = flattened
        .where((entry) => entry.rule.id == _selectedRuleId)
        .firstOrNull
        ?.rule;
    if (_selectedRuleId != null && selectedRule == null) {
      _selectedRuleId = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final groupsMax = _columnMaxWidth(
          constraints.maxWidth,
          minimumTrailingWidth: 520,
        );
        final groupsWidth = _groupsWidth
            .clamp(_minimumColumnWidth, groupsMax)
            .toDouble();
        final rulesMax = _columnMaxWidth(
          constraints.maxWidth - groupsWidth - _columnSplitterWidth,
          minimumTrailingWidth: 240,
        );
        final rulesWidth = _rulesWidth
            .clamp(_minimumColumnWidth, rulesMax)
            .toDouble();

        return Row(
          children: [
            SizedBox(
              key: const ValueKey('viewer-rule-groups-column'),
              width: groupsWidth,
              child: _GroupsColumn(
                groups: groups,
                selectedId: activeGroup.id,
                hasIssues: service.issues.isNotEmpty,
                issueMessage: service.issues
                    .map((issue) => '${issue.message}\n${issue.path}')
                    .join('\n\n'),
                onSelect: (id) => setState(() {
                  _selectedGroupId = id;
                  _selectedRuleId = null;
                }),
                onAdd: () => _addGroup(context, service),
                onEdit: () => _editGroup(context, service, activeGroup),
                onDelete: activeGroup.builtIn
                    ? null
                    : () => _deleteGroup(context, service, activeGroup),
                onReload: service.reload,
                onReorder: service.reorderRuleGroups,
                onRuleDropped: (ruleId, groupId) {
                  service.moveRuleToGroup(ruleId, groupId);
                  setState(() {
                    _selectedGroupId = groupId;
                    _selectedRuleId = ruleId;
                  });
                },
                onEnabled: service.setRuleGroupEnabled,
              ),
            ),
            _ColumnSplitter(
              key: const ValueKey('viewer-rule-groups-splitter'),
              width: groupsWidth,
              maxWidth: groupsMax,
              onWidthChanged: (value) => setState(() => _groupsWidth = value),
            ),
            SizedBox(
              key: const ValueKey('viewer-rules-column'),
              width: rulesWidth,
              child: _RulesColumn(
                entries: flattened,
                selectedRuleId: selectedRule?.id,
                onSelect: (id) => setState(() => _selectedRuleId = id),
                onToggleCollapsed: (id) => setState(() {
                  if (!_collapsedRuleIds.add(id)) {
                    _collapsedRuleIds.remove(id);
                  }
                }),
                onAdd: () => _addRule(context, service, activeGroup),
                onAddChild: selectedRule == null
                    ? null
                    : () => _addRule(
                        context,
                        service,
                        activeGroup,
                        parent: selectedRule,
                      ),
                onEdit: selectedRule == null || selectedRule.managed
                    ? null
                    : () => _editRule(context, service, selectedRule),
                onDelete: selectedRule == null || selectedRule.managed
                    ? null
                    : () => _deleteRule(context, service, selectedRule),
                onEnabled: service.setRuleEnabled,
                canDrop: (draggedId, targetId) =>
                    _canMoveRule(service, draggedId, targetId),
                onMoveBefore: (draggedId, targetId) {
                  service.moveRuleBefore(draggedId, targetId);
                  setState(() => _selectedRuleId = draggedId);
                },
                onMoveInto: (draggedId, targetId) {
                  service.moveRuleInto(draggedId, targetId);
                  setState(() {
                    _selectedRuleId = draggedId;
                    _collapsedRuleIds.remove(targetId);
                  });
                },
                onMoveToRoot: (id) {
                  service.moveRuleToGroup(id, activeGroup.id);
                  setState(() => _selectedRuleId = id);
                },
              ),
            ),
            _ColumnSplitter(
              key: const ValueKey('viewer-rules-splitter'),
              width: rulesWidth,
              maxWidth: rulesMax,
              onWidthChanged: (value) => setState(() => _rulesWidth = value),
            ),
            Expanded(
              child: _ViewersColumn(
                rule: selectedRule,
                service: service,
                onAdd: selectedRule == null
                    ? null
                    : () => _addViewer(context, service, selectedRule),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _canMoveRule(
    QuickViewService service,
    String draggedId,
    String targetId,
  ) {
    if (draggedId == targetId) return false;
    final dragged = service.rule(draggedId);
    return !_containsRule(dragged, targetId);
  }

  Future<void> _addGroup(BuildContext context, QuickViewService service) async {
    final name = await _showGroupDialog(context);
    if (name == null || !mounted) return;
    final group = service.addRuleGroup(name: name);
    setState(() {
      _selectedGroupId = group.id;
      _selectedRuleId = null;
    });
  }

  Future<void> _editGroup(
    BuildContext context,
    QuickViewService service,
    ViewerRuleGroup group,
  ) async {
    final name = await _showGroupDialog(context, initialName: group.name);
    if (name != null && mounted) service.renameRuleGroup(group.id, name);
  }

  Future<void> _deleteGroup(
    BuildContext context,
    QuickViewService service,
    ViewerRuleGroup group,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: '删除规则组',
      message: '规则组“${group.name}”及其全部规则将被删除。',
    );
    if (!confirmed || !mounted) return;
    service.removeRuleGroup(group.id);
    setState(() {
      _selectedGroupId = null;
      _selectedRuleId = null;
    });
  }

  Future<void> _addRule(
    BuildContext context,
    QuickViewService service,
    ViewerRuleGroup group, {
    ViewerRule? parent,
  }) async {
    final draft = await _showRuleDialog(context);
    if (draft == null || !mounted) return;
    final rule = service.addRule(
      groupId: group.id,
      parentRuleId: parent?.id,
      type: draft.type,
      value: draft.value,
      pathMode: draft.pathMode,
    );
    setState(() {
      _selectedRuleId = rule.id;
      if (parent != null) _collapsedRuleIds.remove(parent.id);
    });
  }

  Future<void> _editRule(
    BuildContext context,
    QuickViewService service,
    ViewerRule rule,
  ) async {
    final draft = await _showRuleDialog(context, initialRule: rule);
    if (draft == null || !mounted) return;
    service.updateRule(
      rule.id,
      type: draft.type,
      value: draft.value,
      pathMode: draft.pathMode,
    );
  }

  Future<void> _deleteRule(
    BuildContext context,
    QuickViewService service,
    ViewerRule rule,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: '删除规则',
      message: '规则“${rule.value}”及其全部子规则将被删除。',
    );
    if (!confirmed || !mounted) return;
    service.removeRule(rule.id);
    setState(() => _selectedRuleId = null);
  }

  Future<void> _addViewer(
    BuildContext context,
    QuickViewService service,
    ViewerRule rule,
  ) async {
    final available = service.availablePluginsForRule(rule);
    final plugin = await showDialog<ViewerPlugin>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加 Viewer'),
        children: [
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Text('没有可添加的 Viewer'),
            ),
          for (final item in available)
            SimpleDialogOption(
              key: ValueKey('available-viewer-${item.manifest.id}'),
              onPressed: () => Navigator.of(context).pop(item),
              child: Text(item.manifest.name),
            ),
        ],
      ),
    );
    if (plugin != null && mounted) {
      service.addViewerToRule(rule.id, plugin.manifest.id);
    }
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Viewer 关联',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _IconAction(icon: Icons.close, tooltip: '关闭', onPressed: onClose),
        ],
      ),
    );
  }
}

class _GroupsColumn extends StatelessWidget {
  const _GroupsColumn({
    required this.groups,
    required this.selectedId,
    required this.hasIssues,
    required this.issueMessage,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onReload,
    required this.onReorder,
    required this.onRuleDropped,
    required this.onEnabled,
  });

  final List<ViewerRuleGroup> groups;
  final String selectedId;
  final bool hasIssues;
  final String issueMessage;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onReload;
  final ReorderCallback onReorder;
  final void Function(String ruleId, String groupId) onRuleDropped;
  final void Function(String id, bool enabled) onEnabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.surface,
      child: Column(
        children: [
          _ColumnToolbar(
            title: '规则组',
            actions: [
              _IconAction(icon: Icons.add, tooltip: '新建规则组', onPressed: onAdd),
              _IconAction(icon: Icons.edit, tooltip: '重命名', onPressed: onEdit),
              _IconAction(
                icon: Icons.delete_outline,
                tooltip: '删除规则组',
                onPressed: onDelete,
              ),
              if (hasIssues)
                _IconAction(
                  icon: Icons.warning_amber,
                  tooltip: issueMessage,
                  onPressed: null,
                ),
              _IconAction(
                icon: Icons.refresh,
                tooltip: '重新扫描插件',
                onPressed: onReload,
              ),
            ],
          ),
          Expanded(
            child: ReorderableListView.builder(
              key: const ValueKey('viewer-rule-groups-list'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              buildDefaultDragHandles: false,
              itemExtent: 52,
              itemCount: groups.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                onReorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final group = groups[index];
                return DragTarget<_RuleDragData>(
                  key: ValueKey('viewer-rule-group-${group.id}'),
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (details) =>
                      onRuleDropped(details.data.ruleId, group.id),
                  builder: (context, candidates, rejected) => _GroupRow(
                    group: group,
                    index: index,
                    selected: group.id == selectedId,
                    acceptingRule: candidates.isNotEmpty,
                    onSelected: () => onSelect(group.id),
                    onEnabled: (value) => onEnabled(group.id, value),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.index,
    required this.selected,
    required this.acceptingRule,
    required this.onSelected,
    required this.onEnabled,
  });

  final ViewerRuleGroup group;
  final int index;
  final bool selected;
  final bool acceptingRule;
  final VoidCallback onSelected;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selectedColor = acceptingRule ? c.accentSubtle : c.selectedInactive;
    return Material(
      color: selected || acceptingRule ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: Row(
          children: [
            SizedBox(
              width: 3,
              height: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Icon(Icons.drag_indicator, size: AppMetrics.iconMd),
              ),
            ),
            Checkbox(
              value: group.enabled,
              onChanged: (value) => onEnabled(value ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${group.rules.length} 条顶层规则',
                    style: TextStyle(color: c.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (group.builtIn)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: AppMetrics.iconSm,
                  color: c.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RulesColumn extends StatelessWidget {
  const _RulesColumn({
    required this.entries,
    required this.selectedRuleId,
    required this.onSelect,
    required this.onToggleCollapsed,
    required this.onAdd,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
    required this.onEnabled,
    required this.canDrop,
    required this.onMoveBefore,
    required this.onMoveInto,
    required this.onMoveToRoot,
  });

  final List<_RuleTreeEntry> entries;
  final String? selectedRuleId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggleCollapsed;
  final VoidCallback onAdd;
  final VoidCallback? onAddChild;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(String id, bool enabled) onEnabled;
  final bool Function(String draggedId, String targetId) canDrop;
  final void Function(String draggedId, String targetId) onMoveBefore;
  final void Function(String draggedId, String targetId) onMoveInto;
  final ValueChanged<String> onMoveToRoot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.surface,
      child: Column(
        children: [
          _ColumnToolbar(
            title: '规则',
            actions: [
              _IconAction(icon: Icons.add, tooltip: '新建规则', onPressed: onAdd),
              _IconAction(
                icon: Icons.subdirectory_arrow_right,
                tooltip: '添加子规则',
                onPressed: onAddChild,
              ),
              _IconAction(icon: Icons.edit, tooltip: '编辑规则', onPressed: onEdit),
              _IconAction(
                icon: Icons.delete_outline,
                tooltip: '删除规则',
                onPressed: onDelete,
              ),
            ],
          ),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyState(
                    icon: Icons.account_tree_outlined,
                    text: '此规则组中还没有规则',
                  )
                : ListView.builder(
                    key: const ValueKey('viewer-rules-tree'),
                    itemCount: entries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == entries.length) {
                        return _RootRuleDropTarget(onAccept: onMoveToRoot);
                      }
                      final entry = entries[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RuleInsertTarget(
                            targetId: entry.rule.id,
                            canDrop: canDrop,
                            onAccept: onMoveBefore,
                          ),
                          _RuleTreeRow(
                            key: ValueKey('viewer-rule-${entry.rule.id}'),
                            entry: entry,
                            selected: entry.rule.id == selectedRuleId,
                            canDrop: canDrop,
                            onSelected: () => onSelect(entry.rule.id),
                            onEnabled: (value) =>
                                onEnabled(entry.rule.id, value),
                            onToggleCollapsed: () =>
                                onToggleCollapsed(entry.rule.id),
                            onAcceptChild: (draggedId) =>
                                onMoveInto(draggedId, entry.rule.id),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RuleTreeRow extends StatelessWidget {
  const _RuleTreeRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.canDrop,
    required this.onSelected,
    required this.onEnabled,
    required this.onToggleCollapsed,
    required this.onAcceptChild,
  });

  final _RuleTreeEntry entry;
  final bool selected;
  final bool Function(String draggedId, String targetId) canDrop;
  final VoidCallback onSelected;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onAcceptChild;

  @override
  Widget build(BuildContext context) {
    final rule = entry.rule;
    final c = context.colors;
    return DragTarget<_RuleDragData>(
      onWillAcceptWithDetails: (details) =>
          canDrop(details.data.ruleId, rule.id),
      onAcceptWithDetails: (details) => onAcceptChild(details.data.ruleId),
      builder: (context, candidates, rejected) {
        final accepting = candidates.isNotEmpty;
        return Material(
          color: accepting
              ? c.accentSubtle
              : selected
              ? c.selectedInactive
              : Colors.transparent,
          child: InkWell(
            onTap: onSelected,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  SizedBox(width: entry.depth * 16.0),
                  Draggable<_RuleDragData>(
                    data: _RuleDragData(rule.id),
                    feedback: Material(
                      color: c.surface,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(
                        AppMetrics.controlRadius,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Text(rule.value),
                      ),
                    ),
                    childWhenDragging: Icon(
                      Icons.drag_indicator,
                      size: AppMetrics.iconMd,
                      color: c.textTertiary,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: AppMetrics.iconMd,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: rule.rules.isEmpty ? 4 : 20,
                    child: rule.rules.isEmpty
                        ? null
                        : IconButton(
                            onPressed: onToggleCollapsed,
                            tooltip: entry.collapsed ? '展开' : '折叠',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            iconSize: AppMetrics.iconMd,
                            icon: Icon(
                              entry.collapsed
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                            ),
                          ),
                  ),
                  Checkbox(
                    key: ValueKey('viewer-rule-enabled-${rule.id}'),
                    value: rule.enabled,
                    onChanged: (value) => onEnabled(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _ruleSubtitle(rule),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (rule.managed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.lock_outline,
                        size: AppMetrics.iconSm,
                        color: c.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RuleInsertTarget extends StatelessWidget {
  const _RuleInsertTarget({
    required this.targetId,
    required this.canDrop,
    required this.onAccept,
  });

  final String targetId;
  final bool Function(String draggedId, String targetId) canDrop;
  final void Function(String draggedId, String targetId) onAccept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DragTarget<_RuleDragData>(
      onWillAcceptWithDetails: (details) =>
          canDrop(details.data.ruleId, targetId),
      onAcceptWithDetails: (details) => onAccept(details.data.ruleId, targetId),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: candidates.isEmpty ? 2 : 6,
        color: candidates.isEmpty ? Colors.transparent : c.accent,
      ),
    );
  }
}

class _RootRuleDropTarget extends StatelessWidget {
  const _RootRuleDropTarget({required this.onAccept});

  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DragTarget<_RuleDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data.ruleId),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: candidates.isEmpty ? 12 : 26,
        alignment: Alignment.center,
        color: candidates.isEmpty ? Colors.transparent : c.accentSubtle,
        child: candidates.isEmpty
            ? null
            : Text('移到组内末尾', style: TextStyle(color: c.accent, fontSize: 11)),
      ),
    );
  }
}

class _ViewersColumn extends StatelessWidget {
  const _ViewersColumn({
    required this.rule,
    required this.service,
    required this.onAdd,
  });

  final ViewerRule? rule;
  final QuickViewService service;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final valueRule = rule;
    final c = context.colors;
    return ColoredBox(
      color: c.surface,
      child: Column(
        children: [
          _ColumnToolbar(
            title: 'Viewer',
            actions: [
              _IconAction(
                icon: Icons.add,
                tooltip: '添加 Viewer',
                onPressed: onAdd,
              ),
            ],
          ),
          Expanded(
            child: valueRule == null
                ? const _EmptyState(
                    icon: Icons.touch_app_outlined,
                    text: '选择一条规则以编辑 Viewer',
                  )
                : valueRule.viewers.isEmpty
                ? const _EmptyState(
                    icon: Icons.visibility_off_outlined,
                    text: '这条规则还没有 Viewer',
                  )
                : ReorderableListView.builder(
                    key: const ValueKey('viewer-candidates-list'),
                    buildDefaultDragHandles: false,
                    itemExtent: 52,
                    itemCount: valueRule.viewers.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      service.reorderRuleViewers(
                        valueRule.id,
                        oldIndex,
                        newIndex,
                      );
                    },
                    itemBuilder: (context, index) {
                      final viewer = valueRule.viewers[index];
                      final plugin = service.pluginById(viewer.id);
                      return _ViewerRow(
                        key: ValueKey('viewer-candidate-${viewer.id}'),
                        viewer: viewer,
                        plugin: plugin,
                        index: index,
                        onEnabled: (enabled) => service.setRuleViewerEnabled(
                          valueRule.id,
                          viewer.id,
                          enabled,
                        ),
                        onRemove: viewer.managed
                            ? null
                            : () => service.removeViewerFromRule(
                                valueRule.id,
                                viewer.id,
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({
    super.key,
    required this.viewer,
    required this.plugin,
    required this.index,
    required this.onEnabled,
    required this.onRemove,
  });

  final ViewerRuleViewer viewer;
  final ViewerPlugin? plugin;
  final int index;
  final ValueChanged<bool> onEnabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final available = plugin?.isAvailable ?? false;
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_indicator, size: AppMetrics.iconMd),
            ),
          ),
          Checkbox(
            key: ValueKey('viewer-enabled-${viewer.id}'),
            value: viewer.enabled,
            onChanged: (value) => onEnabled(value ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin?.manifest.name ?? viewer.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  available ? viewer.id : '${viewer.id} · 不可用',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: available ? c.textTertiary : c.danger,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (viewer.managed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.lock_outline,
                size: AppMetrics.iconSm,
                color: c.textTertiary,
              ),
            )
          else
            _IconAction(
              icon: Icons.close,
              tooltip: '移除 Viewer',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _ColumnToolbar extends StatelessWidget {
  const _ColumnToolbar({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: AppMetrics.fontBody,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.textTertiary),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleDraft {
  const _RuleDraft({
    required this.type,
    required this.value,
    required this.pathMode,
  });

  final ViewerRuleType type;
  final String value;
  final ViewerPathMatchMode? pathMode;
}

Future<String?> _showGroupDialog(
  BuildContext context, {
  String initialName = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _GroupEditorDialog(initialName: initialName),
  );
}

class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({required this.initialName});

  final String initialName;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName.isEmpty ? '新建规则组' : '重命名规则组'),
      content: TextField(
        key: const ValueKey('viewer-rule-group-name'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }
}

Future<_RuleDraft?> _showRuleDialog(
  BuildContext context, {
  ViewerRule? initialRule,
}) {
  return showDialog<_RuleDraft>(
    context: context,
    builder: (context) => _RuleEditorDialog(initialRule: initialRule),
  );
}

class _RuleEditorDialog extends StatefulWidget {
  const _RuleEditorDialog({this.initialRule});

  final ViewerRule? initialRule;

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late ViewerRuleType _type;
  late ViewerPathMatchMode _pathMode;
  late final TextEditingController _valueController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialRule?.type ?? ViewerRuleType.extension;
    _pathMode = widget.initialRule?.pathMode ?? ViewerPathMatchMode.glob;
    _valueController = TextEditingController(
      text: widget.initialRule?.value ?? '',
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialRule == null ? '新建规则' : '编辑规则'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<ViewerRuleType>(
              key: const ValueKey('viewer-rule-type'),
              initialSelection: _type,
              label: const Text('类型'),
              selectOnly: true,
              enableSearch: false,
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final type in ViewerRuleType.values)
                  DropdownMenuEntry(value: type, label: type.label),
              ],
              onSelected: (value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                    _error = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            if (_type == ViewerRuleType.path) ...[
              DropdownMenu<ViewerPathMatchMode>(
                key: const ValueKey('viewer-rule-path-mode'),
                initialSelection: _pathMode,
                label: const Text('路径匹配'),
                selectOnly: true,
                enableSearch: false,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final mode in ViewerPathMatchMode.values)
                    DropdownMenuEntry(value: mode, label: mode.label),
                ],
                onSelected: (value) {
                  if (value != null) setState(() => _pathMode = value);
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('viewer-rule-value'),
              controller: _valueController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _valueLabel(_type),
                hintText: _valueHint(_type),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }

  void _submit() {
    try {
      final mode = _type == ViewerRuleType.path ? _pathMode : null;
      final value = ViewerRule.normalizeValue(
        _type,
        _valueController.text,
        pathMode: mode,
      );
      Navigator.of(
        context,
      ).pop(_RuleDraft(type: _type, value: value, pathMode: mode));
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
    }
  }
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}

String _ruleSubtitle(ViewerRule rule) {
  final childText = rule.rules.isEmpty ? '' : ' · ${rule.rules.length} 个子规则';
  final viewerText = rule.viewers.isEmpty
      ? ''
      : ' · ${rule.viewers.length} 个 Viewer';
  final modeText = rule.type == ViewerRuleType.path
      ? ' · ${rule.pathMode!.label}'
      : '';
  return '${rule.type.label}$modeText$childText$viewerText';
}

String _valueLabel(ViewerRuleType type) => switch (type) {
  ViewerRuleType.path => '路径',
  ViewerRuleType.fileName => '文件名',
  ViewerRuleType.extension => '扩展名',
  ViewerRuleType.mimeType => 'MIME',
};

String _valueHint(ViewerRuleType type) => switch (type) {
  ViewerRuleType.path => r'C:\Projects\**\*.md',
  ViewerRuleType.fileName => 'README.md',
  ViewerRuleType.extension => '.md',
  ViewerRuleType.mimeType => 'text/markdown',
};

List<_RuleTreeEntry> _flattenRules(
  Iterable<ViewerRule> roots,
  Set<String> collapsed, [
  int depth = 0,
]) {
  final result = <_RuleTreeEntry>[];
  for (final rule in roots) {
    final isCollapsed = collapsed.contains(rule.id);
    result.add(
      _RuleTreeEntry(rule: rule, depth: depth, collapsed: isCollapsed),
    );
    if (!isCollapsed) {
      result.addAll(_flattenRules(rule.rules, collapsed, depth + 1));
    }
  }
  return result;
}

bool _containsRule(ViewerRule root, String id) {
  if (root.id == id) return true;
  return root.rules.any((child) => _containsRule(child, id));
}

class _RuleTreeEntry {
  const _RuleTreeEntry({
    required this.rule,
    required this.depth,
    required this.collapsed,
  });

  final ViewerRule rule;
  final int depth;
  final bool collapsed;
}

class _RuleDragData {
  const _RuleDragData(this.ruleId);

  final String ruleId;
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: AppMetrics.iconMd,
      color: context.colors.textSecondary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
  }
}

const double _minimumColumnWidth = 140;
const double _maximumColumnWidth = 520;
const double _columnSplitterWidth = 8;

double _columnMaxWidth(
  double availableWidth, {
  required double minimumTrailingWidth,
}) {
  if (!availableWidth.isFinite) return _maximumColumnWidth;
  final available =
      availableWidth - _columnSplitterWidth - minimumTrailingWidth;
  return math
      .max(_minimumColumnWidth, math.min(_maximumColumnWidth, available))
      .toDouble();
}

class _ColumnSplitter extends StatefulWidget {
  const _ColumnSplitter({
    super.key,
    required this.width,
    required this.maxWidth,
    required this.onWidthChanged,
  });

  final double width;
  final double maxWidth;
  final ValueChanged<double> onWidthChanged;

  @override
  State<_ColumnSplitter> createState() => _ColumnSplitterState();
}

class _ColumnSplitterState extends State<_ColumnSplitter> {
  bool _hovering = false;
  bool _dragging = false;
  double _startPosition = 0;
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() => _dragging = true);
          _startPosition = details.globalPosition.dx;
          _startWidth = widget.width;
        },
        onPanUpdate: (details) {
          final target =
              _startWidth + details.globalPosition.dx - _startPosition;
          widget.onWidthChanged(
            target.clamp(_minimumColumnWidth, widget.maxWidth).toDouble(),
          );
        },
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        child: Container(
          width: _columnSplitterWidth,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            color: _dragging
                ? c.accent
                : _hovering
                ? c.accent.withValues(alpha: 0.5)
                : c.border,
          ),
        ),
      ),
    );
  }
}
