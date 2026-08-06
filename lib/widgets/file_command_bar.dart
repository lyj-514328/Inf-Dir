import 'package:flutter/material.dart';

import '../state/pane_controller.dart';
import 'app_theme.dart';

enum _NewAction { folder, textFile }

enum _SortAction { name, dateModified, type, size, ascending, descending }

enum _MoreAction { selectAll, refresh, showHiddenFiles, properties }

/// Explorer-style command row for a file pane.
class FileCommandBar extends StatelessWidget {
  final bool canCreate;
  final bool canCut;
  final bool canCopy;
  final bool canPaste;
  final bool canRename;
  final bool canShare;
  final bool canDelete;
  final bool canSelectAll;
  final bool canShowProperties;
  final bool showHiddenFiles;
  final SortColumn sortColumn;
  final bool sortAscending;
  final PaneViewMode viewMode;
  final EntryFilter entryFilter;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onCreateTextFile;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onRename;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final ValueChanged<SortColumn>? onSortColumn;
  final ValueChanged<bool>? onSortAscending;
  final ValueChanged<PaneViewMode>? onViewMode;
  final ValueChanged<EntryFilter>? onFilter;
  final VoidCallback? onSelectAll;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleHiddenFiles;
  final VoidCallback? onProperties;

  const FileCommandBar({
    super.key,
    this.canCreate = true,
    required this.canCut,
    required this.canCopy,
    required this.canPaste,
    required this.canRename,
    this.canShare = false,
    required this.canDelete,
    this.canSelectAll = false,
    this.canShowProperties = false,
    this.showHiddenFiles = false,
    this.sortColumn = SortColumn.name,
    this.sortAscending = true,
    this.viewMode = PaneViewMode.details,
    this.entryFilter = EntryFilter.all,
    this.onCreateFolder,
    this.onCreateTextFile,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onRename,
    this.onShare,
    this.onDelete,
    this.onSortColumn,
    this.onSortAscending,
    this.onViewMode,
    this.onFilter,
    this.onSelectAll,
    this.onRefresh,
    this.onToggleHiddenFiles,
    this.onProperties,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppMetrics.commandBarHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CommandMenuButton<_NewAction>(
              icon: Icons.add,
              label: '新建',
              tooltip: '新建',
              enabled: canCreate,
              items: const [
                PopupMenuItem(
                  value: _NewAction.folder,
                  child: _MenuRow(
                    icon: Icons.create_new_folder_outlined,
                    label: '文件夹',
                  ),
                ),
                PopupMenuItem(
                  value: _NewAction.textFile,
                  child: _MenuRow(icon: Icons.note_add_outlined, label: '文本文档'),
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _NewAction.folder:
                    onCreateFolder?.call();
                  case _NewAction.textFile:
                    onCreateTextFile?.call();
                }
              },
            ),
            _CommandButton(
              icon: Icons.content_cut,
              label: '剪切',
              tooltip: '剪切 (Ctrl+X)',
              enabled: canCut,
              onPressed: onCut,
            ),
            _CommandButton(
              icon: Icons.content_copy,
              label: '复制',
              tooltip: '复制 (Ctrl+C)',
              enabled: canCopy,
              onPressed: onCopy,
            ),
            _CommandButton(
              icon: Icons.content_paste,
              label: '粘贴',
              tooltip: '粘贴 (Ctrl+V)',
              enabled: canPaste,
              onPressed: onPaste,
            ),
            _CommandButton(
              icon: Icons.drive_file_rename_outline,
              label: '重命名',
              tooltip: '重命名 (F2)',
              enabled: canRename,
              onPressed: onRename,
            ),
            _CommandButton(
              icon: Icons.ios_share,
              label: '共享',
              tooltip: '使用 Windows 共享',
              enabled: canShare,
              onPressed: onShare,
            ),
            _CommandButton(
              icon: Icons.delete_outline,
              label: '删除',
              tooltip: '删除 (Delete)',
              enabled: canDelete,
              onPressed: onDelete,
            ),
            const _CommandDivider(),
            _CommandMenuButton<_SortAction>(
              icon: Icons.sort,
              label: '排序',
              tooltip: '排序方式',
              items: [
                _checkedMenuItem(
                  value: _SortAction.name,
                  label: '名称',
                  checked: sortColumn == SortColumn.name,
                ),
                _checkedMenuItem(
                  value: _SortAction.dateModified,
                  label: '修改日期',
                  checked: sortColumn == SortColumn.dateModified,
                ),
                _checkedMenuItem(
                  value: _SortAction.type,
                  label: '类型',
                  checked: sortColumn == SortColumn.type,
                ),
                _checkedMenuItem(
                  value: _SortAction.size,
                  label: '大小',
                  checked: sortColumn == SortColumn.size,
                ),
                const PopupMenuDivider(),
                _checkedMenuItem(
                  value: _SortAction.ascending,
                  label: '升序',
                  checked: sortAscending,
                ),
                _checkedMenuItem(
                  value: _SortAction.descending,
                  label: '降序',
                  checked: !sortAscending,
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _SortAction.name:
                    onSortColumn?.call(SortColumn.name);
                  case _SortAction.dateModified:
                    onSortColumn?.call(SortColumn.dateModified);
                  case _SortAction.type:
                    onSortColumn?.call(SortColumn.type);
                  case _SortAction.size:
                    onSortColumn?.call(SortColumn.size);
                  case _SortAction.ascending:
                    onSortAscending?.call(true);
                  case _SortAction.descending:
                    onSortAscending?.call(false);
                }
              },
            ),
            _CommandMenuButton<PaneViewMode>(
              icon: _viewIcon(viewMode),
              label: '查看',
              tooltip: '查看方式',
              items: [
                _checkedMenuItem(
                  value: PaneViewMode.details,
                  label: '详细信息',
                  checked: viewMode == PaneViewMode.details,
                ),
                _checkedMenuItem(
                  value: PaneViewMode.list,
                  label: '列表',
                  checked: viewMode == PaneViewMode.list,
                ),
                _checkedMenuItem(
                  value: PaneViewMode.compact,
                  label: '紧凑视图',
                  checked: viewMode == PaneViewMode.compact,
                ),
              ],
              onSelected: (mode) => onViewMode?.call(mode),
            ),
            _CommandMenuButton<EntryFilter>(
              icon: Icons.filter_alt_outlined,
              label: '筛选器',
              tooltip: '筛选当前文件夹',
              active: entryFilter != EntryFilter.all,
              items: [
                _checkedMenuItem(
                  value: EntryFilter.all,
                  label: '全部',
                  checked: entryFilter == EntryFilter.all,
                ),
                _checkedMenuItem(
                  value: EntryFilter.folders,
                  label: '文件夹',
                  checked: entryFilter == EntryFilter.folders,
                ),
                _checkedMenuItem(
                  value: EntryFilter.files,
                  label: '文件',
                  checked: entryFilter == EntryFilter.files,
                ),
                _checkedMenuItem(
                  value: EntryFilter.images,
                  label: '图片',
                  checked: entryFilter == EntryFilter.images,
                ),
                _checkedMenuItem(
                  value: EntryFilter.documents,
                  label: '文档',
                  checked: entryFilter == EntryFilter.documents,
                ),
              ],
              onSelected: (filter) => onFilter?.call(filter),
            ),
            _CommandMenuButton<_MoreAction>(
              icon: Icons.more_horiz,
              label: '更多',
              tooltip: '更多操作',
              active: showHiddenFiles,
              items: [
                PopupMenuItem(
                  value: _MoreAction.selectAll,
                  enabled: canSelectAll,
                  child: const _MenuRow(icon: Icons.select_all, label: '全选'),
                ),
                const PopupMenuItem(
                  value: _MoreAction.refresh,
                  child: _MenuRow(icon: Icons.refresh, label: '刷新'),
                ),
                const PopupMenuDivider(),
                _checkedMenuItem(
                  value: _MoreAction.showHiddenFiles,
                  label: '显示隐藏项目',
                  checked: showHiddenFiles,
                ),
                PopupMenuItem(
                  value: _MoreAction.properties,
                  enabled: canShowProperties,
                  child: const _MenuRow(icon: Icons.info_outline, label: '属性'),
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _MoreAction.selectAll:
                    onSelectAll?.call();
                  case _MoreAction.refresh:
                    onRefresh?.call();
                  case _MoreAction.showHiddenFiles:
                    onToggleHiddenFiles?.call();
                  case _MoreAction.properties:
                    onProperties?.call();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static IconData _viewIcon(PaneViewMode mode) {
    return switch (mode) {
      PaneViewMode.details => Icons.view_headline,
      PaneViewMode.list => Icons.view_list,
      PaneViewMode.compact => Icons.density_small,
    };
  }

  static CheckedPopupMenuItem<T> _checkedMenuItem<T>({
    required T value,
    required String label,
    required bool checked,
  }) {
    return CheckedPopupMenuItem<T>(
      value: value,
      checked: checked,
      child: Text(label),
    );
  }
}

class _CommandDivider extends StatelessWidget {
  const _CommandDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: context.colors.border,
    );
  }
}

class _CommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  const _CommandButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        hoverColor: c.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: SizedBox(
            height: AppMetrics.commandBarHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: AppMetrics.iconMd,
                  color: enabled ? c.textSecondary : c.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: enabled ? c.textSecondary : c.textTertiary,
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

class _CommandMenuButton<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final bool active;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  const _CommandMenuButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.enabled = true,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = !enabled
        ? c.textTertiary
        : active
        ? c.accent
        : c.textSecondary;
    return PopupMenuButton<T>(
      enabled: enabled,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      offset: const Offset(0, AppMetrics.commandBarHeight - 2),
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: SizedBox(
          height: AppMetrics.commandBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppMetrics.iconMd, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: AppMetrics.fontSmall, color: color),
              ),
              Icon(Icons.arrow_drop_down, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: AppMetrics.iconMd,
          color: context.colors.textSecondary,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
