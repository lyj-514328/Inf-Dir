import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../services/icon_service.dart';
import '../state/pane_controller.dart';

class FileListView extends StatefulWidget {
  final List<FileEntry> entries;
  final Set<String> selectedPaths;
  final bool isActive;
  final ValueChanged<String> onSingleTap;
  final ValueChanged<String> onDoubleTap;
  final Function(String path, Offset globalPosition)? onItemRightClick;
  final Function(Offset globalPosition)? onEmptyRightClick;
  final bool loading;
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;
  final List<double> columnWidths;
  final Function(int colIndex, double deltaPx) onResizeColumn;
  final Function(double paneWidth)? onInitWidths;

  const FileListView({
    super.key,
    required this.entries,
    required this.selectedPaths,
    this.isActive = true,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onItemRightClick,
    this.onEmptyRightClick,
    required this.loading,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.onResizeColumn,
    this.onInitWidths,
  });

  @override
  State<FileListView> createState() => _FileListViewState();
}

class _FileListViewState extends State<FileListView> {
  static const double _minBlank = 20;
  static const double _splitterW = 4;
  static const double _hPad = 8; // horizontal padding

  double _paneWidth = 0;
  bool _widthsInitialized = false;
  final ScrollController _hScrollController = ScrollController();

  double get _totalColWidth =>
      widget.columnWidths.reduce((a, b) => a + b) + 4 * _splitterW + _hPad;

  double get _blankWidth {
    final b = _paneWidth - _totalColWidth;
    return b < _minBlank ? _minBlank : b;
  }

  double get _listWidth => _totalColWidth + _blankWidth;

  bool get _hasScrollbar => _blankWidth <= _minBlank + 1; // tolerance

  void _handleResize(int colIndex, double delta) {
    final newW = (widget.columnWidths[colIndex] + delta).clamp(40.0, double.infinity);
    final actualDelta = newW - widget.columnWidths[colIndex];
    if (actualDelta.abs() > 0.01) {
      widget.onResizeColumn(colIndex, actualDelta);
    }
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _paneWidth = constraints.maxWidth;
        if (!_widthsInitialized && _paneWidth > 0 && widget.onInitWidths != null) {
          _widthsInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onInitWidths!(_paneWidth);
          });
        }
        final blankW = _blankWidth;
        final listW = _listWidth;

        return Scrollbar(
          controller: _hScrollController,
          child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _hScrollController,
          child: SizedBox(
            width: listW,
            height: constraints.maxHeight,
            child: Column(
              children: [
                _ColumnHeader(
                  sortColumn: widget.sortColumn,
                  sortAscending: widget.sortAscending,
                  onSort: widget.onSort,
                  columnWidths: widget.columnWidths,
                  blankWidth: blankW,
                  onResizeColumn: _handleResize,
                ),
                Container(height: 1, color: const Color(0xFFD0D0D0)),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapUp: (details) {
                      widget.onEmptyRightClick?.call(details.globalPosition);
                    },
                    child: widget.entries.isEmpty
                        ? const Center(
                            child: Text(
                              '空文件夹',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            itemCount: widget.entries.length,
                            itemExtent: 22,
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              final entry = widget.entries[index];
                              return _FileRow(
                                entry: entry,
                                isSelected: widget.selectedPaths.contains(entry.path),
                                isActive: widget.isActive,
                                columnWidths: widget.columnWidths,
                                blankWidth: blankW,
                                onSingleTap: () => widget.onSingleTap(entry.path),
                                onDoubleTap: () => widget.onDoubleTap(entry.path),
                                onRightClick: (pos) =>
                                    widget.onItemRightClick?.call(entry.path, pos),
                              );
                            },
                          ),
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

// ── Column Header ────────────────────────────────────────────────────

class _ColumnHeader extends StatelessWidget {
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;
  final List<double> columnWidths;
  final double blankWidth;
  final Function(int colIndex, double deltaPx) onResizeColumn;

  const _ColumnHeader({
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.blankWidth,
    required this.onResizeColumn,
  });

  static const _columns = [
    (label: '名称', column: SortColumn.name),
    (label: '修改日期', column: SortColumn.dateModified),
    (label: '类型', column: SortColumn.type),
    (label: '大小', column: SortColumn.size),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Container(
            height: 22,
            color: const Color(0xFFF0F0F0),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (int i = 0; i < _columns.length; i++) ...[
                  if (i > 0)
                    _HeaderSplitter(
                      colIndex: i - 1,
                      onResizeColumn: onResizeColumn,
                    ),
                  _HeaderCell(
                    label: _columns[i].label,
                    width: columnWidths[i],
                    column: _columns[i].column,
                    sortColumn: sortColumn,
                    sortAscending: sortAscending,
                    onSort: onSort,
                  ),
                ],
                // 大小列与空白列之间的分隔条
                _HeaderSplitter(
                  colIndex: 3,
                  onResizeColumn: onResizeColumn,
                ),
              ],
            ),
          ),
          SizedBox(width: blankWidth, height: 22),
        ],
      ),
    );
  }
}

