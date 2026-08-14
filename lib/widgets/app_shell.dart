import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import '../features/quick_view/quick_view_service.dart';
import '../features/quick_view/viewer_associations_dialog.dart';
import '../services/directory_repository.dart';
import '../services/file_operation_center.dart';
import '../services/file_service.dart';
import '../services/home_service.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/sidebar_controller.dart';
import '../state/theme_controller.dart';
import '../services/undo_redo_service.dart';
import 'app_theme.dart';
import 'app_menu.dart';
import 'close_confirmation.dart';
import 'command_menu.dart';
import 'confirm_dialog.dart';
import 'favorites_dialog.dart';
import 'file_task_center.dart';
import 'sidebar_tree.dart';
import 'layout_view.dart';
import 'file_pane.dart';
import 'window_controls.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

bool matchesUndoShortcut(KeyEvent event, HardwareKeyboard keyboard) {
  return event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyZ &&
      keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isShiftPressed;
}

bool matchesRedoShortcut(KeyEvent event, HardwareKeyboard keyboard) {
  return event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyY &&
      keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isShiftPressed;
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, WindowListener {
  bool _sidebarHovering = false;
  bool _sidebarDragging = false;

  /// 侧栏点击触发的导航：随后的 syncTo 不应让侧栏滚动到选中节点。
  /// navigateTo 同步触发 activePanePath → _syncSidebar，故在此消费。
  bool _suppressSidebarScroll = false;

  /// 原生关闭回调共享同一个 Future；所有退出入口只保存一次会话。
  Future<void>? _closeFuture;
  bool _sessionSaved = false;

  /// 文件任务中心面板是否展开；任务列表清空后自动收起。
  bool _taskCenterOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ServicesBinding.instance.keyboard.addHandler(_onKey);
    windowManager.addListener(this);
    context.read<AppState>().fileOperations.addListener(_onFileOperationsChanged);
    // 目录缓存被操作就地补丁/失效后，桥接到侧栏控制器重读（增量刷新）。
    context.read<DirectoryRepository>().onCacheChanged = _onRepositoryCacheChanged;
    // 焦点 pane 路径 → 侧栏同步（§12）：监听稳定 notifier，
    // 不再靠 didUpdateWidget 比较字符串驱动业务。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final layout = context.read<LayoutState>();
      layout.activePanePath.addListener(_syncSidebar);
      _syncSidebar();
    });
  }

  void _onRepositoryCacheChanged(String pathKey) {
    if (!mounted) return;
    context.read<SidebarSyncController>().onCachePatched(pathKey);
  }

  void _onFileOperationsChanged() {
    if (!_taskCenterOpen || !mounted) return;
    if (context.read<AppState>().fileOperations.tasks.isEmpty) {
      setState(() => _taskCenterOpen = false);
    }
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
    context.read<AppState>().fileOperations.removeListener(
      _onFileOperationsChanged,
    );
    context.read<DirectoryRepository>().onCacheChanged = null;
    context.read<LayoutState>().activePanePath.removeListener(_syncSidebar);
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_closeApplication());
  }

  void _saveSessionOnce() {
    if (_sessionSaved || !mounted) return;
    _sessionSaved = true;
    debugPrint('[LayoutCache] saving session before exit');
    context.read<LayoutState>().saveSession();
  }

  Future<void> _closeApplication() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    final closeFuture = () async {
      // 有进行中/排队中的文件操作时先确认，禁止静默中断（4.4）。
      final activeCount =
          context.read<AppState>().fileOperations.activeTasks.length;
      final confirmed = await confirmCloseWithActiveTasks(
        context,
        activeCount,
      );
      if (!confirmed) {
        // 用户取消：窗口保持打开，允许稍后重试关闭。
        _closeFuture = null;
        return;
      }
      _saveSessionOnce();
      // Release the native close so Windows can follow the normal
      // WM_CLOSE -> WM_DESTROY path and shut the Flutter engine down cleanly.
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }();
    _closeFuture = closeFuture;
    return closeFuture;
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
    _saveSessionOnce();
    return AppExitResponse.exit;
  }

  bool _onKey(KeyEvent event) {
    final layoutState = context.read<LayoutState>();
    final isAltDown =
        event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight);
    final isAltUp =
        event is KeyUpEvent &&
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
    // Ctrl+Z / Ctrl+Y — 撤销 / 重做
    if (matchesUndoShortcut(event, keyboard) ||
        matchesRedoShortcut(event, keyboard)) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return false;
      final undoRedo = context.read<UndoRedoService>();
      if (matchesUndoShortcut(event, keyboard)) {
        unawaited(
          undoRedo.undo(
            confirm: (title, message) => showConfirmDialog(
              context,
              title: title,
              message: message,
            ),
          ),
        );
      } else {
        unawaited(undoRedo.redo());
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
    final appState = context.watch<AppState>();
    final activePane = layoutState.allPaneNodes.isNotEmpty
        ? layoutState.controllerFor(layoutState.focusedNode)
        : null;

    return Scaffold(
      body: Column(
        children: [
          _TopBar(
            layoutState: layoutState,
            showHiddenFiles: appState.showHiddenFiles,
            showFileExtensions: appState.showFileExtensions,
            taskCenter: appState.fileOperations,
            taskCenterOpen: _taskCenterOpen,
            onToggleTaskCenter: () =>
                setState(() => _taskCenterOpen = !_taskCenterOpen),
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
            onExit: () => unawaited(_closeApplication()),
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
                        if (_taskCenterOpen)
                          Positioned(
                            right: AppMetrics.paneGap,
                            bottom: AppMetrics.paneGap,
                            child: FileTaskCenterPanel(
                              center: appState.fileOperations,
                              onClose: () =>
                                  setState(() => _taskCenterOpen = false),
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
  final FileOperationCenter taskCenter;
  final bool taskCenterOpen;
  final VoidCallback onToggleTaskCenter;
  final VoidCallback onToggleHiddenFiles;
  final VoidCallback onToggleFileExtensions;
  final VoidCallback onViewerAssociations;
  final VoidCallback onExit;

  const _TopBar({
    required this.layoutState,
    required this.showHiddenFiles,
    required this.showFileExtensions,
    required this.taskCenter,
    required this.taskCenterOpen,
    required this.onToggleTaskCenter,
    required this.onToggleHiddenFiles,
    required this.onToggleFileExtensions,
    required this.onViewerAssociations,
    required this.onExit,
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
                    onExit: onExit,
                  ),
                  const SizedBox(width: 8),
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
                    tooltip: showHiddenFiles ? '隐藏文件：显示中' : '隐藏文件：已隐藏',
                    active: showHiddenFiles,
                    onTap: onToggleHiddenFiles,
                  ),
                  _GhostIconButton(
                    icon: Icons.text_fields,
                    tooltip: showFileExtensions ? '文件后缀名：显示中' : '文件后缀名：已隐藏',
                    active: showFileExtensions,
                    onTap: onToggleFileExtensions,
                  ),
                  _GhostIconButton(
                    icon: theme.icon,
                    tooltip: '主题：${theme.label}',
                    onTap: theme.cycle,
                  ),
                  FileTaskCenterButton(
                    center: taskCenter,
                    open: taskCenterOpen,
                    onTap: onToggleTaskCenter,
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

class _AppMenus extends StatefulWidget {
  const _AppMenus({
    required this.layoutState,
    required this.onViewerAssociations,
    required this.onExit,
  });

  final LayoutState layoutState;
  final VoidCallback onViewerAssociations;
  final VoidCallback onExit;

  @override
  State<_AppMenus> createState() => _AppMenusState();
}

class _AppMenusState extends State<_AppMenus> {
  LayoutState get layoutState => widget.layoutState;
  VoidCallback get onViewerAssociations => widget.onViewerAssociations;
  VoidCallback get onExit => widget.onExit;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activePane = layoutState.allPaneNodes.isEmpty
        ? null
        : layoutState.controllerFor(layoutState.focusedNode);
    final currentPath = activePane?.currentPath;
    final canFavorite =
        activePane != null &&
        currentPath != null &&
        !FileService.isSpecialPath(currentPath);
    final isFavorite = canFavorite && HomeService.isFavorite(currentPath);
    final undoRedo = context.read<UndoRedoService>();

    // 历史栈变化时更新撤销/重做的可用状态。
    List<AppMenuGroup> groupsBuilder() => buildAppMenuGroups(
      layoutState: layoutState,
      appState: appState,
      activePane: activePane,
      isFavorite: isFavorite,
      canUndo: appState.history.canUndo,
      canRedo: appState.history.canRedo,
      onUndo: () => unawaited(
        undoRedo.undo(
          confirm: (title, message) =>
              showConfirmDialog(context, title: title, message: message),
        ),
      ),
      onRedo: () => unawaited(undoRedo.redo()),
      onExit: onExit,
      onViewerAssociations: onViewerAssociations,
      onAddFavorite: () {
        if (currentPath == null) return;
        HomeService.addFavorite(currentPath);
        layoutState.refreshPanesWhere(FileService.isHomePath);
        if (mounted) setState(() {});
      },
      onRemoveFavorite: () {
        if (currentPath == null) return;
        HomeService.removeFavorite(currentPath);
        layoutState.refreshPanesWhere(FileService.isHomePath);
        if (mounted) setState(() {});
      },
      onManageFavorites: () => showFavoritesDialog(context),
      onAbout: () => showAboutDialog(
        context: context,
        applicationName: 'Inf-Dir',
        applicationVersion: '1.0.0 (1)',
        applicationLegalese: '多面板文件管理器',
      ),
      onCopy: activePane == null
          ? null
          : () => copyPaneSelection(context, activePane),
      onCut: activePane == null
          ? null
          : () => cutPaneSelection(context, activePane),
      onPaste: activePane == null
          ? null
          : () => unawaited(pasteIntoPane(context, activePane)),
    );

    // 历史栈变化时更新撤销/重做的可用状态。
    return ListenableBuilder(
      listenable: appState.history,
      builder: (context, _) {
        final groups = groupsBuilder();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final group in groups)
              _MenuDropdown(
                label: group.label,
                buildEntries: () => group.items,
              ),
          ],
        );
      },
    );
  }
}

/// 带下拉菜单的菜单栏按钮，菜单展开于按钮正下方
class _MenuDropdown extends StatefulWidget {
  final String label;
  final List<CommandMenuItem> Function() buildEntries;

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
      items: entries,
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
            color: _open || _hovering ? c.surfaceHover : Colors.transparent,
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
