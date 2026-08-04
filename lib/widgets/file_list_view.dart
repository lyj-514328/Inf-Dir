import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../services/icon_service.dart';
import '../state/pane_controller.dart';
import 'app_theme.dart';

/// 云同步"状态"列的固定宽度（不参与列宽拖拽）。
const double _statusColWidth = 48;

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

  /// 当前目录位于云同步区时，追加只读的"状态"列（资源管理器同款）。
  final bool showStatusColumn;

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
    this.showStatusColumn = false,
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
  final ScrollController _vScrollController = ScrollController();

  /// 鼠标悬停在列表面板上时显示滚动条。
  bool _scrollbarHovered = false;

  double get _totalColWidth =>
      widget.columnWidths.reduce((a, b) => a + b) +
      4 * _splitterW +
      _hPad +
      (widget.showStatusColumn ? _statusColWidth : 0);

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
    _vScrollController.dispose();
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

        return MouseRegion(
          onEnter: (_) => setState(() => _scrollbarHovered = true),
          onExit: (_) => setState(() => _scrollbarHovered = false),
          child: Scrollbar(
          controller: _hScrollController,
          thumbVisibility: _scrollbarHovered,
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
                  showStatusColumn: widget.showStatusColumn,
                ),
                Container(height: 1, color: context.colors.border),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapUp: (details) {
                      widget.onEmptyRightClick?.call(details.globalPosition);
                    },
                    child: widget.entries.isEmpty
                        ? Center(
                            child: Text(
                              '空文件夹',
                              style: TextStyle(
                                color: context.colors.textTertiary,
                                fontSize: AppMetrics.fontBody,
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _vScrollController,
                            thumbVisibility: _scrollbarHovered,
                            child: ListView.builder(
                            controller: _vScrollController,
                            itemCount: widget.entries.length,
                            itemExtent: AppMetrics.rowHeight,
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              final entry = widget.entries[index];
                              return _FileRow(
                                entry: entry,
                                isSelected: widget.selectedPaths.contains(entry.path),
                                isActive: widget.isActive,
                                columnWidths: widget.columnWidths,
                                blankWidth: blankW,
                                showStatusColumn: widget.showStatusColumn,
                                onSingleTap: () => widget.onSingleTap(entry.path),
                                onDoubleTap: () => widget.onDoubleTap(entry.path),
                                onRightClick: (pos) =>
                                    widget.onItemRightClick?.call(entry.path, pos),
                              );
                            },
                          ),
                        ),
                  ),
                ),
              ],
            ),
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
  final bool showStatusColumn;

  const _ColumnHeader({
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.blankWidth,
    required this.onResizeColumn,
    this.showStatusColumn = false,
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
      height: AppMetrics.rowHeight,
      child: Row(
        children: [
          Container(
            height: AppMetrics.rowHeight,
            color: context.colors.surfaceSubtle,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (int i = 0; i < _columns.length; i++) ...[
                  if (i > 0)
                    _HeaderSplitter(
                      colIndex: i - 1,
                      onResizeColumn: onResizeColumn,
                    ),
                  if (i == 1 && showStatusColumn)
                    SizedBox(
                      width: _statusColWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '状态',
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
          SizedBox(width: blankWidth, height: AppMetrics.rowHeight),
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
    final c = context.colors;
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
                  ? c.accent
                  : _hovering
                      ? c.accent.withValues(alpha: 0.4)
                      : c.borderStrong,
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
    final c = context.colors;
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
                    fontSize: AppMetrics.fontBody,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? c.textPrimary : c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Icon(
                  sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: c.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File Row ─────────────────────────────────────────────────────────

class _FileRow extends StatefulWidget {
  final FileEntry entry;
  final bool isSelected;
  final bool isActive;
  final List<double> columnWidths;
  final double blankWidth;
  final bool showStatusColumn;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onRightClick;

  const _FileRow({
    required this.entry,
    required this.isSelected,
    this.isActive = true,
    required this.columnWidths,
    required this.blankWidth,
    this.showStatusColumn = false,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selectedBg = widget.isActive ? c.accent : c.selectedInactive;
    final textColor = widget.isSelected
        ? (widget.isActive ? Colors.white : c.textPrimary)
        : c.textPrimary;

    Color bgColor;
    if (widget.isSelected) {
      bgColor = selectedBg;
    } else if (_hovering) {
      bgColor = c.surfaceHover;
    } else {
      bgColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (event) {
          // 鼠标按下即选中：避免 onTap 等待双击判定（kDoubleTapTimeout）的延迟
          if (event.buttons & kPrimaryMouseButton != 0) {
            widget.onSingleTap();
          }
        },
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: (details) =>
              widget.onRightClick?.call(details.globalPosition),
          child: SizedBox(
            height: AppMetrics.rowHeight,
          child: Row(
            children: [
              // 浮动选中条：圆角 + 左右内缩（Win11 资源管理器风格）
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: widget.columnWidths[0],
                        child: Row(
                          children: [
                            _FileIcon(
                              path: widget.entry.path,
                              isDirectory: widget.entry.isDirectory,
                              isSelected: widget.isSelected && widget.isActive,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.entry.name,
                                style: TextStyle(
                                  fontSize: AppMetrics.fontBody,
                                  color: textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.showStatusColumn)
                        SizedBox(
                          width: _statusColWidth,
                          child: _CloudStatusCell(path: widget.entry.path),
                        ),
                      SizedBox(
                        width: widget.columnWidths[1],
                        child: Text(
                          widget.entry.formattedDate,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: widget.columnWidths[2],
                        child: Text(
                          widget.entry.type,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: widget.columnWidths[3],
                        child: Text(
                          widget.entry.formattedSize,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: widget.blankWidth),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ── File Icon (real system icon + shell overlay) ─────────────────────

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
    final c = context.colors;
    const iconSize = AppMetrics.iconMd; // 16
    const badgeSize = 10.0;

    final png = IconService.getFileIconPng(path, isDirectory, 32);
    final overlayPng = IconService.getFileOverlayPng(path, 16);

    final Widget base = png != null
        ? Image.memory(
            png,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
          )
        : Icon(
            isDirectory ? Icons.folder : Icons.insert_drive_file,
            size: iconSize,
            color: isSelected
                ? Colors.white
                : (isDirectory ? c.iconFolder : c.iconFile),
          );

    if (overlayPng == null) {
      return SizedBox(width: iconSize, height: iconSize, child: base);
    }

    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base,
          Positioned(
            left: -2,
            bottom: -2,
            child: Image.memory(
              overlayPng,
              width: badgeSize,
              height: badgeSize,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cloud sync status column ───────────────────────────────────────

/// 云同步状态语义编码（见 IconService.getCloudStatus）：
/// 0 仅联机 / 1 本地可用 / 2 固定保留 / 3 同步中 / 4 已排除。
(IconData, Color) _cloudStatusVisual(int status, AppColors c) =>
    switch (status) {
      2 => (Icons.check_circle, c.success), // pinned / always available
      1 => (Icons.cloud_done, c.accent), // locally available
      3 => (Icons.sync, c.accent), // syncing
      0 => (Icons.cloud, c.textSecondary), // online only
      4 => (Icons.remove_circle_outline, c.textTertiary), // excluded
      _ => (Icons.cloud, c.textTertiary),
    };

String _cloudStatusText(int status) => switch (status) {
      2 => '始终保留在此设备上',
      1 => '本地可用',
      3 => '正在同步',
      0 => '仅联机可用',
      4 => '已排除（不同步）',
      _ => '云文件',
    };

/// 详情视图"状态"列单元：按云同步状态渲染图标（带 tooltip）。
/// 非云条目（-1）留空，与资源管理器一致。
class _CloudStatusCell extends StatelessWidget {
  final String path;

  const _CloudStatusCell({required this.path});

  @override
  Widget build(BuildContext context) {
    final status = IconService.getCloudStatus(path);
    if (status < 0) return const SizedBox.shrink();
    final (icon, color) = _cloudStatusVisual(status, context.colors);
    return Center(
      child: Tooltip(
        message: _cloudStatusText(status),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
