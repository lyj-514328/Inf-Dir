import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/file_entry.dart';
import '../services/icon_service.dart';
import '../state/pane_controller.dart';
import 'app_theme.dart';

/// 云同步"状态"列的固定宽度（不参与列宽拖拽）。
const double _statusColWidth = 48;

String _displayEntryName(String name, bool showFileExtensions) {
  if (showFileExtensions) return name;
  final extension = p.extension(name);
  return extension.isEmpty ? name : p.basenameWithoutExtension(name);
}

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
  final PaneViewMode viewMode;
  final bool showFileExtensions;

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
    this.viewMode = PaneViewMode.details,
    this.showFileExtensions = true,
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

  void _handleResize(int colIndex, double delta) {
    final newW = (widget.columnWidths[colIndex] + delta).clamp(
      40.0,
      double.infinity,
    );
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

    if (_isIconMode(widget.viewMode)) {
      return _buildIconView(context);
    }
    if (widget.viewMode == PaneViewMode.tiles ||
        widget.viewMode == PaneViewMode.content) {
      return _buildCardList(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _paneWidth = constraints.maxWidth;
        if (!_widthsInitialized &&
            _paneWidth > 0 &&
            widget.onInitWidths != null) {
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
                      viewMode: widget.viewMode,
                      showStatusColumn: widget.showStatusColumn,
                    ),
                    Container(height: 1, color: context.colors.border),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapUp: (details) {
                          widget.onEmptyRightClick?.call(
                            details.globalPosition,
                          );
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
                                      isSelected: widget.selectedPaths.contains(
                                        entry.path,
                                      ),
                                      isActive: widget.isActive,
                                      columnWidths: widget.columnWidths,
                                      blankWidth: blankW,
                                      viewMode: widget.viewMode,
                                      showFileExtensions:
                                          widget.showFileExtensions,
                                      showStatusColumn: widget.showStatusColumn,
                                      onSingleTap: () =>
                                          widget.onSingleTap(entry.path),
                                      onDoubleTap: () =>
                                          widget.onDoubleTap(entry.path),
                                      onRightClick: (pos) => widget
                                          .onItemRightClick
                                          ?.call(entry.path, pos),
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

  bool _isIconMode(PaneViewMode mode) => switch (mode) {
    PaneViewMode.extraLargeIcons ||
    PaneViewMode.largeIcons ||
    PaneViewMode.mediumIcons ||
    PaneViewMode.smallIcons ||
    PaneViewMode.compact => true,
    _ => false,
  };

  ({double iconSize, double tileWidth, double tileHeight, bool horizontal})
  _iconSpec(PaneViewMode mode) => switch (mode) {
    PaneViewMode.extraLargeIcons => (
      iconSize: 96,
      tileWidth: 158,
      tileHeight: 142,
      horizontal: false,
    ),
    PaneViewMode.largeIcons => (
      iconSize: 64,
      tileWidth: 132,
      tileHeight: 108,
      horizontal: false,
    ),
    PaneViewMode.mediumIcons => (
      iconSize: 44,
      tileWidth: 112,
      tileHeight: 84,
      horizontal: false,
    ),
    PaneViewMode.smallIcons || PaneViewMode.compact => (
      iconSize: 20,
      tileWidth: 190,
      tileHeight: 38,
      horizontal: true,
    ),
    _ => (iconSize: 44, tileWidth: 112, tileHeight: 84, horizontal: false),
  };

  Widget _buildIconView(BuildContext context) {
    final spec = _iconSpec(widget.viewMode);
    return _FileSurface(
      scrollController: _vScrollController,
      scrollbarVisible: _scrollbarHovered,
      onHoverChanged: (hovering) {
        if (_scrollbarHovered != hovering) {
          setState(() => _scrollbarHovered = hovering);
        }
      },
      onEmptyRightClick: widget.onEmptyRightClick,
      empty: widget.entries.isEmpty,
      child: GridView.builder(
        controller: _vScrollController,
        padding: const EdgeInsets.all(6),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: spec.tileWidth,
          mainAxisExtent: spec.tileHeight,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: widget.entries.length,
        itemBuilder: (context, index) {
          final entry = widget.entries[index];
          return _ExplorerTile(
            entry: entry,
            iconSize: spec.iconSize,
            horizontal: spec.horizontal,
            showFileExtensions: widget.showFileExtensions,
            isSelected: widget.selectedPaths.contains(entry.path),
            isActive: widget.isActive,
            onSingleTap: () => widget.onSingleTap(entry.path),
            onDoubleTap: () => widget.onDoubleTap(entry.path),
            onRightClick: (position) =>
                widget.onItemRightClick?.call(entry.path, position),
          );
        },
      ),
    );
  }

  Widget _buildCardList(BuildContext context) {
    final contentMode = widget.viewMode == PaneViewMode.content;
    if (!contentMode && widget.viewMode == PaneViewMode.tiles) {
      return _buildTileGrid(context);
    }
    return _FileSurface(
      scrollController: _vScrollController,
      scrollbarVisible: _scrollbarHovered,
      onHoverChanged: (hovering) {
        if (_scrollbarHovered != hovering) {
          setState(() => _scrollbarHovered = hovering);
        }
      },
      onEmptyRightClick: widget.onEmptyRightClick,
      empty: widget.entries.isEmpty,
      child: ListView.builder(
        controller: _vScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemExtent: contentMode ? 68 : 58,
        itemCount: widget.entries.length,
        itemBuilder: (context, index) {
          final entry = widget.entries[index];
          return _ExplorerContentRow(
            entry: entry,
            contentMode: contentMode,
            showFileExtensions: widget.showFileExtensions,
            isSelected: widget.selectedPaths.contains(entry.path),
            isActive: widget.isActive,
            onSingleTap: () => widget.onSingleTap(entry.path),
            onDoubleTap: () => widget.onDoubleTap(entry.path),
            onRightClick: (position) =>
                widget.onItemRightClick?.call(entry.path, position),
          );
        },
      ),
    );
  }

  Widget _buildTileGrid(BuildContext context) {
    return _FileSurface(
      scrollController: _vScrollController,
      scrollbarVisible: _scrollbarHovered,
      onHoverChanged: (hovering) {
        if (_scrollbarHovered != hovering) {
          setState(() => _scrollbarHovered = hovering);
        }
      },
      onEmptyRightClick: widget.onEmptyRightClick,
      empty: widget.entries.isEmpty,
      child: GridView.builder(
        controller: _vScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 286,
          mainAxisExtent: 64,
          crossAxisSpacing: 5,
          mainAxisSpacing: 3,
        ),
        itemCount: widget.entries.length,
        itemBuilder: (context, index) {
          final entry = widget.entries[index];
          return _ExplorerContentRow(
            entry: entry,
            contentMode: false,
            showFileExtensions: widget.showFileExtensions,
            isSelected: widget.selectedPaths.contains(entry.path),
            isActive: widget.isActive,
            onSingleTap: () => widget.onSingleTap(entry.path),
            onDoubleTap: () => widget.onDoubleTap(entry.path),
            onRightClick: (position) =>
                widget.onItemRightClick?.call(entry.path, position),
          );
        },
      ),
    );
  }
}

class _FileSurface extends StatelessWidget {
  final ScrollController scrollController;
  final bool scrollbarVisible;
  final ValueChanged<bool> onHoverChanged;
  final Function(Offset globalPosition)? onEmptyRightClick;
  final bool empty;
  final Widget child;

  const _FileSurface({
    required this.scrollController,
    required this.scrollbarVisible,
    required this.onHoverChanged,
    required this.onEmptyRightClick,
    required this.empty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) =>
            onEmptyRightClick?.call(details.globalPosition),
        child: empty
            ? Center(
                child: Text(
                  '空文件夹',
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: context.colors.textTertiary,
                  ),
                ),
              )
            : Scrollbar(
                controller: scrollController,
                thumbVisibility: scrollbarVisible,
                child: child,
              ),
      ),
    );
  }
}

