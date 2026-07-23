import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/file_service.dart';

class SidebarTree extends StatefulWidget {
  final ValueChanged<String> onNavigate;

  const SidebarTree({super.key, required this.onNavigate});

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

class _SidebarTreeState extends State<SidebarTree> {
  late final List<_QuickItem> _quickItems;
  late final List<String> _drives;

  @override
  void initState() {
    super.initState();
    _quickItems = [
      _QuickItem('桌面', FileService.desktopPath, Icons.desktop_windows),
      _QuickItem('文档', FileService.documentsPath, Icons.description),
      _QuickItem('下载', FileService.downloadsPath, Icons.download),
      _QuickItem('图片', FileService.picturesPath, Icons.image),
      _QuickItem('音乐', FileService.musicPath, Icons.music_note),
      _QuickItem('视频', FileService.videosPath, Icons.videocam),
    ];
    _drives = FileService.getDrives();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: const Color(0xFFF8F8F8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('快速访问'),
            for (final item in _quickItems)
              _TreeNodeWidget(
                label: item.label,
                path: item.path,
                icon: item.icon,
                depth: 0,
                onNavigate: widget.onNavigate,
              ),
            const Divider(height: 1, thickness: 1),
            const _SectionLabel('此电脑'),
            for (final drive in _drives)
              _TreeNodeWidget(
                label: drive,
                path: drive,
                icon: Icons.storage,
                depth: 0,
                onNavigate: widget.onNavigate,
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickItem {
  final String label;
  final String path;
  final IconData icon;
  _QuickItem(this.label, this.path, this.icon);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF888888),
        ),
      ),
    );
  }
}

class _TreeNodeWidget extends StatefulWidget {
  final String label;
  final String path;
  final IconData icon;
  final int depth;
  final ValueChanged<String> onNavigate;

  const _TreeNodeWidget({
    required this.label,
    required this.path,
    required this.icon,
    required this.depth,
    required this.onNavigate,
  });

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  bool _expanded = false;
  List<_ChildDir>? _children;

  Future<void> _toggleExpand() async {
    if (!_expanded && _children == null) {
      final children = await _loadSubDirs(widget.path);
      setState(() {
        _children = children;
        _expanded = true;
      });
    } else {
      setState(() => _expanded = !_expanded);
    }
  }

  Future<List<_ChildDir>> _loadSubDirs(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      final entities = await dir.list(followLinks: false).toList();
      final dirs = entities
          .whereType<Directory>()
          .map((d) => _ChildDir(p.basename(d.path), d.path))
          .toList();
      dirs.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return dirs;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            widget.onNavigate(widget.path);
            _toggleExpand();
          },
          child: SizedBox(
            height: 22,
            child: Row(
              children: [
                SizedBox(width: 4.0 + widget.depth * 16.0),
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: const Color(0xFF888888),
                ),
                const SizedBox(width: 2),
                Icon(widget.icon, size: 15, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && _children != null)
          for (final child in _children!)
            _TreeNodeWidget(
              label: child.name,
              path: child.path,
              icon: Icons.folder,
              depth: widget.depth + 1,
              onNavigate: widget.onNavigate,
            ),
      ],
    );
  }
}

class _ChildDir {
  final String name;
  final String path;
  _ChildDir(this.name, this.path);
}
