import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/pane_controller.dart';
import '../services/cloud_drive_service.dart';
import '../services/file_service.dart';
import '../services/shell_context_menu.dart';
import 'app_theme.dart';
import 'file_list_view.dart';
import 'address_bar.dart';
import 'command_menu.dart';
import 'nav_toolbar.dart';
import 'pane_tab_bar.dart';
import 'home_view.dart';

class FilePane extends StatelessWidget {
  final String paneId;

  const FilePane({super.key, required this.paneId});

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutState>();
    final node = layoutState.allPaneNodes.firstWhere(
      (n) => n.paneId == paneId,
      orElse: () => layoutState.allPaneNodes.first,
    );
    final controller = layoutState.controllerFor(node);

    if (controller == null) return const SizedBox.shrink();

    return ChangeNotifierProvider<PaneController>.value(
      value: controller,
      child: _PaneContent(paneNode: node),
    );
  }
}

class _PaneContent extends StatelessWidget {
  final LayoutNode paneNode;

  const _PaneContent({required this.paneNode});

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final controller = context.read<PaneController>();
    final layoutState = context.watch<LayoutState>();
    final isActive = layoutState.focusedNodeId == paneNode.id;

    final c = context.colors;
    final result = Column(
      children: [
        Container(
          color: c.surfaceSubtle,
          child: Column(
            children: [
              const _PaneTabBarSection(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppMetrics.paneGap,
                  1,
                  AppMetrics.paneGap,
                  5,
                ),
                child: _PaneLocationSection(
                  onCommandMenu: (pos) => _openCommandMenu(context, pos),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.isHome
              ? HomeView(
                  controller: controller,
                  onNavigate: controller.navigateTo,
                  showFileExtensions: context
                      .watch<AppState>()
                      .showFileExtensions,
                )
              : Focus(
                  autofocus: false,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.backspace ||
                          (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                              HardwareKeyboard.instance.isAltPressed)) {
                        controller.goUp();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                          HardwareKeyboard.instance.isAltPressed) {
                        controller.goBack();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                          HardwareKeyboard.instance.isAltPressed) {
                        controller.goForward();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.f5) {
                        controller.refresh();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.keyA &&
                          HardwareKeyboard.instance.isControlPressed) {
                        controller.selectAll();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.enter) {
                        _openSelected(context, controller);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.delete) {
                        if (!FileService.isRecycleBinPath(
                          controller.currentPath,
                        )) {
                          _deleteSelected(context);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.f2) {
                        if (!FileService.isRecycleBinPath(
                          controller.currentPath,
                        )) {
                          _renameSelected(context);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.keyC &&
                          HardwareKeyboard.instance.isControlPressed) {
                        _copySelected(context);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.keyX &&
                          HardwareKeyboard.instance.isControlPressed) {
                        if (FileService.isRecycleBinPath(
                          controller.currentPath,
                        )) {
                          return KeyEventResult.handled;
                        }
                        _cutSelected(context);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.keyV &&
                          HardwareKeyboard.instance.isControlPressed) {
                        if (FileService.isRecycleBinPath(
                          controller.currentPath,
                        )) {
                          return KeyEventResult.handled;
                        }
                        _paste(context);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _FileListSection(isActive: isActive),
                ),
        ),
        if (!controller.isHome) const _StatusBarSection(),
      ],
    );

    sw.stop();
    if (sw.elapsedMilliseconds > 10) {
      debugPrint(
        '[Perf] _PaneContent build: ${sw.elapsedMilliseconds}ms, entries=${controller.entries.length}',
      );
    }
    return result;
  }

  // ── Open / Navigate ────────────────────────────────────────────────

  Future<void> _createFolder(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建文件夹',
      initialValue: '新建文件夹',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await FileService.createFolder(controller.currentPath, name.trim());
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件夹失败', e);
    }
  }

  Future<void> _createTextFile(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建文本文档',
      initialValue: '新建文本文档.txt',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await FileService.createTextFile(controller.currentPath, name.trim());
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件失败', e);
    }
  }

  void _showProperties(BuildContext context) {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    _showNativeMenuAtToolbar(context, paths);
  }

  void _openCommandMenu(BuildContext context, Offset position) {
    final controller = context.read<PaneController>();
    final appState = context.read<AppState>();
    final isHome = controller.isHome;
    final currentPath = controller.currentPath;
    final selectionCount = controller.selectedPaths.length;
    final canSelect = !isHome && selectionCount > 0;
    final canCreate =
        !isHome &&
        !FileService.isSpecialPath(currentPath) &&
        !FileService.isRecycleBinPath(currentPath);
    final canRename =
        canSelect &&
        selectionCount == 1 &&
        !FileService.isRecycleBinPath(currentPath);
    final canDelete = canSelect && !FileService.isRecycleBinPath(currentPath);

    showCommandMenu(
      context,
      position: position,
      config: CommandMenuConfig(
        searchQuery: controller.filterQuery,
        onSearchChanged: controller.setFilterQuery,
        canCreate: canCreate,
        canCut: canSelect && !FileService.isRecycleBinPath(currentPath),
        canCopy: canSelect,
        canPaste: canCreate && appState.hasClipboard,
        canRename: canRename,
        canDelete: canDelete,
        canSelectAll: !isHome && controller.visibleEntries.isNotEmpty,
        canShowProperties: canSelect,
        showHiddenFiles: appState.showHiddenFiles,
        showFileExtensions: appState.showFileExtensions,
        sortColumn: controller.sortColumn,
        sortAscending: controller.sortAscending,
        viewMode: controller.viewMode,
        entryFilter: controller.entryFilter,
        onCreateFolder: () => _createFolder(context),
        onCreateTextFile: () => _createTextFile(context),
        onCut: () => _cutSelected(context),
        onCopy: () => _copySelected(context),
        onPaste: () => _paste(context),
        onRename: () => _renameSelected(context),
        onDelete: () => _deleteSelected(context),
        onSortColumn: controller.setSortColumn,
        onSortAscending: controller.setSortAscending,
        onViewMode: controller.setViewMode,
        onFilter: controller.setEntryFilter,
        onSelectAll: controller.selectAll,
        onRefresh: controller.refresh,
        onToggleHiddenFiles: () {
          appState.setShowHiddenFiles(!appState.showHiddenFiles);
          context.read<LayoutState>().refreshAllPanes();
        },
        onToggleFileExtensions: () {
          appState.setShowFileExtensions(!appState.showFileExtensions);
        },
        onProperties: () => _showProperties(context),
      ),
    );
  }

  void _showNativeMenuAtToolbar(BuildContext context, List<String> paths) {
    final size = MediaQuery.sizeOf(context);
    _showNativeMenu(
      context,
      paths,
      Offset(size.width * 0.5, AppMetrics.commandBarHeight * 3.5),
    );
  }

  void _openSelected(BuildContext context, PaneController controller) {
    // In the Recycle Bin, Enter does nothing
    if (FileService.isRecycleBinPath(controller.currentPath)) return;
    if (controller.selectedPaths.isEmpty) return;
    _handleDoubleTap(context, controller, controller.selectedPaths.first);
  }

  // ── Keyboard-triggered operations ──────────────────────────────────

  void _copySelected(BuildContext context) {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    if (controller.selectedPaths.isNotEmpty) {
      appState.copyPaths(controller.selectedPaths.toList());
      Clipboard.setData(
        ClipboardData(text: controller.selectedPaths.join('\n')),
      );
    }
  }

  void _cutSelected(BuildContext context) {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    if (controller.selectedPaths.isNotEmpty) {
      appState.cutPaths(controller.selectedPaths.toList());
    }
  }

  Future<void> _paste(BuildContext context) async {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();

    // Cannot paste into the Recycle Bin
    if (FileService.isSpecialPath(controller.currentPath)) return;

    if (!appState.hasClipboard) return;

    final destDir = controller.currentPath;
    for (final srcPath in appState.clipboardPaths) {
      try {
        if (appState.clipboardIsCut) {
          await FileService.moveEntry(srcPath, destDir);
        } else {
          await FileService.copyEntry(srcPath, destDir);
        }
      } catch (_) {}
    }
    if (appState.clipboardIsCut) appState.clearClipboard();
    controller.refresh();
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final controller = context.read<PaneController>();

    // In Recycle Bin, deletion is handled by the shell context menu
    if (FileService.isRecycleBinPath(controller.currentPath)) return;

    final selected = controller.selectedPaths.toList();
    if (selected.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          selected.length == 1
              ? '确定要删除 "${_basename(selected.first)}" 吗？'
              : '确定要删除 ${selected.length} 个项目吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: context.colors.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    for (final path in selected) {
      try {
        await FileService.deleteEntry(path);
      } catch (_) {}
    }
    controller.refresh();
  }

  void _showOperationError(
    BuildContext context,
    String operation,
    Object error,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$operation: $error'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ── Sections：按需重建，避免选中/加载时整个面板 rebuild ──────────────

class _PaneTabBarSection extends StatelessWidget {
  const _PaneTabBarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (List<TabInfo>, int)>(
      selector: (_, c) => (c.tabs, c.activeTabIndex),
      shouldRebuild: (a, b) => !listEquals(a.$1, b.$1) || a.$2 != b.$2,
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return PaneTabBar(
          tabs: sel.$1,
          activeIndex: sel.$2,
          onSwitchTab: controller.switchTab,
          onCloseTab: controller.closeTab,
          onAddTab: () => controller.addTab(),
        );
      },
    );
  }
}

class _PaneLocationSection extends StatelessWidget {
  final ValueChanged<Offset> onCommandMenu;

  const _PaneLocationSection({required this.onCommandMenu});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.addressBarHeight,
      child: Row(
        children: [
          _NavToolbarSection(onCommandMenu: onCommandMenu),
          const SizedBox(width: 4),
          const Expanded(child: _AddressBarSection()),
        ],
      ),
    );
  }
}

