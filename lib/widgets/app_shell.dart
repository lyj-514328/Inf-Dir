import 'package:flutter/material.dart';
import 'quad_layout.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _MenuBar(),
          _GlobalToolbar(),
          Container(height: 1, color: const Color(0xFFD0D0D0)),
          const Expanded(child: QuadLayout()),
        ],
      ),
    );
  }
}

class _MenuBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: const [
          _MenuItem('文件(F)'),
          _MenuItem('编辑(E)'),
          _MenuItem('视图(V)'),
          _MenuItem('收藏夹(A)'),
          _MenuItem('选项(O)'),
          _MenuItem('信息(H)'),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  const _MenuItem(this.label);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
        ),
      ),
    );
  }
}

class _GlobalToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _ToolButton(Icons.content_copy, '复制'),
          _ToolButton(Icons.content_cut, '剪切'),
          _ToolButton(Icons.content_paste, '粘贴'),
          _ToolButton(Icons.delete_outline, '删除'),
          const SizedBox(width: 8),
          _ToolButton(Icons.create_new_folder_outlined, '新建文件夹'),
          const Spacer(),
          _ToolButton(Icons.view_list, '列表'),
          _ToolButton(Icons.grid_view, '图标'),
          const SizedBox(width: 8),
          _ToolButton(Icons.search, '搜索'),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;

  const _ToolButton(this.icon, this.tooltip);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: const Color(0xFF555555)),
        ),
      ),
    );
  }
}
