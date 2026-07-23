import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../services/icon_service.dart';
import '../state/pane_controller.dart';

class FileListView extends StatelessWidget {
  final List<FileEntry> entries;
  final Set<String> selectedPaths;
  final ValueChanged<String> onSingleTap;
  final ValueChanged<String> onDoubleTap;
  final Function(String path, Offset globalPosition)? onItemRightClick;
  final Function(Offset globalPosition)? onEmptyRightClick;
  final bool loading;
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;

  const FileListView({
    super.key,
    required this.entries,
    required this.selectedPaths,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onItemRightClick,
    this.onEmptyRightClick,
    required this.loading,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      children: [
        _ColumnHeader(
          sortColumn: sortColumn,
          sortAscending: sortAscending,
          onSort: onSort,
        ),
        Container(height: 1, color: const Color(0xFFD0D0D0)),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) {
              onEmptyRightClick?.call(details.globalPosition);
            },
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      '空文件夹',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemExtent: 22,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _FileRow(
                        entry: entry,
                        isSelected: selectedPaths.contains(entry.path),
                        onSingleTap: () => onSingleTap(entry.path),
                        onDoubleTap: () => onDoubleTap(entry.path),
                        onRightClick: (pos) =>
                            onItemRightClick?.call(entry.path, pos),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Column Header ────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;

  const _ColumnHeader({
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _HeaderCell(
            label: '名称',
            flex: 4,
            column: SortColumn.name,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            onSort: onSort,
          ),
          _HeaderCell(
            label: '修改日期',
            flex: 2,
            column: SortColumn.dateModified,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            onSort: onSort,
          ),
          _HeaderCell(
            label: '类型',
            flex: 2,
            column: SortColumn.type,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            onSort: onSort,
          ),
          _HeaderCell(
            label: '大小',
            flex: 1,
            column: SortColumn.size,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            onSort: onSort,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final SortColumn column;
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;

  const _HeaderCell({
    required this.label,
    required this.flex,
    required this.column,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortColumn == column;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(column),
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: const Color(0xFF333333),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Icon(
                  sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: const Color(0xFF555555),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File Row ─────────────────────────────────────────────────────────

class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onRightClick;

  const _FileRow({
    required this.entry,
    required this.isSelected,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isSelected ? const Color(0xFF0078D4) : Colors.transparent;
    final textColor = isSelected ? Colors.white : const Color(0xFF1A1A1A);

    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (details) =>
          onRightClick?.call(details.globalPosition),
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _FileIcon(
                    path: entry.path,
                    isDirectory: entry.isDirectory,
                    isSelected: isSelected,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: TextStyle(fontSize: 12, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.formattedDate,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.type,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                entry.formattedSize,
                style: TextStyle(fontSize: 12, color: textColor),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── File Icon (real system icon via SHGetFileInfo) ───────────────────

class _FileIcon extends StatelessWidget {
  final String path;
  final bool isDirectory;
  final bool isSelected;

  const _FileIcon({
    required this.path,
    required this.isDirectory,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final iconIndex = IconService.getIconIndex(path, isDirectory);
    final png = IconService.getIconPng(iconIndex);

    if (png != null) {
      return SizedBox(
        width: 16,
        height: 16,
        child: Image.memory(png, width: 16, height: 16, fit: BoxFit.contain),
      );
    }

    // Fallback to Material icons
    return Icon(
      isDirectory ? Icons.folder : Icons.insert_drive_file,
      size: 16,
      color: isSelected
          ? Colors.white
          : (isDirectory ? Colors.amber.shade700 : Colors.grey.shade600),
    );
  }
}
