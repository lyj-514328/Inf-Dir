import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/sidebar_service.dart';
import '../services/directory_service.dart';
import '../services/icon_service.dart';

// ======================================================================
//  ShellIcon — loads proper Windows icon via IconService, fallback to
//  Material icon
// ======================================================================

class _ShellIcon extends StatelessWidget {
  final String path;
  final bool isDirectory;
  final int iconSize;
  final IconData fallback;

  const _ShellIcon({
    required this.path,
    required this.isDirectory,
    this.iconSize = 15,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = IconService.getFileIconPng(path, isDirectory, iconSize);
    if (bytes != null) {
      return _PngIcon(bytes: bytes, size: iconSize);
    }
    return Icon(fallback, size: iconSize.toDouble(), color: Colors.amber.shade700);
  }
}

class _PngIcon extends StatelessWidget {
  final Uint8List bytes;
  final int size;
  const _PngIcon({required this.bytes, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      width: size.toDouble(),
      height: size.toDouble(),
      gaplessPlayback: true,
    );
  }
}

// ======================================================================
//  Path helpers
// ======================================================================

/// Normalize path for comparison: lowercase, remove trailing separator.
String _norm(String path) {
  var s = path.replaceAll('/', '\\');
  while (s.length > 3 && s.endsWith('\\')) {
    s = s.substring(0, s.length - 1);
  }
  return s.toLowerCase();
}

bool _pathEquals(String a, String b) => _norm(a) == _norm(b);

/// Check if [child] is under [parent] (or equal).
bool _isUnder(String child, String parent) {
  final nc = _norm(child);
  final np = _norm(parent);
  return nc == np || nc.startsWith(np.endsWith('\\') ? np : '$np\\');
}

// ======================================================================
//  SidebarTree — the main sidebar widget
// ======================================================================

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

  List<QuickAccessItem> _quickAccessItems = [];
  List<String> _driveRoots = [];

  // Centralized tree state
  bool _thisPcExpanded = true;
  final Set<String> _expandedPaths = {}; // normalized paths that are expanded
  final Map<String, List<_ChildDir>> _childrenCache = {}; // norm path → children
  final Map<String, bool> _hasChildrenCache = {}; // norm path → has sub-dirs

  // Single selection shared across Quick Access + This PC
  String? _selectedPath;

  final ScrollController _verticalScrollController = ScrollController();

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
    // Initial sync
    _selectedPath = widget.activePath;
    _syncToPath(widget.activePath);
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
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

  // ── Sync tree to a target path ──────────────────────────────────────

  void _syncToPath(String path) {
    // Priority 1: Quick Access match
    for (final item in _quickAccessItems) {
      if (_pathEquals(item.path, path)) {
        setState(() => _selectedPath = item.path);
        return;
      }
    }

    // Priority 2: This PC tree
    if (path == _thisPcGuid) {
      setState(() => _selectedPath = _thisPcGuid);
      return;
    }

    // Find matching drive
    final drive = _findDriveFor(path);
    if (drive == null) {
      setState(() {});
      return;
    }

    // Ensure This PC is expanded
    _thisPcExpanded = true;
    // Expand the drive
    _expandedPaths.add(_norm(drive));
    _loadChildren(drive);

    // Expand intermediate directories to reveal the target
    _expandChainTo(path, drive);

    setState(() => _selectedPath = path);
  }

  String? _findDriveFor(String path) {
    for (final drive in _driveRoots) {
      if (_isUnder(path, drive)) return drive;
    }
    return null;
  }

  /// Expand all intermediate directories from [drive] down to [targetPath].
  void _expandChainTo(String targetPath, String drive) {
    final normTarget = _norm(targetPath);
    final normDrive = _norm(drive);
    if (normTarget == normDrive) return;

    // Get relative segments after drive
    var rel = targetPath.replaceAll('/', '\\');
    // Remove drive prefix (e.g. "C:\")
    if (rel.toLowerCase().startsWith(drive.toLowerCase())) {
      rel = rel.substring(drive.length);
    }
    final segments = rel.split('\\').where((s) => s.isNotEmpty).toList();

    // Build path incrementally and expand each level
    String current = drive.endsWith('\\') ? drive : '$drive\\';
    for (int i = 0; i < segments.length; i++) {
      current = i == 0 ? '$drive${segments[i]}' : '$current\\${segments[i]}';
      final normCurrent = _norm(current);
      _expandedPaths.add(normCurrent);
      // Load children for this level (needed to render sub-nodes)
      _loadChildrenSync(current);
    }
  }

