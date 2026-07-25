import 'package:flutter/material.dart';
import 'file_pane.dart';
import 'sidebar_tree.dart';

/// 旧版固定四宫格布局（保留兼容，主布局已迁移至 LayoutView）
class QuadLayout extends StatelessWidget {
  const QuadLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 侧边栏暂时显示空路径
        SidebarTree(
          activePath: '',
          onNavigate: (_) {},
        ),
        Container(width: 1, color: const Color(0xFFD0D0D0)),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Expanded(child: FilePane(paneId: 'pane_0')),
                    VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: FilePane(paneId: 'pane_1')),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: Row(
                  children: const [
                    Expanded(child: FilePane(paneId: 'pane_2')),
                    VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: FilePane(paneId: 'pane_3')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
