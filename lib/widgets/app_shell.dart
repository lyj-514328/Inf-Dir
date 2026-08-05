import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../features/quick_view/quick_view_service.dart';
import '../features/quick_view/viewer_associations_dialog.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/sidebar_controller.dart';
import '../state/theme_controller.dart';
import 'app_theme.dart';
import 'sidebar_tree.dart';
import 'layout_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  double _sidebarWidth = 220;
  bool _sidebarHovering = false;
  bool _sidebarDragging = false;

  /// 侧栏点击触发的导航：随后的 syncTo 不应让侧栏滚动到选中节点。
  /// navigateTo 同步触发 activePanePath → _syncSidebar，故在此消费。
  bool _suppressSidebarScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ServicesBinding.instance.keyboard.addHandler(_onKey);
    // 焦点 pane 路径 → 侧栏同步（§12）：监听稳定 notifier，
    // 不再靠 didUpdateWidget 比较字符串驱动业务。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final layout = context.read<LayoutState>();
      layout.activePanePath.addListener(_syncSidebar);
      _syncSidebar();
    });
  }

  void _syncSidebar() {
    final layout = context.read<LayoutState>();
    final suppress = _suppressSidebarScroll;
    _suppressSidebarScroll = false;
    context.read<SidebarSyncController>().syncTo(
          layout.activePanePath.value,
          scrollToSelected: !suppress,
        );
  }

  @override
  void dispose() {
    context.read<LayoutState>().activePanePath.removeListener(_syncSidebar);
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Alt+Tab 切换窗口后 KeyUpEvent 丢失，overlay 会残留。
    // 应用不可见时主动隐藏 overlay。
    if (state != AppLifecycleState.resumed) {
      context.read<LayoutState>().hideAltOverlay();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.altLeft ||
        event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.altRight) {
      context.read<LayoutState>().showAltOverlay();
    }
    if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.altLeft ||
        event is KeyUpEvent &&
            event.logicalKey == LogicalKeyboardKey.altRight) {
      context.read<LayoutState>().hideAltOverlay();
    }
    // F3 — Quick View
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f3 &&
        !keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isShiftPressed) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return false;
      final layout = context.read<LayoutState>();
      final node = layout.focusedNode;
      final ctrl = layout.controllerFor(node);
      final path =
          ctrl?.focusedPath ??
          (ctrl != null && ctrl.selectedPaths.isNotEmpty
              ? ctrl.selectedPaths.first
              : null);
      if (path != null) {
        unawaited(_openQuickView(path));
      }
      return true;
    }
    return false;
  }

  Future<void> _openQuickView(String path) async {
    final result = await context.read<QuickViewService>().open(path);
    if (!mounted || result.started) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layoutState = context.watch<LayoutState>();
    final activePane = layoutState.allPaneNodes.isNotEmpty
        ? layoutState.controllerFor(layoutState.focusedNode)
        : null;

    return Scaffold(
      body: Column(
        children: [
          _MenuBar(
            layoutState: layoutState,
            onViewerAssociations: () => showViewerAssociationsDialog(context),
          ),
          _WorkspaceBar(
            layoutState: layoutState,
            showHiddenFiles: context.watch<AppState>().showHiddenFiles,
            onToggleHiddenFiles: () {
              final app = context.read<AppState>();
              app.setShowHiddenFiles(!app.showHiddenFiles);
              // 缓存已清空，侧栏重新同步当前路径以应用新过滤。
              _syncSidebar();
            },
          ),
          Container(height: 1, color: c.border),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppMetrics.pagePadding),
              child: Row(
                children: [
                  Container(
                    margin: const EdgeInsets.all(1),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppMetrics.paneRadius,
                      ),
                      border: Border.all(color: c.border),
                      color: c.surface,
                    ),
                    child: SizedBox(
                      key: ValueKey(layoutState.activeWorkspaceIndex),
                      width: _sidebarWidth,
                      child: SidebarTree(
                        onNavigate: (path) {
                          _suppressSidebarScroll = true;
                          activePane?.navigateTo(path);
                          _suppressSidebarScroll = false;
                        },
                      ),
                    ),
                  ),
                  _SideSplitter(
                    hovering: _sidebarHovering,
                    dragging: _sidebarDragging,
                    onHoverChanged: (v) => setState(() => _sidebarHovering = v),
                    onDragStart: () => setState(() => _sidebarDragging = true),
                    onDragUpdate: (delta) => setState(
                      () => _sidebarWidth = (_sidebarWidth + delta).clamp(
                        150,
                        double.infinity,
                      ),
                    ),
                    onDragEnd: () {
                      setState(() => _sidebarDragging = false);
                    },
                  ),
                  Expanded(
                    child: LayoutView(node: layoutState.activeWorkspace),
                  ),
                ],
              ),
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
  final bool showHiddenFiles;
  final VoidCallback onToggleHiddenFiles;

  const _WorkspaceBar({
    required this.layoutState,
    required this.showHiddenFiles,
    required this.onToggleHiddenFiles,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();

    return Container(
      height: AppMetrics.workspaceBarHeight,
      color: c.surfaceSubtle,
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
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                Icons.add,
                size: AppMetrics.iconMd,
                color: c.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: showHiddenFiles ? '隐藏文件：显示中' : '隐藏文件：已隐藏',
            child: InkWell(
              onTap: onToggleHiddenFiles,
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Icon(
                  showHiddenFiles ? Icons.visibility : Icons.visibility_off,
                  size: AppMetrics.iconMd,
                  color: showHiddenFiles ? c.accent : c.textSecondary,
                ),
              ),
            ),
          ),
          Tooltip(
            message: '主题：${theme.label}',
            child: InkWell(
              onTap: theme.cycle,
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Icon(
                  theme.icon,
                  size: AppMetrics.iconMd,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '按住 Alt 显示面板操作',
              style: TextStyle(
                fontSize: AppMetrics.fontSmall,
                color: c.textTertiary,
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
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.tabRadius),
          border: Border.all(
            color: isActive ? c.borderStrong : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppMetrics.fontSmall,
                color: isActive ? c.textPrimary : c.textSecondary,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(2),
                child: Icon(Icons.close, size: 12, color: c.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({required this.layoutState, required this.onViewerAssociations});

  final LayoutState layoutState;
  final VoidCallback onViewerAssociations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      height: AppMetrics.menuBarHeight,
      color: c.surfaceSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const _MenuLabel('文件(F)'),
          const _MenuLabel('编辑(E)'),
          _MenuDropdown(
            label: '视图(V)',
            buildEntries: () => [
              _MenuEntry(
                '关闭面板',
                enabled: layoutState.allPaneNodes.length > 1,
                onTap: () => layoutState.closePane(layoutState.focusedNode),
              ),
              _MenuEntry(
                '水平切分',
                onTap: () => layoutState.splitPane(
                  layoutState.focusedNode,
                  SplitDirection.vertical,
                ),
              ),
              _MenuEntry(
                '垂直切分',
                onTap: () => layoutState.splitPane(
                  layoutState.focusedNode,
                  SplitDirection.horizontal,
                ),
              ),
            ],
          ),
          const _MenuLabel('收藏夹(A)'),
          _MenuDropdown(
            label: '选项(O)',
            buildEntries: () =>
                [_MenuEntry('查看器管理', onTap: onViewerAssociations)],
          ),
          const _MenuLabel('信息(H)'),
        ],
      ),
    );
  }
}

/// 无下拉的纯文本菜单项
class _MenuLabel extends StatelessWidget {
  final String label;

  const _MenuLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppMetrics.fontBody,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

class _MenuEntry {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _MenuEntry(this.label, {required this.onTap, this.enabled = true});
}

/// 带下拉菜单的菜单栏按钮，菜单展开于按钮正下方
class _MenuDropdown extends StatefulWidget {
  final String label;
  final List<_MenuEntry> Function() buildEntries;

  const _MenuDropdown({required this.label, required this.buildEntries});

  @override
  State<_MenuDropdown> createState() => _MenuDropdownState();
}

class _MenuDropdownState extends State<_MenuDropdown> {
  final GlobalKey _labelKey = GlobalKey();
  bool _open = false;

  Future<void> _show() async {
    final box = _labelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);

    final entries = widget.buildEntries();
    setState(() => _open = true);
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + box.size.height + 2,
          box.size.width,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: entries[i].enabled,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              entries[i].label,
              style: TextStyle(
                fontSize: AppMetrics.fontBody,
                color: entries[i].enabled
                    ? context.colors.textPrimary
                    : context.colors.textTertiary,
              ),
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) entries[picked].onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      key: _labelKey,
      onTap: _open ? null : _show,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _open ? c.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: AppMetrics.fontBody,
            color: c.textPrimary,
          ),
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
    final c = context.colors;

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
              ? c.accent
              : hovering
              ? c.accent.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
    );
  }
}
