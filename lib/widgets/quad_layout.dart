import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'file_pane.dart';
import 'sidebar_tree.dart';

class QuadLayout extends StatelessWidget {
  const QuadLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    return Row(
      children: [
        SidebarTree(
          onNavigate: (path) {
            appState.activePane.navigateTo(path);
          },
        ),
        Container(width: 1, color: const Color(0xFFD0D0D0)),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Expanded(child: FilePane(paneIndex: 0)),
                    VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: FilePane(paneIndex: 1)),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: Row(
                  children: const [
                    Expanded(child: FilePane(paneIndex: 2)),
                    VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: FilePane(paneIndex: 3)),
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
