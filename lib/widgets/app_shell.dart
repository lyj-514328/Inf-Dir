import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import '../features/quick_view/quick_view_service.dart';
import '../features/quick_view/viewer_associations_dialog.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/sidebar_controller.dart';
import '../state/theme_controller.dart';
import 'app_theme.dart';
import 'command_menu.dart';
import 'sidebar_tree.dart';
import 'layout_view.dart';
import 'file_pane.dart';
import 'window_controls.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, WindowListener {
  bool _sidebarHovering = false;
  bool _sidebarDragging = false;

  /// 侧栏点击触发的导航：随后的 syncTo 不应让侧栏滚动到选中节点。
  /// navigateTo 同步触发 activePanePath → _syncSidebar，故在此消费。
  bool _suppressSidebarScroll = false;

  /// 关闭流程已开始：防止重入的 onWindowClose 重复 flush / 重复投递关闭。
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ServicesBinding.instance.keyboard.addHandler(_onKey);
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
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
    debugPrint('[LayoutCache] AppShell.dispose');
    windowManager.removeListener(this);
    context.read<LayoutState>().activePanePath.removeListener(_syncSidebar);
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    debugPrint('[LayoutCache] onWindowClose -> flushing layout cache');
    if (_closing) return;
    _closing = true;
    if (mounted) {
      context.read<LayoutState>().flushLayoutCache();
    }
    // Re-enable the native close so the window tears down through the normal
    // WM_CLOSE → WM_DESTROY path, which cleanly shuts down the engine. Calling
    // destroy() here only posts WM_QUIT and leaves the window/engine alive,
    // freezing the process.
    unawaited(
      windowManager.setPreventClose(false).then((_) => windowManager.close()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Alt+Tab 切换窗口后 KeyUpEvent 丢失，overlay 会残留。
    // 应用不可见时主动隐藏 overlay。
    if (state != AppLifecycleState.resumed) {
      context.read<LayoutState>().hideAltOverlay();
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    debugPrint('[LayoutCache] didRequestAppExit triggered');
    context.read<LayoutState>().flushLayoutCache();
    return AppExitResponse.exit;
  }

  bool _onKey(KeyEvent event) {
    final layoutState = context.read<LayoutState>();
    final isAltDown = event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight);
    final isAltUp = event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight);
    // 最大化面板时 Alt 面板命令失效
    if (layoutState.maximizedPaneId == null) {
      if (isAltDown) layoutState.showAltOverlay();
      if (isAltUp) layoutState.hideAltOverlay();
    }
    final keyboard = HardwareKeyboard.instance;
    // F3 — Quick View
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
    toastification.show(
      title: const Text('快速查看'),
      description: Text(result.message),
      type: ToastificationType.warning,
      style: ToastificationStyle.flatColored,
      autoCloseDuration: const Duration(seconds: 4),
    );
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
          _TopBar(
            layoutState: layoutState,
            showHiddenFiles: context.watch<AppState>().showHiddenFiles,
            showFileExtensions: context.watch<AppState>().showFileExtensions,
            onToggleHiddenFiles: () {
              final app = context.read<AppState>();
              app.setShowHiddenFiles(!app.showHiddenFiles);
              layoutState.refreshAllPanes();
              // 缓存已清空，侧栏重新同步当前路径以应用新过滤。
              _syncSidebar();
            },
            onToggleFileExtensions: () {
              final app = context.read<AppState>();
              app.setShowFileExtensions(!app.showFileExtensions);
            },
            onViewerAssociations: () => showViewerAssociationsDialog(context),
          ),
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
                      color: c.surface,
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppMetrics.paneRadius,
                      ),
                      border: Border.all(color: c.border),
                    ),
                    child: SizedBox(
                      key: ValueKey(layoutState.activeWorkspaceIndex),
                      width: layoutState.sidebarWidth,
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
                    onDragUpdate: (delta) => layoutState.setSidebarWidth(
                      layoutState.sidebarWidth + delta,
                    ),
                    onDragEnd: () {
                      setState(() => _sidebarDragging = false);
                    },
                  ),
                  const SizedBox(width: AppMetrics.paneGap),
                  Expanded(
                    child: Stack(
                      children: [
                        LayoutView(node: layoutState.activeWorkspace),
                        if (layoutState.maximizedPaneId != null &&
                            layoutState.allPaneNodes.any(
                              (n) => n.paneId == layoutState.maximizedPaneId,
                            ))
                          Positioned.fill(
                            child: Container(
                              margin: EdgeInsets.all(AppMetrics.paneGap / 2),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppMetrics.paneRadius,
                                ),
                                color: c.surface,
                                boxShadow: [
                                  BoxShadow(
                                    color: c.scrim,
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              foregroundDecoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppMetrics.paneRadius,
                                ),
                                border: Border.all(
                                  color: c.accent.withValues(alpha: 0.6),
                                  width: 1,
                                ),
                              ),
                              child: FilePane(
                                paneId: layoutState.maximizedPaneId!,
                              ),
                            ),
                          ),
                      ],
                    ),
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

