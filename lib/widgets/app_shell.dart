import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/layout_state.dart';
import 'sidebar_tree.dart';
import 'layout_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  double _sidebarWidth = 220;
  bool _sidebarHovering = false;
  bool _sidebarDragging = false;

  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.altLeft ||
        event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.altRight) {
      context.read<LayoutState>().showAltOverlay();
    }
    if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.altLeft ||
        event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.altRight) {
      context.read<LayoutState>().hideAltOverlay();
    }
    return false; // 不拦截，继续传递给其他 handler
  }

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutState>();
    final activePane = layoutState.allPaneNodes.isNotEmpty
        ? layoutState.controllerFor(layoutState.focusedNode)
        : null;

    return Scaffold(
      body: Column(
        children: [
          _MenuBar(),
          _GlobalToolbar(layoutState: layoutState),
          Container(height: 1, color: const Color(0xFFD0D0D0)),
          _WorkspaceBar(layoutState: layoutState),
          Container(height: 1, color: const Color(0xFFD0D0D0)),
          Expanded(
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.all(1),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: SizedBox(
                    width: _sidebarWidth,
                    child: SidebarTree(
                      activePath: activePane?.displayPath ?? '',
                      onNavigate: (path) {
                        activePane?.navigateTo(path);
                      },
                    ),
                  ),
                ),
                _SideSplitter(
                  hovering: _sidebarHovering,
                  dragging: _sidebarDragging,
                  onHoverChanged: (v) => setState(() => _sidebarHovering = v),
                  onDragStart: () => setState(() => _sidebarDragging = true),
                  onDragUpdate: (delta) => setState(() => _sidebarWidth = (_sidebarWidth + delta).clamp(150, 500)),
                  onDragEnd: () => setState(() => _sidebarDragging = false),
                ),
                Expanded(
                  child: LayoutView(node: layoutState.activeWorkspace),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 工作区标签栏
class _WorkspaceBar extends StatelessWidget {
  final LayoutState layoutState;

  const _WorkspaceBar({required this.layoutState});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (int i = 0; i < layoutState.workspaces.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _WorkspaceTab(
              label: layoutState.workspaces[i].label ?? 'WS$i',
              isActive: i == layoutState.activeWorkspaceIndex,
              onTap: () => layoutState.switchWorkspace(i),
              onClose: layoutState.workspaces.length > 1
                  ? () => layoutState.removeWorkspace(i)
                  : null,
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            onTap: () => layoutState.addWorkspace(),
            borderRadius: BorderRadius.circular(3),
            child: const SizedBox(
              width: 26,
              height: 26,
              child: Icon(Icons.add, size: 16, color: Color(0xFF555555)),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '按住 Alt 显示面板操作',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _WorkspaceTab({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? const Color(0xFFB0B0B0) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? const Color(0xFF333333) : const Color(0xFF777777),
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(2),
                child: const Icon(Icons.close, size: 12, color: Color(0xFF888888)),
              ),
            ],
          ],
        ),
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
          _MenuLabel('文件(F)'),
          _MenuLabel('编辑(E)'),
          _MenuLabel('视图(V)'),
          _MenuLabel('收藏夹(A)'),
          _MenuLabel('选项(O)'),
          _MenuLabel('信息(H)'),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final String label;
  const _MenuLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
      ),
    );
  }
}

class _GlobalToolbar extends StatelessWidget {
  final LayoutState layoutState;

  const _GlobalToolbar({required this.layoutState});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _ToolButton(Icons.content_copy, '复制', () {}),
          _ToolButton(Icons.content_cut, '剪切', () {}),
          _ToolButton(Icons.content_paste, '粘贴', () {}),
          _ToolButton(Icons.delete_outline, '删除', () {}),
          const SizedBox(width: 8),
          _ToolButton(Icons.create_new_folder_outlined, '新建文件夹', () {}),
          const Spacer(),
          _ToolButton(Icons.view_list, '列表', () {}),
          _ToolButton(Icons.grid_view, '图标', () {}),
          const SizedBox(width: 8),
          _ToolButton(Icons.search, '搜索', () {}),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolButton(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
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

/// 侧边栏与主内容区的可拖拽分隔线，风格与 pane 间 splitter 一致
class _SideSplitter extends StatelessWidget {
  final bool hovering;
  final bool dragging;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _SideSplitter({
    required this.hovering,
    required this.dragging,
    required this.onHoverChanged,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (details) => onDragUpdate(details.delta.dx),
        onPanEnd: (_) => onDragEnd(),
        child: Container(
          width: 2,
          color: dragging
              ? cs.primary
              : hovering
                  ? cs.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
        ),
      ),
    );
  }
}