  // ── Children loading (via native Shell API) ────────────────────────

  void _loadChildrenSync(String path) {
    final key = _norm(path);
    if (_childrenCache.containsKey(key)) return;
    try {
      final entries = DirectoryService.listDirectory(path);
      final children = entries
          .where((e) => e.isDirectory)
          .map((e) => _ChildDir(e.name, e.path))
          .toList();
      children.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _childrenCache[key] = children;
    } catch (_) {
      _childrenCache[key] = [];
    }
  }

  Future<void> _loadChildren(String path) async {
    final key = _norm(path);
    if (_childrenCache.containsKey(key)) return;
    try {
      // DirectoryService.listDirectory is synchronous (native call),
      // wrap in compute-like pattern is unnecessary; just call directly.
      final entries = DirectoryService.listDirectory(path);
      final children = entries
          .where((e) => e.isDirectory)
          .map((e) => _ChildDir(e.name, e.path))
          .toList();
      children.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _childrenCache[key] = children);
    } catch (_) {
      if (mounted) setState(() => _childrenCache[key] = []);
    }
  }

  bool _hasChildren(String path) {
    final key = _norm(path);
    if (_hasChildrenCache.containsKey(key)) return _hasChildrenCache[key]!;
    final has = SidebarService.directoryHasChildren(path);
    _hasChildrenCache[key] = has;
    return has;
  }

  // ── Toggle expansion ────────────────────────────────────────────────

  void _toggleExpand(String path) {
    final key = _norm(path);
    if (_expandedPaths.contains(key)) {
      setState(() => _expandedPaths.remove(key));
    } else {
      _loadChildren(path);
      setState(() => _expandedPaths.add(key));
    }
  }

  void _selectAndNavigate(String path) {
    setState(() => _selectedPath = path);
    widget.onNavigate(path);
  }

  bool _isSelected(String path) =>
      _selectedPath != null && _pathEquals(_selectedPath!, path);

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: Color(0xFFF8F8F8)),
      alignment: Alignment.topLeft,
      child: Scrollbar(
        controller: _verticalScrollController,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _verticalScrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Quick Access section ----
              const _SectionHeader(
                icon: Icons.history,
                title: '快速访问',
                topPadding: 2,
              ),
              ..._quickAccessItems.map((item) => _QuickAccessTile(
                    item: item,
                    selected: _isSelected(item.path),
                    onTap: () => _selectAndNavigate(item.path),
                  )),
              const Divider(height: 1, thickness: 1),

              // ---- This PC section ----
              const SizedBox(height: 4),
              _ThisPcTreeNode(
                label: '此电脑',
                expanded: _thisPcExpanded,
                selected: _isSelected(_thisPcGuid),
                onToggle: () =>
                    setState(() => _thisPcExpanded = !_thisPcExpanded),
                onTap: () {
                  setState(() => _selectedPath = _thisPcGuid);
                  widget.onNavigate(_thisPcGuid);
                  setState(() => _thisPcExpanded = !_thisPcExpanded);
                },
                children: [
                  ..._driveRoots.map((drive) {
                    final label = SidebarService.formatDriveLabel(drive);
                    final normDrive = _norm(drive);
                    final expanded = _expandedPaths.contains(normDrive);
                    final children = _childrenCache[normDrive] ?? [];
                    return _DriveTreeNode(
                      drive: drive,
                      label: label,
                      expanded: expanded,
                      hasChildren: _hasChildren(drive),
                      selected: _isSelected(drive),
                      onToggle: () => _toggleExpand(drive),
                      onTap: () => _selectAndNavigate(drive),
                      children: children.map((child) => _buildChildTile(child, 2)).toList(),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildTile(_ChildDir child, int depth) {
    final normPath = _norm(child.path);
    final expanded = _expandedPaths.contains(normPath);
    final hasKids = _hasChildren(child.path);
    final children = _childrenCache[normPath] ?? [];

    return _ChildDirNode(
      name: child.name,
      path: child.path,
      depth: depth,
      expanded: expanded,
      hasChildren: hasKids,
      selected: _isSelected(child.path),
      children: children,
      onToggle: () => _toggleExpand(child.path),
      onTap: () => _selectAndNavigate(child.path),
      buildChild: (c, d) => _buildChildTile(c, d),
    );
  }
}

// ======================================================================
//  Widgets
// ======================================================================

/// Section header with icon and title.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final double topPadding;
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.topPadding = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topPadding, 8, 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: const Color(0xFF666666)),
          const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
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

/// A flat tile in the Quick Access section.
class _QuickAccessTile extends StatelessWidget {
  final QuickAccessItem item;
  final bool selected;
  final VoidCallback onTap;

  const _QuickAccessTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  IconData _fallbackIcon() {
    final name = item.name;
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
    return _SidebarItem(
      onTap: onTap,
      leading: _ShellIcon(
        path: item.path,
        isDirectory: true,
        fallback: _fallbackIcon(),
      ),
      title: item.name,
      showArrow: false,
      selected: selected,
      trailing: item.isPinned
          ? Icon(Icons.push_pin, size: 11, color: Colors.grey.shade500)
          : null,
    );
  }
}

/// Tree node for "此电脑" root.
class _ThisPcTreeNode extends StatelessWidget {
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final List<Widget> children;

  const _ThisPcTreeNode({
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarItem(
          onTap: onTap,
          leading: _ShellIcon(
            path: '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
            isDirectory: true,
            fallback: Icons.computer,
          ),
          title: label,
          showArrow: true,
          expanded: expanded,
          selected: selected,
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// Tree node for a single drive.
class _DriveTreeNode extends StatelessWidget {
  final String drive;
  final String label;
  final bool expanded;
  final bool hasChildren;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final List<Widget> children;

  const _DriveTreeNode({
    required this.drive,
    required this.label,
    required this.expanded,
    required this.hasChildren,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarItem(
          depth: 1,
          onTap: () {
            onTap();
            if (hasChildren) onToggle();
          },
          leading: _ShellIcon(
            path: drive,
            isDirectory: true,
            fallback: Icons.storage,
          ),
          title: label,
          showArrow: hasChildren,
          expanded: expanded,
          selected: selected,
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// A recursive directory tree node (controlled by parent).
class _ChildDirNode extends StatelessWidget {
  final String name;
  final String path;
  final int depth;
  final bool expanded;
  final bool hasChildren;
  final bool selected;
  final List<_ChildDir> children;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final Widget Function(_ChildDir, int) buildChild;

  const _ChildDirNode({
    required this.name,
    required this.path,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
    required this.selected,
    required this.children,
    required this.onToggle,
    required this.onTap,
    required this.buildChild,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarItem(
          depth: depth,
          onTap: () {
            onTap();
            if (hasChildren) onToggle();
          },
          leading: _ShellIcon(
            path: path,
            isDirectory: true,
            fallback: Icons.folder,
          ),
          title: name,
          showArrow: hasChildren,
          expanded: expanded,
          selected: selected,
        ),
        if (expanded)
          ...children.map((child) => buildChild(child, depth + 1)),
      ],
    );
  }
}

/// Reusable sidebar item row.
class _SidebarItem extends StatelessWidget {
  final int depth;
  final VoidCallback? onTap;
  final Widget leading;
  final String title;
  final bool showArrow;
  final bool expanded;
  final bool selected;
  final Widget? trailing;

  const _SidebarItem({
    this.depth = 0,
    this.onTap,
    required this.leading,
    required this.title,
    this.showArrow = false,
    this.expanded = false,
    this.selected = false,
    this.trailing,
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
            SizedBox(width: 4.0 + depth * 16.0),
            if (showArrow)
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: const Color(0xFF888888),
              )
            else
              const SizedBox(width: 14),
            const SizedBox(width: 2),
            SizedBox(width: 15, child: leading),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ======================================================================
//  Data helpers
// ======================================================================

class _ChildDir {
  final String name;
  final String path;
  _ChildDir(this.name, this.path);
}