// ── Column Header ────────────────────────────────────────────────────

class _ExplorerTile extends StatefulWidget {
  final FileEntry entry;
  final double iconSize;
  final bool horizontal;
  final bool showFileExtensions;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onRightClick;

  const _ExplorerTile({
    required this.entry,
    required this.iconSize,
    required this.horizontal,
    required this.showFileExtensions,
    required this.isSelected,
    required this.isActive,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  State<_ExplorerTile> createState() => _ExplorerTileState();
}

class _ExplorerTileState extends State<_ExplorerTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 大图标瓦片用 accentSubtle 软底 + accent 描边表示选中，
    // 避免整瓦片实心 accent 过重；失焦面板用 selectedInactive。
    final selectedBg = widget.isActive ? c.accentSubtle : c.selectedInactive;
    final foreground = c.textPrimary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
        },
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: (details) =>
              widget.onRightClick?.call(details.globalPosition),
          child: Container(
            margin: const EdgeInsets.all(1),
            padding: widget.horizontal
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : const EdgeInsets.fromLTRB(6, 6, 6, 5),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? selectedBg
                  : _hovering
                  ? c.surfaceHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              border: Border.all(
                color: widget.isSelected && widget.isActive
                    ? c.accent
                    : Colors.transparent,
              ),
            ),
            child: widget.horizontal
                ? Row(
                    children: [
                      _FileIcon(
                        path: widget.entry.path,
                        isDirectory: widget.entry.isDirectory,
                        isSelected: false,
                        size: widget.iconSize,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _displayEntryName(
                            widget.entry.name,
                            widget.showFileExtensions,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _FileIcon(
                            path: widget.entry.path,
                            isDirectory: widget.entry.isDirectory,
                            isSelected: false,
                            size: widget.iconSize,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displayEntryName(
                          widget.entry.name,
                          widget.showFileExtensions,
                        ),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMetrics.fontBody,
                          color: foreground,
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

class _ExplorerContentRow extends StatefulWidget {
  final FileEntry entry;
  final bool contentMode;
  final bool showFileExtensions;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset>? onRightClick;

  const _ExplorerContentRow({
    required this.entry,
    required this.contentMode,
    required this.showFileExtensions,
    required this.isSelected,
    required this.isActive,
    required this.onSingleTap,
    required this.onDoubleTap,
    this.onRightClick,
  });

  @override
  State<_ExplorerContentRow> createState() => _ExplorerContentRowState();
}

class _ExplorerContentRowState extends State<_ExplorerContentRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 与 _ExplorerTile 一致：选中 = accentSubtle 软底 + accent 描边，
    // 失焦面板 = selectedInactive；文字保持 textPrimary/textSecondary。
    final selectedBg = widget.isActive ? c.accentSubtle : c.selectedInactive;
    final foreground = c.textPrimary;
    final secondary = c.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kPrimaryMouseButton != 0) widget.onSingleTap();
        },
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: (details) =>
              widget.onRightClick?.call(details.globalPosition),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? selectedBg
                  : _hovering
                  ? c.surfaceHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
              border: Border.all(
                color: widget.isSelected && widget.isActive
                    ? c.accent
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _FileIcon(
                  path: widget.entry.path,
                  isDirectory: widget.entry.isDirectory,
                  isSelected: false,
                  size: widget.contentMode ? 40 : 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayEntryName(
                          widget.entry.name,
                          widget.showFileExtensions,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMetrics.fontBody,
                          fontWeight: FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.entry.isDirectory
                            ? widget.entry.type
                            : '${widget.entry.type}  ${widget.entry.formattedSize}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMetrics.fontSmall,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.contentMode) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      widget.entry.formattedDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppMetrics.fontSmall,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final SortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<SortColumn> onSort;
  final List<double> columnWidths;
  final double blankWidth;
  final Function(int colIndex, double deltaPx) onResizeColumn;
  final PaneViewMode viewMode;
  final bool showStatusColumn;

  const _ColumnHeader({
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.blankWidth,
    required this.onResizeColumn,
    this.viewMode = PaneViewMode.details,
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
    if (viewMode == PaneViewMode.list) {
      return SizedBox(
        height: AppMetrics.rowHeight,
        child: Row(
          children: [
            _HeaderCell(
              label: '名称',
              width: columnWidths[0],
              column: SortColumn.name,
              sortColumn: sortColumn,
              sortAscending: sortAscending,
              onSort: onSort,
            ),
            SizedBox(width: blankWidth),
          ],
        ),
      );
    }
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
                            fontSize: AppMetrics.fontSmall,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textTertiary,
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
                _HeaderSplitter(colIndex: 3, onResizeColumn: onResizeColumn),
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

  const _HeaderSplitter({required this.colIndex, required this.onResizeColumn});

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
              color: _hovering || _dragging
                  ? c.borderStrong
                  : Colors.transparent,
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
                    fontSize: AppMetrics.fontSmall,
                    fontWeight: FontWeight.w500,
                    color: isActive ? c.textSecondary : c.textTertiary,
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
  final PaneViewMode viewMode;
  final bool showFileExtensions;
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
    this.viewMode = PaneViewMode.details,
    required this.showFileExtensions,
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
        ? (widget.isActive ? c.onAccent : c.textPrimary)
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
                      borderRadius: BorderRadius.circular(
                        AppMetrics.controlRadius,
                      ),
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
                                isSelected:
                                    widget.isSelected && widget.isActive,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _displayEntryName(
                                    widget.entry.name,
                                    widget.showFileExtensions,
                                  ),
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
                        if (widget.viewMode != PaneViewMode.list) ...[
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
  final double size;

  const _FileIcon({
    required this.path,
    required this.isDirectory,
    required this.isSelected,
    this.size = AppMetrics.iconMd,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final iconSize = size;
    final badgeSize = (size * 0.42).clamp(8.0, 22.0);

    final png = IconService.getFileIconPng(path, isDirectory, iconSize.round());
    final overlayPng = IconService.getFileOverlayPng(path, badgeSize.round());

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
                ? c.onAccent
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
      1 => (Icons.cloud_done, c.success), // locally available
      3 => (Icons.sync, c.textTertiary), // syncing
      0 => (Icons.cloud, c.textTertiary), // online only
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
        child: Icon(icon, size: AppMetrics.iconSm, color: color),
      ),
    );
  }
}
