import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../services/sidebar_service.dart';
import '../services/icon_service.dart';
import '../services/file_service.dart';
import '../state/sidebar_controller.dart';
import '../utils/path_utils.dart';
import 'app_theme.dart';
import 'home_icon.dart';

enum _RowType { home, thisPc, drive, cloudDrive, directory, loadingIndicator }

class _TreeRow {
  final _RowType type;
  final String path;
  final String name;
  final int depth;
  final bool isExpanded;
  final bool hasChildren;
  const _TreeRow({
    required this.type,
    required this.path,
    required this.name,
    required this.depth,
    required this.isExpanded,
    required this.hasChildren,
  });
}

/// 纯渲染层（§8 / §15 阶段五）：只展示 SidebarSyncController 的状态、
/// 转发点击事件。不碰 FFI、不存 session id、不在 build 里做同步 probe、
/// 不在异步函数里改 cache。
///
/// 虚拟化方案（docs §18 的替代）：不用 sliver，整个内容区是一个
/// SingleChildScrollView + 纯算术高度的 SizedBox，内部用 Stack/Positioned
/// 只物化可见窗口 ±缓存带的行。maxScrollExtent 由总行数纯算，永远准确，
/// 不存在 SliverMultiBoxAdaptorElement 的 layout 跳过问题。
class SidebarTree extends StatefulWidget {
  final ValueChanged<String> onNavigate;

  const SidebarTree({super.key, required this.onNavigate});

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

/// State 只拥有 ScrollController 与虚拟化窗口状态；业务状态全在
/// SidebarSyncController。
class _SidebarTreeState extends State<SidebarTree> {
  static const _thisPcGuid = SidebarSyncController.thisPcGuid;

  // ── 布局常量：整个侧栏内容按固定行高排布 ──────────────────
  static const double _rowHeight = AppMetrics.sidebarRowHeight;
  static const double _homeRowHeight = _rowHeight;
  static const double _homeDividerHeight = 1;
  static const double _homeGapHeight = 4;
  static const double _quickAccessHeaderHeight =
      AppMetrics.quickAccessHeaderHeight;
  static const double _dividerHeight = 1.0;
  static const double _gapHeight = 4.0;

  /// 视口外额外物化的行数（缓存带）。
  static const int _cacheRows = 8;

  final ScrollController _scrollController = ScrollController();
  List<_TreeRow> _treeItems = [];

  // build 时更新的窗口状态；滚动监听据此重建可见行。
  int _qaCount = 0;
  int _treeCount = 0;
  int _firstVisibleTreeIndex = 0;
  int _lastVisibleTreeIndex = 0;

  /// 最近一次程序自动 jumpTo 的 pixels；用户手动滚动会使其失效。
  double? _lastAutoJumpPixels;
  SidebarSyncController? _sidebar;

  /// 鼠标悬停在侧栏面板上时显示滚动条。
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  虚拟化：index ↔ offset 纯算术
  // ═══════════════════════════════════════════════════════════

  /// 内容区布局 index 空间（顶部起）：
  ///   [0] 快速访问头          _quickAccessHeaderHeight
  ///   [1, qaCount) 快速访问行 _rowHeight × qaCount
  ///   divider                _dividerHeight
  ///   gap                    _gapHeight
  ///   之后是树行             _rowHeight × treeCount
  /// 总高度是纯函数，不依赖 layout 结果，maxScrollExtent 永远准确。

  double _quickAccessStartOffset() =>
      _homeRowHeight + _homeDividerHeight + _homeGapHeight;

  double _treeStartOffset(int qaCount) =>
      _quickAccessStartOffset() +
      _quickAccessHeaderHeight +
      qaCount * _rowHeight +
      _dividerHeight +
      _gapHeight;

  double _totalHeight(int qaCount, int treeCount) =>
      _treeStartOffset(qaCount) + treeCount * _rowHeight;

