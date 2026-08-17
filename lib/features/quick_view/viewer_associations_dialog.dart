import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/app_theme.dart';
import 'plugin_manifest.dart';
import 'quick_view_service.dart';
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
    final width = (viewport.width - 48).clamp(420.0, 820.0);
    final height = (viewport.height - 48).clamp(360.0, 620.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: width,
        height: height,
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

class ViewerAssociationsView extends StatelessWidget {
  const ViewerAssociationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _AssociationTabs(),
          Expanded(
            child: TabBarView(
              children: [
                _PathRulePage(),
                _AssociationPage(kind: ViewerAssociationKind.extension),
                _AssociationPage(kind: ViewerAssociationKind.fileName),
                _AssociationPage(kind: ViewerAssociationKind.mimeType),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final service = context.watch<QuickViewService>();
    return SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(
          children: [
            Icon(Icons.extension, size: AppMetrics.iconMd, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '查看器关联',
                style: Theme.of(context).dialogTheme.titleTextStyle,
              ),
            ),
            Tooltip(
              message: service.issues.isEmpty
                  ? '所有插件均可用'
                  : service.issues
                        .map((issue) => '${issue.message}\n${issue.path}')
                        .join('\n\n'),
              child: Text(
                '${service.plugins.where((plugin) => plugin.isAvailable).length} 个可用插件',
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: service.issues.isEmpty ? c.textSecondary : c.danger,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _IconAction(
              icon: Icons.refresh,
              tooltip: '重新扫描插件',
              onPressed: service.reload,
            ),
            _IconAction(icon: Icons.close, tooltip: '关闭', onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// 分段（segmented）样式的 tab 切换：surfaceSubtle 底槽 + surface 选中胶囊
class _AssociationTabs extends StatelessWidget {
  const _AssociationTabs();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: c.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        ),
        child: TabBar(
          indicator: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            border: Border.all(color: c.border),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: c.textPrimary,
          unselectedLabelColor: c.textSecondary,
          labelStyle: const TextStyle(
            fontSize: AppMetrics.fontBody,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: AppMetrics.fontBody),
          tabs: const [
            Tab(text: '路径'),
            Tab(text: '扩展名'),
            Tab(text: '文件名'),
            Tab(text: 'MIME'),
          ],
        ),
      ),
    );
  }
}

class _PathRulePage extends StatefulWidget {
  const _PathRulePage();

  @override
  State<_PathRulePage> createState() => _PathRulePageState();
}

class _PathRulePageState extends State<_PathRulePage>
    with AutomaticKeepAliveClientMixin {
  String? _selectedId;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final service = context.watch<QuickViewService>();
    final rules = service.pathRules;
    final selectedIndex = rules.indexWhere((rule) => rule.id == _selectedId);
    final selected = selectedIndex < 0 ? null : rules[selectedIndex];
    if (selected == null && rules.isNotEmpty) {
      _selectedId = rules.first.id;
    }
    final activeRule = selected ?? (rules.isEmpty ? null : rules.first);
    final activeIndex = activeRule == null
        ? -1
        : rules.indexWhere((rule) => rule.id == activeRule.id);

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _PathRuleToolbar(
                onAdd: () => _addRule(context, service),
                onEdit: activeRule == null
                    ? null
                    : () => _editRule(context, service, activeRule),
                onDelete: activeRule == null
                    ? null
                    : () => _deleteRule(context, service, activeRule),
                onMoveUp: activeIndex > 0
                    ? () => service.movePathRule(activeRule!.id, -1)
                    : null,
                onMoveDown: activeIndex >= 0 && activeIndex < rules.length - 1
                    ? () => service.movePathRule(activeRule!.id, 1)
                    : null,
              ),
              Expanded(
                child: rules.isEmpty
                    ? Center(
                        child: Text(
                          '没有路径规则',
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: c.textTertiary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemExtent: 48,
                        itemCount: rules.length,
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          return _PathRuleRow(
                            rule: rule,
                            candidateCount: service
                                .candidatesForPathRule(rule)
                                .length,
                            selected: rule.id == activeRule?.id,
                            onSelected: () =>
                                setState(() => _selectedId = rule.id),
                            onEnabled: (enabled) =>
                                service.setPathRuleEnabled(rule.id, enabled),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: c.border),
        Expanded(
          child: activeRule == null
              ? const SizedBox.shrink()
              : _PathRuleCandidateEditor(ruleId: activeRule.id),
        ),
      ],
    );
  }

  Future<void> _addRule(BuildContext context, QuickViewService service) async {
    final draft = await _showPathRuleDialog(context, service);
    if (draft == null || !mounted) return;
    final rule = service.addPathRule(
      pattern: draft.pattern,
      mode: draft.mode,
      viewerIds: [draft.viewerId!],
    );
    setState(() => _selectedId = rule.id);
  }

  Future<void> _editRule(
    BuildContext context,
    QuickViewService service,
    ViewerPathRule rule,
  ) async {
    final draft = await _showPathRuleDialog(
      context,
      service,
      initialRule: rule,
    );
    if (draft == null || !mounted) return;
    service.updatePathRule(rule.id, pattern: draft.pattern, mode: draft.mode);
  }

  Future<void> _deleteRule(
    BuildContext context,
    QuickViewService service,
    ViewerPathRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final c = dialogContext.colors;
        return AlertDialog(
          title: const Text('删除路径规则'),
          content: Text(
            rule.pattern,
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              color: c.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: c.danger,
                foregroundColor: c.onAccent,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    service.removePathRule(rule.id);
    setState(() => _selectedId = null);
  }
}

class _PathRuleToolbar extends StatelessWidget {
  const _PathRuleToolbar({
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 4),
          _IconAction(icon: Icons.add, tooltip: '添加路径规则', onPressed: onAdd),
          _IconAction(icon: Icons.edit, tooltip: '编辑规则', onPressed: onEdit),
          _IconAction(
            icon: Icons.delete_outline,
            tooltip: '删除规则',
            onPressed: onDelete,
          ),
          _IconAction(
            icon: Icons.keyboard_arrow_up,
            tooltip: '提高路径规则优先级',
            onPressed: onMoveUp,
          ),
          _IconAction(
            icon: Icons.keyboard_arrow_down,
            tooltip: '降低路径规则优先级',
            onPressed: onMoveDown,
          ),
        ],
      ),
    );
  }
}

class _PathRuleRow extends StatelessWidget {
  const _PathRuleRow({
    required this.rule,
    required this.candidateCount,
    required this.selected,
    required this.onSelected,
    required this.onEnabled,
  });

  final ViewerPathRule rule;
  final int candidateCount;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? c.accentSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          hoverColor: c.surfaceHover,
          child: Row(
            children: [
              Checkbox(
                key: ValueKey('path-rule-enabled-${rule.id}'),
                value: rule.enabled,
                onChanged: (value) => onEnabled(value ?? false),
                activeColor: c.accent,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.pattern,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontBody,
                        color: rule.enabled ? c.textPrimary : c.textTertiary,
                      ),
                    ),
                    Text(
                      rule.mode.label,
                      style: TextStyle(
                        fontSize: AppMetrics.fontCaption,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$candidateCount',
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathRuleCandidateEditor extends StatelessWidget {
  const _PathRuleCandidateEditor({required this.ruleId});

  final String ruleId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final service = context.watch<QuickViewService>();
    final rule = service.pathRules.firstWhere((rule) => rule.id == ruleId);
    final selected = service.candidatesForPathRule(rule);
    final selectedIds = selected.map((plugin) => plugin.manifest.id).toList();
    final selectedSet = selectedIds.toSet();
    final display = [
      ...selected,
      ...service.availablePathRulePlugins.where(
        (plugin) => !selectedSet.contains(plugin.manifest.id),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          color: c.surfaceSubtle,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Text(
            '路径规则的候选查看器',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: display.isEmpty
              ? Center(
                  child: Text(
                    '没有可用插件',
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textTertiary,
                    ),
                  ),
                )
              : ListView.builder(
                  itemExtent: 46,
                  itemCount: display.length,
                  itemBuilder: (context, index) {
                    final plugin = display[index];
                    final id = plugin.manifest.id;
                    final selectedIndex = selectedIds.indexOf(id);
                    return _CandidateRow(
                      plugin: plugin,
                      checked: selectedIndex >= 0,
                      canMoveUp: selectedIndex > 0,
                      canMoveDown:
                          selectedIndex >= 0 &&
                          selectedIndex < selectedIds.length - 1,
                      onChecked: (checked) {
                        final next = [...selectedIds];
                        if (checked) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        service.setPathRuleCandidates(rule.id, next);
                      },
                      onMoveUp: () {
                        final next = [...selectedIds];
                        final item = next.removeAt(selectedIndex);
                        next.insert(selectedIndex - 1, item);
                        service.setPathRuleCandidates(rule.id, next);
                      },
                      onMoveDown: () {
                        final next = [...selectedIds];
                        final item = next.removeAt(selectedIndex);
                        next.insert(selectedIndex + 1, item);
                        service.setPathRuleCandidates(rule.id, next);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PathRuleDraft {
  const _PathRuleDraft({
    required this.pattern,
    required this.mode,
    this.viewerId,
  });

  final String pattern;
  final ViewerPathMatchMode mode;
  final String? viewerId;
}

Future<_PathRuleDraft?> _showPathRuleDialog(
  BuildContext context,
  QuickViewService service, {
  ViewerPathRule? initialRule,
}) async {
  var patternText = initialRule?.pattern ?? '';
  var mode = initialRule?.mode ?? ViewerPathMatchMode.glob;
  final plugins = service.availablePathRulePlugins;
  String? viewerId = plugins.isEmpty ? null : plugins.first.manifest.id;
  String? error;

  final result = await showDialog<_PathRuleDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final c = context.colors;
        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          borderSide: BorderSide.none,
        );

        void submit() {
          try {
            final pattern = ViewerPathRule.normalizePattern(
              patternText,
              mode: mode,
            );
            if (initialRule == null && viewerId == null) {
              setDialogState(() => error = '没有可用 Viewer');
              return;
            }
            Navigator.pop(
              dialogContext,
              _PathRuleDraft(pattern: pattern, mode: mode, viewerId: viewerId),
            );
          } on FormatException catch (exception) {
            setDialogState(() => error = exception.message);
          }
        }

        return AlertDialog(
          title: Text(initialRule == null ? '添加路径规则' : '编辑路径规则'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ViewerPathMatchMode>(
                  initialValue: mode,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.surfaceSubtle,
                    labelText: '匹配方式',
                    border: inputBorder,
                    enabledBorder: inputBorder,
                  ),
                  items: [
                    for (final item in ViewerPathMatchMode.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => mode = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: patternText,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.surfaceSubtle,
                    labelText: mode == ViewerPathMatchMode.glob
                        ? r'C:\Work\**\*.pdf'
                        : r'C:\Work\report.pdf',
                    errorText: error,
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppMetrics.controlRadius,
                      ),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                  onChanged: (value) => patternText = value,
                  onFieldSubmitted: (_) => submit(),
                ),
                if (initialRule == null) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: viewerId,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.surfaceSubtle,
                      labelText: '首选 Viewer',
                      border: inputBorder,
                      enabledBorder: inputBorder,
                    ),
                    items: [
                      for (final plugin in plugins)
                        DropdownMenuItem(
                          value: plugin.manifest.id,
                          child: Text(plugin.manifest.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => viewerId = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: submit,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
              ),
              child: Text(initialRule == null ? '添加' : '保存'),
            ),
          ],
        );
      },
    ),
  );
  return result;
}

class _AssociationPage extends StatefulWidget {
  const _AssociationPage({required this.kind});

  final ViewerAssociationKind kind;

  @override
  State<_AssociationPage> createState() => _AssociationPageState();
}

class _AssociationPageState extends State<_AssociationPage>
    with AutomaticKeepAliveClientMixin {
  String? _selectedKey;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final service = context.watch<QuickViewService>();
    final keys = service.associationKeys(widget.kind);
    final selected = keys.contains(_selectedKey)
        ? _selectedKey
        : (keys.isEmpty ? null : keys.first);
    _selectedKey = selected;

    return Row(
      children: [
        SizedBox(
          width: 230,
          child: Column(
            children: [
              _AssociationToolbar(
                onAdd: () => _addAssociation(context, service),
                onDisable: selected == null
                    ? null
                    : () => service.disableAssociation(widget.kind, selected),
                onReset:
                    selected == null ||
                        !service.hasOverride(widget.kind, selected)
                    ? null
                    : () => service.resetAssociation(widget.kind, selected),
              ),
              Expanded(
                child: keys.isEmpty
                    ? Center(
                        child: Text(
                          '没有关联项',
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: c.textTertiary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemExtent: 30,
                        itemCount: keys.length,
                        itemBuilder: (context, index) {
                          final key = keys[index];
                          final candidates = service.candidatesForAssociation(
                            widget.kind,
                            key,
                          );
                          return _AssociationRow(
                            value: key,
                            candidateCount: candidates.length,
                            overridden: service.hasOverride(widget.kind, key),
                            selected: key == selected,
                            onTap: () => setState(() => _selectedKey = key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: c.border),
        Expanded(
          child: selected == null
              ? const SizedBox.shrink()
              : _CandidateEditor(kind: widget.kind, associationKey: selected),
        ),
      ],
    );
  }

  Future<void> _addAssociation(
    BuildContext context,
    QuickViewService service,
  ) async {
    final controller = TextEditingController();
    String? error;
    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = context.colors;
          final inputBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            borderSide: BorderSide.none,
          );
          return AlertDialog(
            title: Text('添加${widget.kind.label}关联'),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(
                fontSize: AppMetrics.fontBody,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceSubtle,
                labelText: switch (widget.kind) {
                  ViewerAssociationKind.extension => '.pdf',
                  ViewerAssociationKind.fileName => 'dockerfile',
                  ViewerAssociationKind.mimeType => 'application/pdf',
                },
                labelStyle: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: c.textTertiary,
                ),
                errorText: error,
                border: inputBorder,
                enabledBorder: inputBorder,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
                  borderSide: BorderSide(color: c.accent),
                ),
              ),
              onSubmitted: (_) => _validateAndClose(
                dialogContext,
                service,
                controller.text,
                (message) => setDialogState(() => error = message),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => _validateAndClose(
                  dialogContext,
                  service,
                  controller.text,
                  (message) => setDialogState(() => error = message),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                ),
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (key == null || !mounted) return;
    final plugins = service.availablePluginsFor(widget.kind, key);
    service.setCandidates(
      widget.kind,
      key,
      plugins.map((plugin) => plugin.manifest.id),
    );
    setState(() => _selectedKey = key);
  }

  void _validateAndClose(
    BuildContext dialogContext,
    QuickViewService service,
    String input,
    ValueChanged<String?> setError,
  ) {
    try {
      final key = widget.kind.normalize(input);
      if (service.availablePluginsFor(widget.kind, key).isEmpty) {
        setError('没有 Manifest 声明支持此关联');
        return;
      }
      Navigator.pop(dialogContext, key);
    } on FormatException catch (error) {
      setError(error.message);
    }
  }
}

class _AssociationToolbar extends StatelessWidget {
  const _AssociationToolbar({
    required this.onAdd,
    required this.onDisable,
    required this.onReset,
  });

  final VoidCallback onAdd;
  final VoidCallback? onDisable;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 4),
          _IconAction(icon: Icons.add, tooltip: '添加关联', onPressed: onAdd),
          _IconAction(
            icon: Icons.link_off,
            tooltip: '禁用关联',
            onPressed: onDisable,
          ),
          _IconAction(
            icon: Icons.restore,
            tooltip: '恢复 Manifest 候选',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _AssociationRow extends StatelessWidget {
  const _AssociationRow({
    required this.value,
    required this.candidateCount,
    required this.overridden,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final int candidateCount;
  final bool overridden;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? c.accentSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          hoverColor: c.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: candidateCount == 0
                          ? c.textTertiary
                          : c.textPrimary,
                    ),
                  ),
                ),
                if (overridden)
                  Icon(
                    Icons.tune,
                    size: AppMetrics.iconSm,
                    color: c.textTertiary,
                  ),
                const SizedBox(width: 6),
                Text(
                  '$candidateCount',
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateEditor extends StatelessWidget {
  const _CandidateEditor({required this.kind, required this.associationKey});

  final ViewerAssociationKind kind;
  final String associationKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final service = context.watch<QuickViewService>();
    final selected = service.candidatesForAssociation(kind, associationKey);
    final selectedIds = selected.map((plugin) => plugin.manifest.id).toList();
    final selectedSet = selectedIds.toSet();
    final available = service.availablePluginsFor(kind, associationKey);
    final display = [
      ...selected,
      ...available.where((plugin) => !selectedSet.contains(plugin.manifest.id)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          color: c.surfaceSubtle,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Text(
            '$associationKey 的候选查看器',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: display.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的已安装插件',
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textTertiary,
                    ),
                  ),
                )
              : ListView.builder(
                  itemExtent: 46,
                  itemCount: display.length,
                  itemBuilder: (context, index) {
                    final plugin = display[index];
                    final id = plugin.manifest.id;
                    final selectedIndex = selectedIds.indexOf(id);
                    return _CandidateRow(
                      plugin: plugin,
                      checked: selectedIndex >= 0,
                      canMoveUp: selectedIndex > 0,
                      canMoveDown:
                          selectedIndex >= 0 &&
                          selectedIndex < selectedIds.length - 1,
                      onChecked: (checked) {
                        final next = [...selectedIds];
                        if (checked) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        service.setCandidates(kind, associationKey, next);
                      },
                      onMoveUp: () {
                        final next = [...selectedIds];
                        final item = next.removeAt(selectedIndex);
                        next.insert(selectedIndex - 1, item);
                        service.setCandidates(kind, associationKey, next);
                      },
                      onMoveDown: () {
                        final next = [...selectedIds];
                        final item = next.removeAt(selectedIndex);
                        next.insert(selectedIndex + 1, item);
                        service.setCandidates(kind, associationKey, next);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.plugin,
    required this.checked,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChecked,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ViewerPlugin plugin;
  final bool checked;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<bool> onChecked;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: (value) => onChecked(value ?? false),
          activeColor: c.accent,
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plugin.manifest.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: c.textPrimary,
                ),
              ),
              Text(
                '${plugin.manifest.id}  ${plugin.manifest.version}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppMetrics.fontCaption,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
        _IconAction(
          icon: Icons.keyboard_arrow_up,
          tooltip: '上移',
          onPressed: canMoveUp ? onMoveUp : null,
        ),
        _IconAction(
          icon: Icons.keyboard_arrow_down,
          tooltip: '下移',
          onPressed: canMoveDown ? onMoveDown : null,
        ),
        const SizedBox(width: 6),
      ],
    );
  }
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
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
  }
}