class _NavToolbarSection extends StatelessWidget {
  final ValueChanged<Offset> onCommandMenu;

  const _NavToolbarSection({required this.onCommandMenu});

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (bool, bool, bool, bool)>(
      selector: (_, c) => (
        c.canGoBack,
        c.canGoForward,
        c.canGoUp,
        c.filterQuery.isNotEmpty || c.entryFilter != EntryFilter.all,
      ),
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return NavToolbar(
          canGoBack: sel.$1,
          canGoForward: sel.$2,
          canGoUp: sel.$3,
          commandMenuActive: sel.$4,
          onBack: controller.goBack,
          onForward: controller.goForward,
          onUp: controller.goUp,
          onRefresh: controller.refresh,
          onCommandMenu: onCommandMenu,
        );
      },
    );
  }
}

class _AddressBarSection extends StatelessWidget {
  const _AddressBarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (String, String)>(
      selector: (_, c) => (c.displayPath, c.currentPath),
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return AddressBar(
          currentPath: sel.$1,
          iconPath: sel.$2,
          onSubmit: (path) => controller.navigateTo(path),
        );
      },
    );
  }
}

class _FileListSection extends StatelessWidget {
  final bool isActive;

  const _FileListSection({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PaneController>();
    final appState = context.watch<AppState>();
    final entries = controller.visibleEntries;
    return Row(
      children: [
        Expanded(
          child: FileListView(
            entries: entries,
            selectedPaths: controller.selectedPaths,
            isActive: isActive,
            loading: controller.isLoading,
            sortColumn: controller.sortColumn,
            sortAscending: controller.sortAscending,
            onSort: controller.sortBy,
            viewMode: controller.viewMode,
            showFileExtensions: appState.showFileExtensions,
            columnWidths: controller.columnWidths,
            onResizeColumn: controller.resizeColumn,
            onInitWidths: controller.initColumnWidths,
            // 当前目录位于云同步区（OneDrive 等）时显示"状态"列，同资源管理器。
            showStatusColumn: CloudDriveService.isCloudZone(
              controller.currentPath,
            ),
            onSingleTap: (path) {
              final ctrl = HardwareKeyboard.instance.isControlPressed;
              final shift = HardwareKeyboard.instance.isShiftPressed;
              if (shift) {
                controller.selectRange(path);
              } else if (ctrl) {
                controller.toggleSelection(path);
              } else {
                controller.selectSingle(path);
              }
            },
            onDoubleTap: (path) => _handleDoubleTap(context, controller, path),
            onItemRightClick: (path, pos) =>
                _showNativeMenu(context, [path], pos),
            onEmptyRightClick: (pos) => _showNativeMenu(context, [], pos),
          ),
        ),
      ],
    );
  }
}

class _StatusBarSection extends StatelessWidget {
  const _StatusBarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (int, bool, int)>(
      selector: (_, c) => (c.entryCount, c.isLoading, c.selectedCount),
      builder: (context, sel, _) =>
          _StatusBar(loaded: sel.$1, isLoading: sel.$2, selectedCount: sel.$3),
    );
  }
}