  (int, int) _visibleWindow(double scrollOffset, double viewportHeight) {
    final startOffset = _treeStartOffset(_qaCount);
    final start =
        (((scrollOffset - startOffset) / _rowHeight).floor() - _cacheRows)
            .clamp(0, _treeCount)
            .toInt();
    final end =
        (((scrollOffset + viewportHeight - startOffset) / _rowHeight).ceil() +
                _cacheRows)
            .clamp(0, _treeCount)
            .toInt();
    return (start, end);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    // 用户手动滚动（非程序 jumpTo）：停止本次同步的自动跟随。
    if (_lastAutoJumpPixels != null && position.pixels != _lastAutoJumpPixels) {
      _lastAutoJumpPixels = null;
      final sidebar = _sidebar;
      if (sidebar != null && sidebar.needsScrollToSelected) {
        sidebar.dismissScrollFollow();
      }
    }

    final (start, end) = _visibleWindow(
      position.pixels,
      position.viewportDimension,
    );
    if (start != _firstVisibleTreeIndex || end != _lastVisibleTreeIndex) {
      setState(() {
        _firstVisibleTreeIndex = start;
        _lastVisibleTreeIndex = end;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Tree flattening (reads controller memory state only)
  // ═══════════════════════════════════════════════════════════

  List<_TreeRow> _flattenTree(SidebarSyncController sidebar) {
    final rows = <_TreeRow>[];
    rows.add(
      const _TreeRow(
        type: _RowType.home,
        path: FileService.homeViewPath,
        name: '主文件夹',
        depth: 0,
        isExpanded: false,
        hasChildren: false,
      ),
    );
    rows.add(
      _TreeRow(
        type: _RowType.thisPc,
        path: _thisPcGuid,
        name: '此电脑',
        depth: 0,
        isExpanded: sidebar.thisPcExpanded,
        hasChildren: sidebar.driveRoots.isNotEmpty,
      ),
    );
    if (sidebar.thisPcExpanded) {
      for (final drive in sidebar.driveRoots) {
        final expanded = sidebar.isExpanded(drive);
        final label = SidebarService.formatDriveLabel(drive);
        rows.add(
          _TreeRow(
            type: _RowType.drive,
            path: drive,
            name: label,
            depth: 1,
            isExpanded: expanded,
            hasChildren: sidebar.hasChildrenFor(drive),
          ),
        );
        if (expanded) {
          _flattenDir(
            sidebar,
            sidebar.childrenFor(drive),
            2,
            rows,
            parentPath: drive,
          );
        }
      }
    }
    // 云盘同步根：顶层节点，排在"此电脑"子树之后（资源管理器里 OneDrive
    // 与"此电脑"平级）。云盘根是真实目录，展开/子节点复用目录分支逻辑。
    for (final cloud in sidebar.cloudDrives) {
      final expanded = sidebar.isExpanded(cloud.path);
      rows.add(
        _TreeRow(
          type: _RowType.cloudDrive,
          path: cloud.path,
          name: cloud.name,
          depth: 0,
          isExpanded: expanded,
          hasChildren: sidebar.hasChildrenFor(cloud.path),
        ),
      );
      if (expanded) {
        _flattenDir(
          sidebar,
          sidebar.childrenFor(cloud.path),
          1,
          rows,
          parentPath: cloud.path,
        );
      }
    }
    return rows;
  }

  void _flattenDir(
    SidebarSyncController sidebar,
    List<FileEntry> dirs,
    int depth,
    List<_TreeRow> out, {
    required String parentPath,
  }) {
    for (final dir in dirs) {
      final expanded = sidebar.isExpanded(dir.path);
      out.add(
        _TreeRow(
          type: _RowType.directory,
          path: dir.path,
          name: dir.name,
          depth: depth,
          isExpanded: expanded,
          // 枚举元数据自带 hasChildren，build 不需要 probe（§13.1）。
          hasChildren: dir.hasChildren,
        ),
      );
      if (expanded) {
        final children = sidebar.childrenFor(dir.path);
        if (children.isNotEmpty) {
          _flattenDir(sidebar, children, depth + 1, out, parentPath: dir.path);
        }
      }
    }
    if (sidebar.isLoading(parentPath)) {
      out.add(
        _TreeRow(
          type: _RowType.loadingIndicator,
          path: '',
          name: '',
          depth: depth + 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Scroll to selected
  // ═══════════════════════════════════════════════════════════

  /// 滚动请求采用「落点稳定才消费」的重试语义：
  /// - 目标行尚未挂上树（祖先仍在加载）→ 保留请求，等下次 partial 更新重试；
  /// - 目标行之前还有 loading 节点 → 行号还会变，跳但保留请求；
  /// - 目标行之前无 loading → 行号稳定，跳转并消费。
  /// 目标行 offset 是纯算术，jumpTo 后触发 _onScroll 重建窗口，
  /// 目标行在该帧物化。不再依赖 maxScrollExtent（sliver 时代它可能过期）。
  void _tryScrollToSelected(SidebarSyncController sidebar) {
    if (!sidebar.needsScrollToSelected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final selected = sidebar.selectedPath ?? '';
      double? offset;
      if (FileService.isHomePath(selected)) {
        offset = 0;
        sidebar.consumeScrollRequest();
      }
      final qaIndex = sidebar.quickAccessItems.indexWhere(
        (item) => pathEquals(item.path, selected),
      );
      if (offset == null && qaIndex >= 0) {
        // 快速访问行固定，offset 永远稳定，直接消费。
        offset = _quickAccessHeaderHeight + qaIndex * _rowHeight;
        sidebar.consumeScrollRequest();
      } else if (offset == null) {
        final treeIndex = _treeItems.indexWhere(
          (item) => pathEquals(item.path, selected),
        );
        if (treeIndex < 0) return; // 目标行未挂上树：保留请求，等待重试。
        offset = _treeStartOffset(_qaCount) + treeIndex * _rowHeight;
        if (treeIndex == 0) return;
        offset = _treeStartOffset(_qaCount) + (treeIndex - 1) * _rowHeight;
        if (!_hasLoadingBefore(treeIndex)) {
          sidebar.consumeScrollRequest();
        }
      }

      final position = _scrollController.position;
      final viewportHeight = position.viewportDimension;
      final maxScroll = (_totalHeight(_qaCount, _treeCount) - viewportHeight)
          .clamp(0.0, double.infinity);
      final centeredOffset = offset - viewportHeight / 2 + _rowHeight / 2;
      final target = centeredOffset.clamp(0.0, maxScroll);
      _lastAutoJumpPixels = target;
      position.jumpTo(target);
    });
  }

  /// selected 行之前是否存在加载中的节点（loadingIndicator 行）。
  bool _hasLoadingBefore(int treeIndex) {
    for (var i = 0; i < treeIndex; i++) {
      if (_treeItems[i].type == _RowType.loadingIndicator) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  //  Event forwarding
  // ═══════════════════════════════════════════════════════════

  void _onTapTreeRow(SidebarSyncController sidebar, _TreeRow row) {
    if (row.type == _RowType.loadingIndicator) return;
    sidebar.select(row.path);
    widget.onNavigate(row.path);
    if (row.hasChildren) {
      if (row.type == _RowType.thisPc) {
        sidebar.toggleThisPc();
      } else {
        sidebar.toggleExpand(row.path);
      }
    }
  }

  void _onTapQuickAccess(SidebarSyncController sidebar, QuickAccessItem item) {
    sidebar.select(item.path);
    widget.onNavigate(item.path);
  }

  // ═══════════════════════════════════════════════════════════
  //  Row builders
  // ═══════════════════════════════════════════════════════════

  IconData _fallbackIcon(_RowType type) {
    switch (type) {
      case _RowType.home:
        return Icons.home;
      case _RowType.thisPc:
        return Icons.computer;
      case _RowType.drive:
        return Icons.storage;
      case _RowType.cloudDrive:
        return Icons.cloud;
      case _RowType.directory:
        return Icons.folder;
      case _RowType.loadingIndicator:
        return Icons.hourglass_empty;
    }
  }

  bool _isSelected(SidebarSyncController sidebar, String path) =>
      sidebar.selectedPath != null && pathEquals(sidebar.selectedPath!, path);

  Widget _buildTreeRow(SidebarSyncController sidebar, int index) {
    final c = context.colors;
    final row = _treeItems[index];

    if (row.type == _RowType.loadingIndicator) {
      return Container(
        height: _rowHeight,
        width: double.infinity,
        padding: EdgeInsets.only(left: 8.0 + row.depth * 16.0),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const SizedBox(
              width: 15,
              height: 15,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Loading...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: c.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isSelected = _isSelected(sidebar, row.path);
    final fallback = _fallbackIcon(row.type);
    // 顶层节点（此电脑 / 云盘根）按分区头样式渲染：小号加宽 tertiary 文字。
    final isSectionHeader = row.depth == 0 &&
        (row.type == _RowType.thisPc || row.type == _RowType.cloudDrive);
    final textStyle = isSectionHeader
        ? TextStyle(
            fontSize: AppMetrics.fontSmall,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: isSelected ? c.accent : c.textTertiary,
          )
        : TextStyle(
            fontSize: AppMetrics.fontBody,
            color: isSelected ? c.accent : c.textPrimary,
          );
    final pillRadius = BorderRadius.circular(AppMetrics.controlRadius);
    // 选中态为圆角 pill（accentSubtle 底），hover 为 surfaceHover pill，
    // 不再使用左侧 3px accent 竖条。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: pillRadius,
        child: InkWell(
          onTap: () => _onTapTreeRow(sidebar, row),
          hoverColor: isSelected ? Colors.transparent : c.surfaceHover,
          borderRadius: pillRadius,
          child: Container(
            height: double.infinity,
            width: double.infinity,
            decoration: isSelected
                ? BoxDecoration(color: c.accentSubtle, borderRadius: pillRadius)
                : null,
            child: Row(
              children: [
                SizedBox(width: 8.0 + row.depth * 16.0),
                if (row.hasChildren)
                  Icon(
                    row.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 12,
                    color: c.textTertiary,
                  )
                else
                  const SizedBox(width: 12),
                const SizedBox(width: 2),
                SizedBox(
                  width: 15,
                  child: _ShellIcon(
                    path: row.path,
                    isDirectory: true,
                    fallback: fallback,
                    selected: isSelected,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.name,
                    style: textStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _quickAccessFallbackIcon(String name) {
    if (name.contains('桌面')) return Icons.desktop_windows;
    if (name.contains('下载')) return Icons.download;
    if (name.contains('文档')) return Icons.description;
    if (name.contains('图片')) return Icons.image;
    if (name.contains('音乐')) return Icons.music_note;
    if (name.contains('视频')) return Icons.videocam;
    if (name.contains('回收站')) return Icons.delete_outline;
    return Icons.folder;
  }

  // ═══════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final sidebar = context.watch<SidebarSyncController>();
    _sidebar = sidebar;
    final c = context.colors;

    final sw = Stopwatch()..start();
    _treeItems = _flattenTree(sidebar);
    _qaCount = sidebar.quickAccessItems.length;
    _treeCount = _treeItems.isEmpty ? 0 : _treeItems.length - 1;
    final flattenMs = sw.elapsedMilliseconds;
    _tryScrollToSelected(sidebar);

    final result = LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final scrollOffset = _scrollController.hasClients
            ? _scrollController.position.pixels
            : 0.0;
        final (first, last) = _visibleWindow(scrollOffset, viewportHeight);
        _firstVisibleTreeIndex = first;
        _lastVisibleTreeIndex = last;

        final stackChildren = <Widget>[];

        stackChildren.add(
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _homeRowHeight,
            child: _HomeSidebarRow(
              selected: _isSelected(sidebar, FileService.homeViewPath),
              onTap: () {
                sidebar.select(FileService.homeViewPath);
                widget.onNavigate(FileService.homeViewPath);
              },
            ),
          ),
        );
        stackChildren.add(
          Positioned(
            top: _homeRowHeight,
            left: 0,
            right: 0,
            height: _homeDividerHeight,
            child: ColoredBox(color: c.border),
          ),
        );

        final quickAccessStart = _quickAccessStartOffset();

        stackChildren.add(
          Positioned(
            top: quickAccessStart,
            left: 0,
            right: 0,
            height: _quickAccessHeaderHeight,
            child: const _QuickAccessHeader(),
          ),
        );
        for (var i = 0; i < _qaCount; i++) {
          final item = sidebar.quickAccessItems[i];
          stackChildren.add(
            Positioned(
              top: quickAccessStart + _quickAccessHeaderHeight + i * _rowHeight,
              left: 0,
              right: 0,
              height: _rowHeight,
              child: _QuickAccessRow(
                item: item,
                selected: _isSelected(sidebar, item.path),
                fallbackIcon: _quickAccessFallbackIcon(item.name),
                onTap: () => _onTapQuickAccess(sidebar, item),
              ),
            ),
          );
        }

        final qaBottom =
            quickAccessStart + _quickAccessHeaderHeight + _qaCount * _rowHeight;
        stackChildren.add(
          Positioned(
            top: qaBottom,
            left: 0,
            right: 0,
            height: _dividerHeight,
            child: const Divider(height: 1, thickness: 1),
          ),
        );
        stackChildren.add(
          Positioned(
            top: qaBottom + _dividerHeight,
            left: 0,
            right: 0,
            height: _gapHeight,
            child: const SizedBox(),
          ),
        );

        final treeStartOffset = _treeStartOffset(_qaCount);
        for (var i = first; i < last; i++) {
          stackChildren.add(
            Positioned(
              top: treeStartOffset + i * _rowHeight,
              left: 0,
              right: 0,
              height: _rowHeight,
              child: _buildTreeRow(sidebar, i + 1),
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(color: c.surfaceSubtle),
            alignment: Alignment.topLeft,
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: _hovered,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SizedBox(
                  height: _totalHeight(_qaCount, _treeCount),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: stackChildren,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    sw.stop();
    if (sw.elapsedMilliseconds > 10) {
      debugPrint(
        '[Perf] SidebarTree build: flatten=${flattenMs}ms, total=${sw.elapsedMilliseconds}ms',
      );
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════════════
//  Private widgets
// ═══════════════════════════════════════════════════════════

class _HomeSidebarRow extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _HomeSidebarRow({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pillRadius = BorderRadius.circular(AppMetrics.controlRadius);
    // 与快速访问项保持相同的行高、缩进和文字层级。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: pillRadius,
        child: InkWell(
          onTap: onTap,
          hoverColor: selected ? Colors.transparent : c.surfaceHover,
          borderRadius: pillRadius,
          child: Container(
            height: double.infinity,
            width: double.infinity,
            decoration: selected
                ? BoxDecoration(color: c.accentSubtle, borderRadius: pillRadius)
                : null,
            child: Row(
              children: [
                const SizedBox(width: 8),
                const SizedBox(width: 12),
                const SizedBox(width: 2),
                const SizedBox(width: 15, child: HomeIcon(size: 15)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '主文件夹',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: selected ? c.accent : c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellIcon extends StatelessWidget {
  static const _iconSize = 15;
  final String path;
  final bool isDirectory;
  final IconData fallback;
  final bool selected;

  const _ShellIcon({
    required this.path,
    required this.isDirectory,
    required this.fallback,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final sourceSize = (_iconSize * View.of(context).devicePixelRatio).ceil();
    final bytes = IconService.getFileIconPng(path, isDirectory, sourceSize);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: _iconSize.toDouble(),
        height: _iconSize.toDouble(),
        gaplessPlayback: true,
      );
    }
    // 无 shell 图标时 fallback 到 Material 图标，选中态染 accent。
    return Icon(
      fallback,
      size: _iconSize.toDouble(),
      color: selected ? context.colors.accent : context.colors.iconFolder,
    );
  }
}

class _QuickAccessHeader extends StatelessWidget {
  const _QuickAccessHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 分区头：小号加宽 tertiary 文字，24px 槽位内垂直居中。
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      alignment: Alignment.centerLeft,
      child: Text(
        '快速访问',
        style: TextStyle(
          fontSize: AppMetrics.fontSmall,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: c.textTertiary,
        ),
      ),
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  final QuickAccessItem item;
  final bool selected;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const _QuickAccessRow({
    required this.item,
    required this.selected,
    required this.fallbackIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pillRadius = BorderRadius.circular(AppMetrics.controlRadius);
    // 与树行一致的 pill 选中态 / hover 态。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: pillRadius,
        child: InkWell(
          onTap: onTap,
          hoverColor: selected ? Colors.transparent : c.surfaceHover,
          borderRadius: pillRadius,
          child: Container(
            height: double.infinity,
            width: double.infinity,
            decoration: selected
                ? BoxDecoration(color: c.accentSubtle, borderRadius: pillRadius)
                : null,
            child: Row(
              children: [
                const SizedBox(width: 8),
                const SizedBox(width: 12),
                const SizedBox(width: 2),
                SizedBox(
                  width: 15,
                  child: _ShellIcon(
                    path: item.path,
                    isDirectory: true,
                    fallback: fallbackIcon,
                    selected: selected,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: selected ? c.accent : c.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.isPinned)
                  Icon(Icons.push_pin, size: 11, color: c.textTertiary),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
