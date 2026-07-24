import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/sidebar_service.dart';
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
//  SidebarTree — the main sidebar widget
// ======================================================================

class SidebarTree extends StatefulWidget {
  final ValueChanged<String> onNavigate;

  const SidebarTree({super.key, required this.onNavigate});

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

class _SidebarTreeState extends State<SidebarTree> {
  List<QuickAccessItem> _quickAccessItems = [];
  List<String> _driveRoots = [];

  // Tree expansion state
  bool _thisPcExpanded = true;
  final Set<String> _expandedDrives = {};
  final Map<String, List<_ChildDir>> _driveChildren = {};

  @override
  void initState() {
    super.initState();
    _loadQuickAccess();
    _driveRoots = SidebarService.getDriveRoots();
    if (_driveRoots.isNotEmpty) {
      _expandedDrives.add(_driveRoots.first);
    }
    _loadDriveChildren(_driveRoots.first);
  }

  void _loadQuickAccess() {
    final items = SidebarService.getQuickAccessItems();
    setState(() {
      _quickAccessItems = items;
    });
  }

  Future<void> _toggleDriveExpanded(String drive) async {
    if (_expandedDrives.contains(drive)) {
      setState(() => _expandedDrives.remove(drive));
      return;
    }
    if (_driveChildren[drive] == null) {
      await _loadDriveChildren(drive);
    }
    setState(() => _expandedDrives.add(drive));
  }

  Future<void> _loadDriveChildren(String drive) async {
    try {
      final dir = Directory(drive);
      final entities = await dir.list(followLinks: false).toList();
      final children = entities
          .whereType<Directory>()
          .map((d) => _ChildDir(p.basename(d.path), d.path))
          .toList();
      children.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() => _driveChildren[drive] = children);
    } catch (_) {
      setState(() => _driveChildren[drive] = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFFF8F8F8),
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Quick Access section ----
            const _SectionHeader(
              icon: Icons.history,
              title: '快速访问',
              topPadding: 2,
            ),
            ..._quickAccessItems.map((item) => _QuickAccessTile(
                  item: item,
                  onNavigate: widget.onNavigate,
                )),
            const Divider(height: 1, thickness: 1),

            // ---- This PC section ----
            const SizedBox(height: 4),
            _ThisPcTreeNode(
              label: '此电脑',
              expanded: _thisPcExpanded,
              onToggle: () => setState(() => _thisPcExpanded = !_thisPcExpanded),
              onNavigate: widget.onNavigate,
              children: [
                // Drives
                ..._driveRoots.map((drive) {
                  final label = SidebarService.formatDriveLabel(drive);
                  final expanded = _expandedDrives.contains(drive);
                  final children = _driveChildren[drive] ?? [];
                  return _DriveTreeNode(
                    drive: drive,
                    label: label,
                    expanded: expanded,
                    childCount: children.length,
                    onToggle: () => _toggleDriveExpanded(drive),
                    onNavigate: widget.onNavigate,
                    children: children.map((child) => _ChildDirTile(
                      name: child.name,
                      path: child.path,
                      depth: 2,
                      onNavigate: widget.onNavigate,
                    )).toList(),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
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
  final ValueChanged<String> onNavigate;

  const _QuickAccessTile({required this.item, required this.onNavigate});

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

  bool get _isFileSystemPath =>
      item.path.isNotEmpty && !item.path.startsWith('::');

  @override
  Widget build(BuildContext context) {
    return _SidebarItem(
      onTap: () => onNavigate(item.path),
      leading: _ShellIcon(
        path: item.path,
        isDirectory: true,
        fallback: _fallbackIcon(),
      ),
      title: item.name,
      showArrow: false,
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
  final VoidCallback onToggle;
  final ValueChanged<String> onNavigate;
  final List<Widget> children;

  const _ThisPcTreeNode({
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.onNavigate,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarItem(
          onTap: () {
            onNavigate('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}');
            onToggle();
          },
          leading: _ShellIcon(
            path: '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
            isDirectory: true,
            fallback: Icons.computer,
          ),
          title: label,
          showArrow: true,
          expanded: expanded,
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// Tree node for a single drive.
class _DriveTreeNode extends StatefulWidget {
  final String drive;
  final String label;
  final bool expanded;
  final int childCount;
  final VoidCallback onToggle;
  final ValueChanged<String> onNavigate;
  final List<Widget> children;

  const _DriveTreeNode({
    required this.drive,
    required this.label,
    required this.expanded,
    required this.childCount,
    required this.onToggle,
    required this.onNavigate,
    required this.children,
  });

  @override
  State<_DriveTreeNode> createState() => _DriveTreeNodeState();
}

class _DriveTreeNodeState extends State<_DriveTreeNode> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarItem(
          depth: 1,
          onTap: () {
            widget.onNavigate(widget.drive);
            widget.onToggle();
          },
          leading: _ShellIcon(
            path: widget.drive,
            isDirectory: true,
            fallback: Icons.storage,
          ),
          title: widget.label,
          showArrow: widget.childCount > 0,
          expanded: widget.expanded,
        ),
        if (widget.expanded) ...widget.children,
      ],
    );
  }
}

/// A terminal directory child tile.
class _ChildDirTile extends StatelessWidget {
  final String name;
  final String path;
  final int depth;
  final ValueChanged<String> onNavigate;

  const _ChildDirTile({
    required this.name,
    required this.path,
    required this.depth,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return _SidebarItem(
      depth: depth,
      onTap: () => onNavigate(path),
      leading: _ShellIcon(
        path: path,
        isDirectory: true,
        fallback: Icons.folder,
      ),
      title: name,
      showArrow: false,
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
  final Widget? trailing;

  const _SidebarItem({
    this.depth = 0,
    this.onTap,
    required this.leading,
    required this.title,
    this.showArrow = false,
    this.expanded = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: const Color(0x11000000),
      child: SizedBox(
        height: 22,
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
