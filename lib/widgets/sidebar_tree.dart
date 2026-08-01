import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../services/sidebar_service.dart';
import '../services/icon_service.dart';
import '../state/sidebar_controller.dart';
import '../utils/path_utils.dart';

enum _RowType { thisPc, drive, directory, loadingIndicator }

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

  const SidebarTree({
    super.key,
    required this.onNavigate,
  });

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

/// State 只拥有 ScrollController 与虚拟化窗口状态；业务状态全在
/// SidebarSyncController。
class _SidebarTreeState extends State<SidebarTree> {
  static const _thisPcGuid = SidebarSyncController.thisPcGuid;

  // ── 布局常量：整个侧栏内容按固定行高排布 ──────────────────
  static const double _rowHeight = 22.0;
  static const double _quickAccessHeaderHeight = 20.0;
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
  ///   [1, qaCount) 快速访问行 22 × qaCount
  ///   divider                _dividerHeight
  ///   gap                    _gapHeight
  ///   之后是树行               22 × treeCount
  /// 总高度是纯函数，不依赖 layout 结果，maxScrollExtent 永远准确。

  double _treeStartOffset(int qaCount) =>
      _quickAccessHeaderHeight + qaCount * _rowHeight + _dividerHeight + _gapHeight;

  double _totalHeight(int qaCount, int treeCount) =>
      _treeStartOffset(qaCount) + treeCount * _rowHeight;

