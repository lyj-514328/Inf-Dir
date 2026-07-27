import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sidebar_service.dart';
import '../services/directory_service.dart';
import '../services/icon_service.dart';

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

class _ChildDir {
  final String name;
  final String path;
  _ChildDir(this.name, this.path);
}

class SidebarTree extends StatefulWidget {
  final String activePath;
  final ValueChanged<String> onNavigate;

  const SidebarTree({
    super.key,
    required this.activePath,
    required this.onNavigate,
  });

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

class _SidebarTreeState extends State<SidebarTree> {
  static const _thisPcGuid = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';

  // ── data ──
  List<QuickAccessItem> _quickAccessItems = [];
  List<String> _driveRoots = [];
  bool _thisPcExpanded = true;
  final Set<String> _expandedPaths = {};
  final Map<String, List<_ChildDir>> _childrenCache = {};
  final Map<String, bool> _hasChildrenCache = {};
  final Set<String> _loadingPaths = {};
  String? _selectedPath;
  final ScrollController _scrollController = ScrollController();
  List<_TreeRow> _treeItems = [];
  bool _needsScrollToSelected = false;

  // ── concurrency control ──
  int _syncGeneration = 0;
  final Map<String, int> _activeSessIds = {}; // normPath → sid
  final Set<String> _inFlight = {}; // intra-generation dedup (synchronous guard)

  @override
  void initState() {
    super.initState();
    _quickAccessItems = SidebarService.getQuickAccessItems();
    _driveRoots = SidebarService.getDriveRoots();
    if (_driveRoots.isNotEmpty) {
      _expandedPaths.add(_norm(_driveRoots.first));
    }
    _loadChildren(_driveRoots.first);
    for (final drive in _driveRoots) {
      _hasChildrenCache[_norm(drive)] =
          SidebarService.directoryHasChildren(drive);
    }
    _selectedPath = widget.activePath;
    _syncToPath(widget.activePath);
  }