// ── 顶层辅助函数 ──────────────────────────────────────────────────────

FileEntry? _findEntry(PaneController controller, String path) {
  for (final e in controller.entries) {
    if (e.path == path) return e;
  }
  return null;
}

String _basename(String path) {
  final idx = path.lastIndexOf(RegExp(r'[\\/]'));
  return idx >= 0 ? path.substring(idx + 1) : path;
}

void _handleDoubleTap(
  BuildContext context,
  PaneController controller,
  String path,
) {
  // In the Recycle Bin, double-click does nothing useful; use right-click
  if (FileService.isRecycleBinPath(controller.currentPath)) return;

  final entry = _findEntry(controller, path);
  if (entry == null) return;
  if (entry.isDirectory) {
    controller.navigateTo(path);
  } else {
    FileService.openFile(path);
  }
}

void _showNativeMenu(
  BuildContext context,
  List<String> selectedPaths,
  Offset position,
) {
  final controller = context.read<PaneController>();

  // If right-clicking an unselected item, select only it
  if (selectedPaths.length == 1 &&
      !controller.selectedPaths.contains(selectedPaths.first)) {
    controller.clearSelection();
    controller.toggleSelection(selectedPaths.first);
  } else if (selectedPaths.isEmpty) {
    controller.clearSelection();
  }

  // Use all currently selected paths for the menu
  final paths = selectedPaths.isEmpty
      ? <String>[]
      : controller.selectedPaths.toList();

  // Convert logical (window-relative) → screen physical coordinates
  final dpr = View.of(context).devicePixelRatio;
  final (screenX, screenY) = ShellContextMenu.toScreenCoords(
    position.dx,
    position.dy,
    dpr,
  );

  final verb = ShellContextMenu.show(
    folderPath: controller.currentPath,
    selectedPaths: paths,
    screenX: screenX,
    screenY: screenY,
  );

  if (!context.mounted) return;
  _handleVerb(context, verb, paths);
}