  (int, int) _visibleWindow(double scrollOffset, double viewportHeight) {
    final startOffset = _treeStartOffset(_qaCount);
    final start = (((scrollOffset - startOffset) / _rowHeight).floor() -
            _cacheRows)
        .clamp(0, _treeCount)
        .toInt();
    final end = (((scrollOffset + viewportHeight - startOffset) / _rowHeight)
            .ceil() +
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

    final (start, end) =
        _visibleWindow(position.pixels, position.viewportDimension);
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
    rows.add(_TreeRow(
      type: _RowType.thisPc,
      path: _thisPcGuid,
      name: '此电脑',
      depth: 0,
      isExpanded: sidebar.thisPcExpanded,
      hasChildren: sidebar.driveRoots.isNotEmpty,
    ));
    if (sidebar.thisPcExpanded) {
      for (final drive in sidebar.driveRoots) {
        final expanded = sidebar.isExpanded(drive);
        final label = SidebarService.formatDriveLabel(drive);
        rows.add(_TreeRow(
          type: _RowType.drive,
          path: drive,
          name: label,
          depth: 1,
          isExpanded: expanded,
          hasChildren: sidebar.hasChildrenFor(drive),
        ));
        if (expanded) {
          _flattenDir(sidebar, sidebar.childrenFor(drive), 2, rows,
              parentPath: drive);
        }
      }
    }
    return rows;
  }

  void _flattenDir(SidebarSyncController sidebar, List<FileEntry> dirs,
      int depth, List<_TreeRow> out,
      {required String parentPath}) {
    for (final dir in dirs) {
      final expanded = sidebar.isExpanded(dir.path);
      out.add(_TreeRow(
        type: _RowType.directory,
        path: dir.path,
        name: dir.name,
        depth: depth,
        isExpanded: expanded,
        // 枚举元数据自带 hasChildren，build 不需要 probe（§13.1）。
        hasChildren: dir.hasChildren,
      ));
      if (expanded) {
        final children = sidebar.childrenFor(dir.path);
        if (children.isNotEmpty) {
          _flattenDir(sidebar, children, depth + 1, out,
              parentPath: dir.path);
        }
      }
    }
    if (sidebar.isLoading(parentPath)) {
      out.add(_TreeRow(
        type: _RowType.loadingIndicator,
        path: '',
        name: '',
        depth: depth + 1,
        isExpanded: false,
        hasChildren: false,
      ));
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
      final qaIndex = sidebar.quickAccessItems
          .indexWhere((item) => pathEquals(item.path, selected));
      if (qaIndex >= 0) {
        // 快速访问行固定，offset 永远稳定，直接消费。
        offset = _quickAccessHeaderHeight + qaIndex * _rowHeight;
        sidebar.consumeScrollRequest();
      } else {
        final treeIndex =
            _treeItems.indexWhere((item) => pathEquals(item.path, selected));
        if (treeIndex < 0) return; // 目标行未挂上树：保留请求，等待重试。
        offset = _treeStartOffset(_qaCount) + treeIndex * _rowHeight;
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
      case _RowType.thisPc:
        return Icons.computer;
      case _RowType.drive:
        return Icons.storage;
      case _RowType.directory:
        return Icons.folder;
      case _RowType.loadingIndicator:
        return Icons.hourglass_empty;
    }
  }

  bool _isSelected(SidebarSyncController sidebar, String path) =>
      sidebar.selectedPath != null &&
      pathEquals(sidebar.selectedPath!, path);

  Widget _buildTreeRow(SidebarSyncController sidebar, int index) {
    final row = _treeItems[index];

    if (row.type == _RowType.loadingIndicator) {
      return Container(
        height: _rowHeight,
        width: double.infinity,
        padding: EdgeInsets.only(left: 4.0 + row.depth * 16.0),
        child: const Row(
          children: [
            SizedBox(width: 14),
            SizedBox(
              width: 15,
              height: 15,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
            SizedBox(width: 4),
            Text(
              'Loading...',
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF999999),
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    final isSelected = _isSelected(sidebar, row.path);
    final fallback = _fallbackIcon(row.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
      onTap: () => _onTapTreeRow(sidebar, row),
      hoverColor: const Color(0x11000000),
      child: Container(
        height: _rowHeight,
        width: double.infinity,
        color: isSelected ? const Color(0xFFCCE8FF) : null,
        child: Row(
          children: [
            SizedBox(width: 4.0 + row.depth * 16.0),
            if (row.hasChildren)
              Icon(
                row.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: const Color(0xFF888888),
              )
            else
              const SizedBox(width: 14),
            const SizedBox(width: 2),
            SizedBox(
              width: 15,
              child: _ShellIcon(
                path: row.path,
                isDirectory: true,
                fallback: fallback,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                row.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

    final sw = Stopwatch()..start();
    _treeItems = _flattenTree(sidebar);
    _qaCount = sidebar.quickAccessItems.length;
    _treeCount = _treeItems.length;
    final flattenMs = sw.elapsedMilliseconds;
    _tryScrollToSelected(sidebar);

    final result = LayoutBuilder(builder: (context, constraints) {
      final viewportHeight = constraints.maxHeight;
      final scrollOffset = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      final (first, last) = _visibleWindow(scrollOffset, viewportHeight);
      _firstVisibleTreeIndex = first;
      _lastVisibleTreeIndex = last;

      final stackChildren = <Widget>[];

      stackChildren.add(Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: _quickAccessHeaderHeight,
        child: const _QuickAccessHeader(),
      ));
      for (var i = 0; i < _qaCount; i++) {
        final item = sidebar.quickAccessItems[i];
        stackChildren.add(Positioned(
          top: _quickAccessHeaderHeight + i * _rowHeight,
          left: 0,
          right: 0,
          height: _rowHeight,
          child: _QuickAccessRow(
            item: item,
            selected: _isSelected(sidebar, item.path),
            fallbackIcon: _quickAccessFallbackIcon(item.name),
            onTap: () => _onTapQuickAccess(sidebar, item),
          ),
        ));
      }

      final qaBottom = _quickAccessHeaderHeight + _qaCount * _rowHeight;
      stackChildren.add(Positioned(
        top: qaBottom,
        left: 0,
        right: 0,
        height: _dividerHeight,
        child: const Divider(height: 1, thickness: 1),
      ));
      stackChildren.add(Positioned(
        top: qaBottom + _dividerHeight,
        left: 0,
        right: 0,
        height: _gapHeight,
        child: const SizedBox(),
      ));

      final treeStartOffset = _treeStartOffset(_qaCount);
      for (var i = first; i < last; i++) {
        stackChildren.add(Positioned(
          top: treeStartOffset + i * _rowHeight,
          left: 0,
          right: 0,
          height: _rowHeight,
          child: _buildTreeRow(sidebar, i),
        ));
      }

      return Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(color: Color(0xFFF8F8F8)),
        alignment: Alignment.topLeft,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: false,
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
      );
    });

    sw.stop();
    if (sw.elapsedMilliseconds > 10) {
      debugPrint(
          '[Perf] SidebarTree build: flatten=${flattenMs}ms, total=${sw.elapsedMilliseconds}ms');
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════════════
//  Private widgets (unchanged)
// ═══════════════════════════════════════════════════════════

class _ShellIcon extends StatelessWidget {
  static const _iconSize = 15;
  final String path;
  final bool isDirectory;
  final IconData fallback;

  const _ShellIcon({
    required this.path,
    required this.isDirectory,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = IconService.getFileIconPng(path, isDirectory, _iconSize);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: _iconSize.toDouble(),
        height: _iconSize.toDouble(),
        gaplessPlayback: true,
      );
    }
    return Icon(fallback,
        size: _iconSize.toDouble(), color: Colors.amber.shade700);
  }
}

class _QuickAccessHeader extends StatelessWidget {
  const _QuickAccessHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Row(
        children: [
          Icon(Icons.history, size: 13, color: Color(0xFF666666)),
          SizedBox(width: 4),
          Text(
            '快速访问',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF888888),
            ),
          ),
        ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
      onTap: onTap,
      hoverColor: const Color(0x11000000),
      child: Container(
        height: 22,
        width: double.infinity,
        color: selected ? const Color(0xFFCCE8FF) : null,
        child: Row(
          children: [
            const SizedBox(width: 4),
            const SizedBox(width: 14),
            const SizedBox(width: 2),
            SizedBox(
              width: 15,
              child: _ShellIcon(
                path: item.path,
                isDirectory: true,
                fallback: fallbackIcon,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isPinned)
              Icon(Icons.push_pin, size: 11, color: Colors.grey.shade500),
          ],
        ),
      ),
    ),
    );
  }
}
