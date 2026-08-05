import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/app_theme.dart';
import 'plugin_manifest.dart';
import 'quick_view_service.dart';

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
    final c = context.colors;
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width - 48).clamp(420.0, 820.0);
    final height = (viewport.height - 48).clamp(360.0, 620.0);

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
        side: BorderSide(color: c.borderStrong),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _DialogHeader(onClose: () => Navigator.of(context).pop()),
            Container(height: 1, color: c.border),
            const Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    _AssociationTabs(),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _AssociationPage(
                            kind: ViewerAssociationKind.extension,
                          ),
                          _AssociationPage(
                            kind: ViewerAssociationKind.fileName,
                          ),
                          _AssociationPage(
                            kind: ViewerAssociationKind.mimeType,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
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

class _AssociationTabs extends StatelessWidget {
  const _AssociationTabs();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 34,
      color: c.surfaceSubtle,
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.accent,
        labelStyle: const TextStyle(fontSize: AppMetrics.fontBody),
        tabs: const [
          Tab(text: '扩展名'),
          Tab(text: '文件名'),
          Tab(text: 'MIME'),
        ],
      ),
    );
  }
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
              Container(height: 1, color: c.border),
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
        builder: (context, setDialogState) => AlertDialog(
          title: Text('添加${widget.kind.label}关联'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: switch (widget.kind) {
                ViewerAssociationKind.extension => '.pdf',
                ViewerAssociationKind.fileName => 'dockerfile',
                ViewerAssociationKind.mimeType => 'application/pdf',
              },
              errorText: error,
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => _validateAndClose(
                dialogContext,
                service,
                controller.text,
                (message) => setDialogState(() => error = message),
              ),
              child: const Text('添加'),
            ),
          ],
        ),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? c.accentSubtle : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: candidateCount == 0 ? c.textTertiary : c.textPrimary,
                ),
              ),
            ),
            if (overridden) Icon(Icons.tune, size: 12, color: c.textTertiary),
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
        Container(height: 1, color: c.border),
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
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
  }
}