void _handleVerb(
  BuildContext context,
  String? verb,
  List<String> selectedPaths,
) {
  if (verb == null) return;

  final appState = context.read<AppState>();
  final controller = context.read<PaneController>();

  switch (verb) {
    case 'open':
    case 'explore':
      // Intercepted — navigate for dirs, open for files
      if (selectedPaths.length == 1) {
        _handleDoubleTap(context, controller, selectedPaths.first);
      }
    case 'rename':
      // Intercepted — show our rename dialog
      _renameSelected(context);
    case 'copy':
      // Shell put CF_HDROP on clipboard; sync our app clipboard
      if (selectedPaths.isNotEmpty) {
        appState.copyPaths(selectedPaths);
      }
      controller.refresh();
    case 'cut':
      if (selectedPaths.isNotEmpty) {
        appState.cutPaths(selectedPaths);
      }
      controller.refresh();
    case 'delete':
      controller.refresh();
    case 'paste':
      appState.clearClipboard();
      controller.refresh();
    default:
      // Properties, copy-as-path, shell extensions, etc.
      // No filesystem change — no refresh needed.
      break;
  }
}

Future<void> _renameSelected(BuildContext context) async {
  final controller = context.read<PaneController>();

  // In Recycle Bin, items cannot be renamed
  if (FileService.isRecycleBinPath(controller.currentPath)) return;

  if (controller.selectedPaths.length != 1) return;
  final oldPath = controller.selectedPaths.first;
  final oldName = _basename(oldPath);

  final newName = await _showInputDialog(
    context,
    title: '重命名',
    initialValue: oldName,
    confirmText: '确定',
  );

  if (newName == null || newName.isEmpty || newName == oldName) return;

  try {
    await FileService.renameEntry(oldPath, newName);
    controller.refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重命名失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

Future<String?> _showInputDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String confirmText,
}) {
  final textController = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = context.colors;
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              borderSide: BorderSide(color: c.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
            ),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
}

class _StatusBar extends StatelessWidget {
  final int loaded;
  final bool isLoading;
  final int selectedCount;

  const _StatusBar({
    required this.loaded,
    required this.isLoading,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String text;
    if (isLoading) {
      text = '正在加载...';
    } else {
      text = '$loaded 个对象';
    }
    if (selectedCount > 0) {
      text = '已选择 $selectedCount 个对象  |  $text';
    }
    return Container(
      height: AppMetrics.statusBarHeight,
      decoration: BoxDecoration(
        color: c.surfaceSubtle,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(fontSize: AppMetrics.fontSmall, color: c.textTertiary),
      ),
    );
  }
}