/// 列间拖拽分隔条
class _HeaderSplitter extends StatefulWidget {
  final int colIndex;
  final Function(int colIndex, double deltaPx) onResizeColumn;

  const _HeaderSplitter({
    required this.colIndex,
    required this.onResizeColumn,
  });

  @override
  State<_HeaderSplitter> createState() => _HeaderSplitterState();
}

class _HeaderSplitterState extends State<_HeaderSplitter> {
  bool _hovering = false;
  bool _dragging = false;
  double _startX = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _dragging = true;
            _startX = details.globalPosition.dx;
          });
        },
        onPanUpdate: (details) {
          final delta = details.globalPosition.dx - _startX;
          _startX = details.globalPosition.dx;
          if (delta.abs() >= 1) {
            widget.onResizeColumn(widget.colIndex, delta);
          }
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
        },
        child: Container(
          width: 4,
          height: double.infinity,
          alignment: Alignment.center,
          child: Container(
            width: _hovering || _dragging ? 4 : 2,
            height: 14,
            decoration: BoxDecoration(
              color: _dragging
                  ? cs.primary
                  : _hovering
                      ? cs.primary.withValues(alpha: 0.4)
                      : cs.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final SortColumn column;
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;

  const _HeaderCell({
    required this.label,
    required this.width,
    required this.column,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortColumn == column;
    return SizedBox(
      width: width,
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
  final bool isActive;
  final List<double> columnWidths;
  final double blankWidth;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onRightClick;

  const _FileRow({
    required this.entry,
    required this.isSelected,
    this.isActive = true,
    required this.columnWidths,
    required this.blankWidth,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? (isActive ? const Color(0xFF0078D4) : const Color(0xFFCCCCCC))
        : Colors.transparent;
    final textColor = isSelected
        ? (isActive ? Colors.white : const Color(0xFF1A1A1A))
        : const Color(0xFF1A1A1A);

    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (details) =>
          onRightClick?.call(details.globalPosition),
      child: SizedBox(
        height: 22,
        child: Row(
          children: [
            Container(
              // 高亮仅覆盖数据列区域，不包含右侧空白
              color: bgColor,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: columnWidths[0],
                    child: Row(
                      children: [
                        _FileIcon(
                          path: entry.path,
                          isDirectory: entry.isDirectory,
                          isSelected: isSelected && isActive,
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
                  SizedBox(
                    width: columnWidths[1],
                    child: Text(
                      entry.formattedDate,
                      style: TextStyle(fontSize: 12, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: columnWidths[2],
                    child: Text(
                      entry.type,
                      style: TextStyle(fontSize: 12, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: columnWidths[3],
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
            SizedBox(width: blankWidth),
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
    final png = IconService.getFileIconPng(path, isDirectory, 32);

    if (png != null) {
      return SizedBox(
        width: 16,
        height: 16,
        child: Image.memory(png, width: 16, height: 16, fit: BoxFit.contain),
      );
    }

    return Icon(
      isDirectory ? Icons.folder : Icons.insert_drive_file,
      size: 16,
      color: isSelected
          ? Colors.white
          : (isDirectory ? Colors.amber.shade700 : Colors.grey.shade600),
    );
  }
}
