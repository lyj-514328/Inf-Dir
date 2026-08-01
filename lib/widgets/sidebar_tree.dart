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
class SidebarTree extends StatefulWidget {
  final ValueChanged<String> onNavigate;

  const SidebarTree({
    super.key,
    required this.onNavigate,
  });

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

/// State 只拥有 ScrollController；业务状态全部在 SidebarSyncController。
class _SidebarTreeState extends State<SidebarTree> {
  static const _thisPcGuid = SidebarSyncController.thisPcGuid;

  final ScrollController _scrollController = ScrollController();
  List<_TreeRow> _treeItems = [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  static const double _quickAccessHeaderHeight = 20.0;

  double _preTreeHeight(SidebarSyncController sidebar) {
    return 20.0 + sidebar.quickAccessItems.length * 22.0 + 1.0 + 4.0;
  }

  void _tryScrollToSelected(SidebarSyncController sidebar) {
    if (!sidebar.needsScrollToSelected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final selected = sidebar.selectedPath ?? '';
      double? offset;
      final qaIndex = sidebar.quickAccessItems
          .indexWhere((item) => pathEquals(item.path, selected));
      if (qaIndex >= 0) {
        offset = _quickAccessHeaderHeight + qaIndex * 22.0;
      } else {
        final items = _flattenTree(sidebar);
        final treeIndex =
            items.indexWhere((item) => pathEquals(item.path, selected));
        if (treeIndex >= 0) {
          offset = _preTreeHeight(sidebar) + treeIndex * 22.0;
        }
      }

      sidebar.consumeScrollRequest();
      if (offset == null) return;

      final viewportHeight = _scrollController.position.viewportDimension;
      final centeredOffset = offset - viewportHeight / 2 + 11.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(centeredOffset.clamp(0.0, maxScroll));
    });
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
  //  Build
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
        height: 22,
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
        height: 22,
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

  @override
  Widget build(BuildContext context) {
    final sidebar = context.watch<SidebarSyncController>();

    final sw = Stopwatch()..start();
    _treeItems = _flattenTree(sidebar);
    final flattenMs = sw.elapsedMilliseconds;
    _tryScrollToSelected(sidebar);

    final result = Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: Color(0xFFF8F8F8)),
      alignment: Alignment.topLeft,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            const SliverToBoxAdapter(child: _QuickAccessHeader()),
            ...sidebar.quickAccessItems.map(
              (item) => SliverToBoxAdapter(
                child: _QuickAccessRow(
                  item: item,
                  selected: _isSelected(sidebar, item.path),
                  fallbackIcon: _quickAccessFallbackIcon(item.name),
                  onTap: () => _onTapQuickAccess(sidebar, item),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Divider(height: 1, thickness: 1),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 4),
            ),
            SliverFixedExtentList(
              itemExtent: 22.0,
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildTreeRow(sidebar, index),
                childCount: _treeItems.length,
              ),
            ),
          ],
        ),
      ),
    );

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