/// 统一顶栏：应用菜单 + 工作区标签 + 全局开关 + 窗口控制按钮，
/// 兼作无边框窗口的拖拽/双击最大化区域。
class _TopBar extends StatelessWidget {
  final LayoutState layoutState;
  final bool showHiddenFiles;
  final bool showFileExtensions;
  final VoidCallback onToggleHiddenFiles;
  final VoidCallback onToggleFileExtensions;
  final VoidCallback onViewerAssociations;

  const _TopBar({
    required this.layoutState,
    required this.showHiddenFiles,
    required this.showFileExtensions,
    required this.onToggleHiddenFiles,
    required this.onToggleFileExtensions,
    required this.onViewerAssociations,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();

    // DragToMoveArea 放在背景层：空白处可拖拽/双击最大化，
    // 前景交互控件（菜单、tab、按钮）不被原生拖动拦截。
    return SizedBox(
      height: AppMetrics.topBarHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: DragToMoveArea(
              child: Container(
                decoration: BoxDecoration(
                  color: c.windowBg,
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              // 右侧不留 padding：最大化时窗口按钮须触达屏幕边缘。
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  _AppMenus(
                    layoutState: layoutState,
                    onViewerAssociations: onViewerAssociations,
                  ),
                  const SizedBox(width: 8),
                  for (int i = 0;
                      i < layoutState.workspaces.length;
                      i++) ...[
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
                  _GhostIconButton(
                    icon: Icons.add,
                    tooltip: '新建工作区',
                    onTap: layoutState.addWorkspace,
                  ),
                  const Spacer(),
                  _GhostIconButton(
                    icon: showHiddenFiles
                        ? Icons.visibility
                        : Icons.visibility_off,
                    tooltip: showHiddenFiles
                        ? '隐藏文件：显示中'
                        : '隐藏文件：已隐藏',
                    active: showHiddenFiles,
                    onTap: onToggleHiddenFiles,
                  ),
                  _GhostIconButton(
                    icon: Icons.text_fields,
                    tooltip: showFileExtensions
                        ? '文件后缀名：显示中'
                        : '文件后缀名：已隐藏',
                    active: showFileExtensions,
                    onTap: onToggleFileExtensions,
                  ),
                  _GhostIconButton(
                    icon: theme.icon,
                    tooltip: '主题：${theme.label}',
                    onTap: theme.cycle,
                  ),
                  const SizedBox(width: 8),
                  const WindowControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 紧凑幽灵图标按钮（顶栏全局开关用）
class _GhostIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _GhostIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: AppMetrics.iconMd,
            color: active ? c.accent : c.textSecondary,
          ),
        ),
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

class _AppMenus extends StatelessWidget {
  const _AppMenus({
    required this.layoutState,
    required this.onViewerAssociations,
  });

  final LayoutState layoutState;
  final VoidCallback onViewerAssociations;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
          buildEntries: () => [
            _MenuEntry('查看器管理', onTap: onViewerAssociations),
          ],
        ),
        const _MenuLabel('信息(H)'),
      ],
    );
  }
}

/// 无下拉的纯文本菜单项（占位，保留 hover 反馈）
class _MenuLabel extends StatefulWidget {
  final String label;

  const _MenuLabel(this.label);

  @override
  State<_MenuLabel> createState() => _MenuLabelState();
}

class _MenuLabelState extends State<_MenuLabel> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _hovering ? c.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: AppMetrics.fontBody,
            color: c.textSecondary,
          ),
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
  bool _hovering = false;

  void _show() {
    final box = _labelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);

    final entries = widget.buildEntries();
    setState(() => _open = true);
    showCommandMenu(
      context,
      position: origin + Offset(0, box.size.height + 2),
      items: [
        for (final e in entries)
          CommandMenuItem(label: e.label, enabled: e.enabled, onAction: e.onTap),
      ],
      onClosed: () {
        if (mounted) setState(() => _open = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        key: _labelKey,
        onTap: _open ? null : _show,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _open || _hovering
                ? c.surfaceHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              color: c.textSecondary,
            ),
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