  @override
  void dispose() {
    _cancelAllSessions();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SidebarTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pathEquals(widget.activePath, oldWidget.activePath)) {
      _selectedPath = widget.activePath;
      _syncToPath(widget.activePath);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Kill / Cancel
  // ═══════════════════════════════════════════════════════════

  /// Kill all in-flight sessions and remove incomplete cache entries.
  /// Called synchronously at the start of every new sync.
  void _cancelAllSessions() {
    for (final entry in _activeSessIds.entries) {
      DirectoryService.endShellEnum(entry.value);
      // Remove incomplete cache — only first page (or fewer) was loaded
      _childrenCache.remove(entry.key);
    }
    _activeSessIds.clear();
    _inFlight.clear();
  }

  /// Cleanup a single session (called from async paths when generation is stale).
  void _cleanupSession(String key, int sid) {
    DirectoryService.endShellEnum(sid);
    _activeSessIds.remove(key);
    _loadingPaths.remove(key);
    _childrenCache.remove(key);
  }

  // ═══════════════════════════════════════════════════════════
  //  Path Sync (entry point for FilePane → SidebarTree navigation)
  // ═══════════════════════════════════════════════════════════

  void _syncToPath(String path) {
    // 1. Kill any in-flight sync
    _syncGeneration++;
    _cancelAllSessions();
    _loadingPaths.clear();
    _needsScrollToSelected = true;

    // 2. Quick Access
    for (final item in _quickAccessItems) {
      if (_pathEquals(item.path, path)) {
        setState(() => _selectedPath = item.path);
        return;
      }
    }

    // 3. This PC
    if (path == _thisPcGuid) {
      setState(() => _selectedPath = _thisPcGuid);
      return;
    }

    // 4. Drive-based chain expansion
    final drive = _findDriveFor(path);
    if (drive == null) {
      setState(() {});
      return;
    }

    _thisPcExpanded = true;
    _expandedPaths.add(_norm(drive));
    setState(() => _selectedPath = path);

    final gen = _syncGeneration;
    _expandChainTo(path, drive, gen);
  }

  String? _findDriveFor(String path) {
    for (final drive in _driveRoots) {
      if (_isUnder(path, drive)) return drive;
    }
    return null;
  }

  /// Walk from [drive] to [targetPath], loading children for each segment
  /// that is not already cached.  Kills itself if generation is stale.
  Future<void> _expandChainTo(
      String targetPath, String drive, int generation) async {
    // Build ordered list of paths: drive, drive\seg1, drive\seg1\seg2, ...
    final paths = <String>[drive];
    final normTarget = _norm(targetPath);
    final normDrive = _norm(drive);
    if (normTarget != normDrive) {
      var rel = targetPath.replaceAll('/', '\\');
      if (rel.toLowerCase().startsWith(drive.toLowerCase())) {
        rel = rel.substring(drive.length);
      }
      final segments = rel.split('\\').where((s) => s.isNotEmpty).toList();
      String current = drive.endsWith('\\') ? drive : '$drive\\';
      for (int i = 0; i < segments.length; i++) {
        current =
            i == 0 ? '$drive${segments[i]}' : '$current\\${segments[i]}';
        paths.add(current);
      }
    }

    for (final p in paths) {
      if (generation != _syncGeneration) return;
      final key = _norm(p);
      _expandedPaths.add(key);

      if (_childrenCache.containsKey(key)) {
        // Already loaded — skip directly to next segment
        if (mounted && generation == _syncGeneration) setState(() {});
        continue;
      }

      await _loadChildren(p, generation: generation);
      if (generation != _syncGeneration) return;
      if (mounted) setState(() {});
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Children Loading
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadChildren(String path, {int? generation}) async {
    final gen = generation ?? _syncGeneration;
    final key = _norm(path);

    if (_childrenCache.containsKey(key) || _inFlight.contains(key)) return;
    _inFlight.add(key);

    await _afterFrame();
    if (gen != _syncGeneration) {
      _inFlight.remove(key);
      return;
    }

    final sid = DirectoryService.beginShellEnum(path, directoriesOnly: true);
    if (sid <= 0) {
      _inFlight.remove(key);
      if (mounted && gen == _syncGeneration) {
        setState(() => _childrenCache[key] = []);
      }
      return;
    }
    _activeSessIds[key] = sid;

    // Load first page synchronously
    final firstPage = DirectoryService.getNextEnumPage(sid, count: 500);
    if (gen != _syncGeneration) {
      _inFlight.remove(key);
      _cleanupSession(key, sid);
      return;
    }

    if (firstPage == null) {
      _inFlight.remove(key);
      _cleanupSession(key, sid);
      if (mounted && gen == _syncGeneration) {
        setState(() => _childrenCache[key] = []);
      }
      return;
    }

    final children = firstPage
        .where((e) => e.isDirectory)
        .map((e) => _ChildDir(e.name, e.path))
        .toList();
    children.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _childrenCache[key] = children;
    _inFlight.remove(key); // cache populated, no longer in-flight
    if (mounted && gen == _syncGeneration) setState(() {});

    // Background: load remaining pages
    _loadingPaths.add(key);
    _loadMoreChildren(sid, key, gen);
  }

  Future<void> _loadMoreChildren(int sid, String key, int generation) async {
    while (true) {
      await _afterFrame();
      if (generation != _syncGeneration) {
        _cleanupSession(key, sid);
        return;
      }

      final page = DirectoryService.getNextEnumPage(sid, count: 500);
      if (page == null) break;

      final dirs = page
          .where((e) => e.isDirectory)
          .map((e) => _ChildDir(e.name, e.path))
          .toList();
      if (dirs.isEmpty) continue;

      final existing = _childrenCache[key];
      if (existing == null) {
        // Killed by a newer sync between frames — safety net
        _cleanupSession(key, sid);
        return;
      }

      existing.addAll(dirs);
      if (mounted && generation == _syncGeneration) setState(() {});
    }

    final existing = _childrenCache[key];
    if (existing != null) {
      existing.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _loadingPaths.remove(key);
    _activeSessIds.remove(key);
    DirectoryService.endShellEnum(sid);
    if (mounted && generation == _syncGeneration) {
      if (_selectedPath != null && _isUnder(_selectedPath!, key)) {
        _needsScrollToSelected = true;
      }
      setState(() {});
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Tree flattening & rendering  (unchanged logic below)
  // ═══════════════════════════════════════════════════════════

  bool _hasChildren(String path) {
    // CACHE DISABLED
    return SidebarService.directoryHasChildren(path);
  }

  Future<void> _afterFrame() {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
    return c.future;
  }

  void _toggleExpand(String path) {
    final key = _norm(path);
    if (_expandedPaths.contains(key)) {
      setState(() => _expandedPaths.remove(key));
    } else {
      _loadChildren(path);
      setState(() => _expandedPaths.add(key));
    }
  }

  bool _isSelected(String path) =>
      _selectedPath != null && _pathEquals(_selectedPath!, path);

  List<_TreeRow> _flattenTree() {
    final rows = <_TreeRow>[];
    rows.add(_TreeRow(
      type: _RowType.thisPc,
      path: _thisPcGuid,
      name: '\u6b64\u7535\u8111',
      depth: 0,
      isExpanded: _thisPcExpanded,
      hasChildren: _driveRoots.isNotEmpty,
    ));
    if (_thisPcExpanded) {
      for (final drive in _driveRoots) {
        final normDrive = _norm(drive);
        final expanded = _expandedPaths.contains(normDrive);
        final children = _childrenCache[normDrive] ?? [];
        final label = SidebarService.formatDriveLabel(drive);
        final hasKids = _hasChildren(drive);
        rows.add(_TreeRow(
          type: _RowType.drive,
          path: drive,
          name: label,
          depth: 1,
          isExpanded: expanded,
          hasChildren: hasKids,
        ));
        if (expanded) {
          _flattenDir(children, 2, rows, parentPath: drive);
        }
      }
    }
    return rows;
  }

  void _flattenDir(List<_ChildDir> dirs, int depth, List<_TreeRow> out,
      {required String parentPath}) {
    for (final dir in dirs) {
      final normPath = _norm(dir.path);
      final expanded = _expandedPaths.contains(normPath);
      final children = _childrenCache[normPath] ?? [];
      final hasKids = _hasChildren(dir.path);
      out.add(_TreeRow(
        type: _RowType.directory,
        path: dir.path,
        name: dir.name,
        depth: depth,
        isExpanded: expanded,
        hasChildren: hasKids,
      ));
      if (expanded && children.isNotEmpty) {
        _flattenDir(children, depth + 1, out, parentPath: dir.path);
      }
    }
    if (_loadingPaths.contains(_norm(parentPath))) {
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

  double get _quickAccessHeaderHeight => 20.0;

  double get _preTreeHeight {
    return 20.0 + _quickAccessItems.length * 22.0 + 1.0 + 4.0;
  }

  void _tryScrollToSelected() {
    if (!_needsScrollToSelected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      double? offset;
      final qaIndex = _quickAccessItems
          .indexWhere((item) => _pathEquals(item.path, _selectedPath ?? ''));
      if (qaIndex >= 0) {
        offset = _quickAccessHeaderHeight + qaIndex * 22.0;
      } else {
        final items = _flattenTree();
        final treeIndex = items
            .indexWhere((item) => _pathEquals(item.path, _selectedPath ?? ''));
        if (treeIndex >= 0) {
          offset = _preTreeHeight + treeIndex * 22.0;
        }
      }

      if (offset == null) return;

      final viewportHeight = _scrollController.position.viewportDimension;
      final centeredOffset = offset - viewportHeight / 2 + 11.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(centeredOffset.clamp(0.0, maxScroll));
      _needsScrollToSelected = false;
    });
  }

  void _onTapTreeRow(_TreeRow row) {
    if (row.type == _RowType.loadingIndicator) return;
    setState(() => _selectedPath = row.path);
    widget.onNavigate(row.path);
    if (row.hasChildren) {
      if (row.type == _RowType.thisPc) {
        setState(() => _thisPcExpanded = !_thisPcExpanded);
      } else {
        _toggleExpand(row.path);
      }
    }
  }

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

  Widget _buildTreeRow(BuildContext context, int index) {
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

    final isSelected =
        _selectedPath != null && _pathEquals(_selectedPath!, row.path);
    final fallback = _fallbackIcon(row.type);
    return InkWell(
      onTap: () => _onTapTreeRow(row),
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
    );
  }

  IconData _quickAccessFallbackIcon(String name) {
    if (name.contains('\u684c\u9762')) return Icons.desktop_windows;
    if (name.contains('\u4e0b\u8f7d')) return Icons.download;
    if (name.contains('\u6587\u6863')) return Icons.description;
    if (name.contains('\u56fe\u7247')) return Icons.image;
    if (name.contains('\u97f3\u4e50')) return Icons.music_note;
    if (name.contains('\u89c6\u9891')) return Icons.videocam;
    if (name.contains('\u56de\u6536\u7ad9')) return Icons.delete_outline;
    return Icons.folder;
  }

  void _onTapQuickAccess(QuickAccessItem item) {
    setState(() => _selectedPath = item.path);
    widget.onNavigate(item.path);
  }

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    _treeItems = _flattenTree();
    final flattenMs = sw.elapsedMilliseconds;
    _tryScrollToSelected();

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
            SliverToBoxAdapter(child: _QuickAccessHeader()),
            ..._quickAccessItems.map(
              (item) => SliverToBoxAdapter(
                child: _QuickAccessRow(
                  item: item,
                  selected: _isSelected(item.path),
                  fallbackIcon: _quickAccessFallbackIcon(item.name),
                  onTap: () => _onTapQuickAccess(item),
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
                _buildTreeRow,
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
//  Utility functions (unchanged)
// ═══════════════════════════════════════════════════════════

String _norm(String path) {
  var s = path.replaceAll('/', '\\');
  while (s.length > 3 && s.endsWith('\\')) {
    s = s.substring(0, s.length - 1);
  }
  return s.toLowerCase();
}

bool _pathEquals(String a, String b) => _norm(a) == _norm(b);

bool _isUnder(String child, String parent) {
  final nc = _norm(child);
  final np = _norm(parent);
  return nc == np || nc.startsWith(np.endsWith('\\') ? np : '$np\\');
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
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Row(
        children: [
          Icon(Icons.history, size: 13, color: Color(0xFF666666)),
          SizedBox(width: 4),
          Text(
            '\u5feb\u901f\u8bbf\u95ee',
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
    return InkWell(
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
    );
  }
}
