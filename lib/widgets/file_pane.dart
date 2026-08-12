import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../features/quick_view/quick_view_service.dart';
import '../models/file_entry.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/pane_controller.dart';
import '../services/cloud_drive_service.dart';
import '../services/file_service.dart';
import '../services/shell_context_menu.dart';
import '../services/shell_new_service.dart';
import '../services/open_with_menu_service.dart';
import 'app_theme.dart';
import 'file_list_view.dart';
import 'address_bar.dart';
import 'command_menu.dart';
import 'file_context_menu.dart';
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
              _PaneTabBarSection(paneId: paneNode.paneId!),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppMetrics.paneGap,
                  1,
                  AppMetrics.paneGap,
                  5,
                ),
                child: const _PaneLocationSection(),
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
                  child: _FileListSection(
                    isActive: isActive,
                    onItemContextMenu: (path, position) =>
                        _openItemContextMenu(context, path, position),
                    onFolderContextMenu: (position) =>
                        _openFolderContextMenu(context, position),
                  ),
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

  Future<void> _createFile(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建文件',
      initialValue: '新建文件',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await FileService.createFile(controller.currentPath, name.trim());
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件失败', e);
    }
  }

  List<ShellNewEntry> _shellNewEntries(BuildContext context) {
    final iconSize = (AppMetrics.iconMd * View.of(context).devicePixelRatio)
        .ceil();
    return ShellNewService.getEntries(iconSize);
  }

  Future<void> _createShortcutFromDialog(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }

    final target = await _showInputDialog(
      context,
      title: '创建快捷方式',
      initialValue: '',
      confirmText: '下一步',
    );
    if (target == null || target.trim().isEmpty || !context.mounted) return;

    final normalizedTarget = target.trim().replaceAll('"', '');
    final targetName = p.basename(normalizedTarget);
    final name = await _showInputDialog(
      context,
      title: '快捷方式名称',
      initialValue: targetName.isEmpty ? '新建快捷方式' : targetName,
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await FileService.createShortcutIn(
        normalizedTarget,
        controller.currentPath,
        name: name,
      );
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建快捷方式失败', e);
    }
  }

  Future<void> _createFromTemplate(
    BuildContext context,
    ShellNewEntry entry,
  ) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    if (entry.isCommandBased) {
      try {
        await ShellNewService.create(controller.currentPath, entry, '');
        controller.refresh();
      } catch (e) {
        if (context.mounted) _showOperationError(context, '创建文件失败', e);
      }
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建${entry.name}',
      initialValue: '新建 ${entry.name}',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ShellNewService.create(controller.currentPath, entry, name.trim());
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件失败', e);
    }
  }

  Future<void> _openItemContextMenu(
    BuildContext context,
    String clickedPath,
    Offset position,
  ) async {
    final controller = context.read<PaneController>();

    // Preserve a multi-selection when right-clicking one of its items.
    if (!controller.selectedPaths.contains(clickedPath)) {
      controller.selectSingle(clickedPath);
    }

    final paths = controller.selectedPaths.toList();
    final singlePath = paths.length == 1 ? paths.first : null;
    final singleEntry = singlePath == null
        ? null
        : _findEntry(controller, singlePath);
    final isRecycleBin = FileService.isRecycleBinPath(controller.currentPath);
    final canModify =
        paths.isNotEmpty && !FileService.isSpecialPath(controller.currentPath);
    final isDir = singleEntry?.isDirectory ?? false;
    final canOpenDir = singleEntry != null && isDir && !isRecycleBin;
    final canOpenFile = singleEntry != null && !isDir && !isRecycleBin;
    final menuIconSize = (AppMetrics.iconMd * View.of(context).devicePixelRatio)
        .ceil();
    final openWithData = canOpenFile
        ? _buildOpenWithMenu(singlePath!, menuIconSize)
        : null;

    String? compressName;
    if (canModify) {
      compressName = (singleEntry != null && !singleEntry.isDirectory)
          ? p.basenameWithoutExtension(paths.first)
          : p.basename(paths.first);
    }

    showCommandMenu(
      context,
      position: position,
      items: buildFileItemContextMenuItems(
        onOpen: singleEntry != null && !isRecycleBin
            ? () => _handleDoubleTap(context, controller, singlePath!)
            : null,
        openImage: openWithData?.defaultAppImage,
        onOpenWith: canOpenFile ? () => _openWith(context, singlePath!) : null,
        openWithChildren: openWithData?.items,
        onQuickView: canOpenFile
            ? () => _openQuickView(context, singlePath!)
            : null,
        onOpenInNewTab: canOpenDir
            ? () => controller.addTab(singlePath!)
            : null,
        onOpenInNewWindow: canOpenDir ? () {} : null,
        onOpenInNewPane: canOpenDir
            ? (direction) => _openInNewPane(context, direction, singlePath!)
            : null,
        onCut: canModify ? () => _cutSelected(context) : null,
        onCopy: canModify ? () => _copySelected(context) : null,
        onRename: canModify && paths.length == 1
            ? () => _renameSelected(context)
            : null,
        onDelete: canModify ? () => _deleteSelected(context) : null,
        onPasteShortcut: canModify && context.read<AppState>().hasClipboard
            ? () => _pasteShortcut(context)
            : null,
        onCopyPath: () => _copySelectedPaths(context),
        onCreateFolderWithSelection: canModify
            ? () => _createFolderWithSelection(context)
            : null,
        onCreateShortcut: canModify ? () => _createShortcuts(context) : null,
        compressName: compressName,
        onCompressZip: canModify ? () => _compressZip(context) : null,
        onSendTo: canModify ? () {} : null,
        onOpenInTerminal: canOpenDir
            ? () => _openTerminal(context, singlePath!)
            : null,
        onPinToSidebar: canOpenDir ? () {} : null,
        onProperties: canModify
            ? () => _showPropertiesVerb(context, paths)
            : null,
        onShowMoreOptions: () => _showNativeMenu(context, paths, position),
      ),
    );
  }

  void _openFolderContextMenu(BuildContext context, Offset position) {
    final controller = context.read<PaneController>();
    final appState = context.read<AppState>();
    controller.clearSelection();

    final canWrite = !FileService.isSpecialPath(controller.currentPath);
    showCommandMenu(
      context,
      position: position,
      items: buildFolderContextMenuItems(
        sortColumn: controller.sortColumn,
        sortAscending: controller.sortAscending,
        viewMode: controller.viewMode,
        groupBy: controller.groupBy,
        groupAscending: controller.groupAscending,
        canWrite: canWrite,
        canPaste: canWrite && appState.hasClipboard,
        canSelectAll: controller.visibleEntries.isNotEmpty,
        onSortColumn: controller.setSortColumn,
        onSortAscending: controller.setSortAscending,
        onViewMode: controller.setViewMode,
        onGroupBy: controller.setGroupBy,
        onGroupAscending: controller.setGroupAscending,
        onRefresh: controller.refresh,
        onCreateFolder: () => _createFolder(context),
        onCreateFile: () => _createFile(context),
        onCreateShortcut: () => _createShortcutFromDialog(context),
        shellNewEntries: _shellNewEntries(context),
        onCreateFromTemplate: (entry) => _createFromTemplate(context, entry),
        onPaste: () => _paste(context),
        onSelectAll: controller.selectAll,
        onOpenInTerminal: canWrite
            ? () => _openTerminal(context, controller.currentPath)
            : null,
        onShowMoreOptions: () => _showNativeMenu(context, const [], position),
      ),
    );
  }

  Future<void> _openQuickView(BuildContext context, String path) async {
    final result = await context.read<QuickViewService>().open(path);
    if (!context.mounted || result.started) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openWith(BuildContext context, String path) async {
    try {
      await FileService.openWithDialog(path);
    } catch (e) {
      if (context.mounted) _showOperationError(context, '打开方式失败', e);
    }
  }

  _OpenWithMenu? _buildOpenWithMenu(String path, int iconSize) {
    try {
      final data = OpenWithMenuService.getData(path, iconSize: iconSize);
      final items = data.entries.isEmpty
          ? null
          : <CommandMenuItem>[
              for (final entry in data.entries)
                if (entry.isDivider)
                  const CommandMenuItem.divider()
                else
                  CommandMenuItem(
                    image: entry.iconPng == null
                        ? null
                        : MemoryImage(entry.iconPng!),
                    label: entry.label,
                    enabled: entry.enabled,
                    onAction: () => OpenWithMenuService.invoke(entry.commandId),
                  ),
              const CommandMenuItem.divider(),
              CommandMenuItem(
                icon: Icons.add_circle_outline,
                label: '选择其他应用',
                onAction: () => FileService.openWithDialog(path),
              ),
            ];
      return _OpenWithMenu(
        defaultAppImage: data.defaultAppIconPng == null
            ? null
            : MemoryImage(data.defaultAppIconPng!),
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInNewPane(
    BuildContext context,
    SplitDirection direction,
    String path,
  ) async {
    final newController = context.read<LayoutState>().splitPane(
      paneNode,
      direction,
    );
    if (newController != null) await newController.navigateTo(path);
  }

  Future<void> _pasteShortcut(BuildContext context) async {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    try {
      for (final path in appState.clipboardPaths) {
        await FileService.createShortcutIn(path, controller.currentPath);
      }
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '粘贴快捷方式失败', e);
    }
  }

  Future<void> _createFolderWithSelection(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    try {
      await FileService.createFolderWithSelection(
        paths,
        controller.currentPath,
      );
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件夹失败', e);
    }
  }

  Future<void> _createShortcuts(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    try {
      for (final path in paths) {
        await FileService.createShortcutIn(path, controller.currentPath);
      }
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建快捷方式失败', e);
    }
  }

  Future<void> _compressZip(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    final first = _findEntry(controller, paths.first);
    final base = (first != null && !first.isDirectory)
        ? p.basenameWithoutExtension(paths.first)
        : p.basename(paths.first);
    final zipPath = p.join(controller.currentPath, '$base.zip');
    try {
      await FileService.compressToZip(paths, zipPath);
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '压缩失败', e);
    }
  }

  Future<void> _openTerminal(BuildContext context, String dirPath) async {
    try {
      await FileService.openTerminal(dirPath);
    } catch (e) {
      if (context.mounted) _showOperationError(context, '打开终端失败', e);
    }
  }

  void _showPropertiesVerb(BuildContext context, List<String> paths) {
    final controller = context.read<PaneController>();
    ShellOperations.invokeVerb(
      folderPath: controller.currentPath,
      selectedPaths: paths,
      verb: 'properties',
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

  void _copySelectedPaths(BuildContext context) {
    final paths = context.read<PaneController>().selectedPaths;
    if (paths.isEmpty) return;
    Clipboard.setData(
      ClipboardData(text: paths.map((path) => '"$path"').join('\n')),
    );
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

class _OpenWithMenu {
  final ImageProvider<Object>? defaultAppImage;
  final List<CommandMenuItem>? items;

  const _OpenWithMenu({this.defaultAppImage, this.items});
}

// ── Sections：按需重建，避免选中/加载时整个面板 rebuild ──────────────

class _PaneTabBarSection extends StatelessWidget {
  final String paneId;

  const _PaneTabBarSection({required this.paneId});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maximized = context.watch<LayoutState>().maximizedPaneId == paneId;
    return Row(
      children: [
        Expanded(
          child: Selector<PaneController, (List<TabInfo>, int)>(
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
          ),
        ),
        Tooltip(
          message: maximized ? '还原面板' : '最大化面板',
          child: InkWell(
            onTap: () => context.read<LayoutState>().toggleMaximize(paneId),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                maximized ? Icons.fullscreen_exit : Icons.fullscreen,
                size: AppMetrics.iconMd,
                color: maximized ? c.accent : c.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _PaneLocationSection extends StatelessWidget {
  const _PaneLocationSection();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.addressBarHeight,
      child: Row(
        children: [
          const _NavToolbarSection(),
          const SizedBox(width: 4),
          const Expanded(child: _AddressBarSection()),
        ],
      ),
    );
  }
}

class _NavToolbarSection extends StatelessWidget {
  const _NavToolbarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (bool, bool, bool)>(
      selector: (_, c) => (c.canGoBack, c.canGoForward, c.canGoUp),
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return NavToolbar(
          canGoBack: sel.$1,
          canGoForward: sel.$2,
          canGoUp: sel.$3,
          onBack: controller.goBack,
          onForward: controller.goForward,
          onUp: controller.goUp,
          onRefresh: controller.refresh,
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
  final void Function(String path, Offset position) onItemContextMenu;
  final ValueChanged<Offset> onFolderContextMenu;

  const _FileListSection({
    required this.isActive,
    required this.onItemContextMenu,
    required this.onFolderContextMenu,
  });

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
            groupBy: controller.groupBy,
            groupAscending: controller.groupAscending,
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
            onItemRightClick: onItemContextMenu,
            onEmptyRightClick: onFolderContextMenu,
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
    return Selector<
      PaneController,
      (int, int, bool, int, String, QueryFilterMode, bool, EntryFilter)
    >(
      selector: (_, c) => (
        c.entryCount,
        c.entries.length,
        c.isLoading,
        c.selectedCount,
        c.filterQuery,
        c.filterMode,
        c.caseSensitive,
        c.entryFilter,
      ),
      builder: (context, sel, _) => _StatusBar(
        visibleCount: sel.$1,
        totalCount: sel.$2,
        isLoading: sel.$3,
        selectedCount: sel.$4,
        filterQuery: sel.$5,
        filterMode: sel.$6,
        caseSensitive: sel.$7,
        entryFilter: sel.$8,
        onFilterChanged: context.read<PaneController>().setFilterQuery,
        onModeSelected: (mode, caseSensitive) => context
            .read<PaneController>()
            .setFilterMode(mode, caseSensitive: caseSensitive),
        onEntryFilterSelected: context.read<PaneController>().setEntryFilter,
      ),
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
  final int visibleCount;
  final int totalCount;
  final bool isLoading;
  final int selectedCount;
  final String filterQuery;
  final QueryFilterMode filterMode;
  final bool caseSensitive;
  final EntryFilter entryFilter;
  final ValueChanged<String> onFilterChanged;
  final void Function(QueryFilterMode mode, bool caseSensitive) onModeSelected;
  final ValueChanged<EntryFilter> onEntryFilterSelected;

  const _StatusBar({
    required this.visibleCount,
    required this.totalCount,
    required this.isLoading,
    required this.selectedCount,
    required this.filterQuery,
    required this.filterMode,
    required this.caseSensitive,
    required this.entryFilter,
    required this.onFilterChanged,
    required this.onModeSelected,
    required this.onEntryFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasFilter =
        filterQuery.trim().isNotEmpty || entryFilter != EntryFilter.all;
    String text;
    if (isLoading) {
      text = '正在加载...';
    } else if (hasFilter) {
      text = '$visibleCount / $totalCount 个对象';
    } else {
      text = '$visibleCount 个对象';
    }
    if (selectedCount > 0) {
      text = '已选择 $selectedCount 个对象  |  $text';
    }
    return Container(
      height: AppMetrics.statusBarHeight,
      decoration: BoxDecoration(color: c.surfaceSubtle),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppMetrics.fontSmall,
                color: c.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 168,
            child: _StatusFilterField(
              query: filterQuery,
              filterMode: filterMode,
              caseSensitive: caseSensitive,
              entryFilter: entryFilter,
              onChanged: onFilterChanged,
              onModeSelected: onModeSelected,
              onEntryFilterSelected: onEntryFilterSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态栏右侧的过滤输入框：右侧图标打开匹配模式和类型菜单。
class _StatusFilterField extends StatefulWidget {
  final String query;
  final QueryFilterMode filterMode;
  final bool caseSensitive;
  final EntryFilter entryFilter;
  final ValueChanged<String> onChanged;
  final void Function(QueryFilterMode mode, bool caseSensitive) onModeSelected;
  final ValueChanged<EntryFilter> onEntryFilterSelected;

  const _StatusFilterField({
    required this.query,
    required this.filterMode,
    required this.caseSensitive,
    required this.entryFilter,
    required this.onChanged,
    required this.onModeSelected,
    required this.onEntryFilterSelected,
  });

  @override
  State<_StatusFilterField> createState() => _StatusFilterFieldState();
}

class _StatusFilterFieldState extends State<_StatusFilterField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _StatusFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _textController.text != widget.query) {
      _textController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _modeTooltip => switch (widget.filterMode) {
    QueryFilterMode.keyword =>
      widget.caseSensitive ? '关键字匹配（大小写敏感）' : '关键字匹配（忽略大小写）',
    QueryFilterMode.glob => 'glob 通配匹配（* 任意串，? 单字符，整名）',
    QueryFilterMode.regex => '正则匹配（大小写由设置决定）',
  };

  IconData get _modeIcon => switch ((widget.filterMode, widget.caseSensitive)) {
    (QueryFilterMode.keyword, false) => Symbols.match_case_off,
    (QueryFilterMode.keyword, true) => Symbols.match_case,
    (QueryFilterMode.glob, _) => Symbols.g_mobiledata_badge,
    (QueryFilterMode.regex, _) => Symbols.regular_expression,
  };

  bool _isActive(QueryFilterMode mode, bool caseSensitive) {
    if (widget.filterMode != mode) return false;
    if (mode == QueryFilterMode.keyword) {
      return widget.caseSensitive == caseSensitive;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasQuery = widget.query.trim().isNotEmpty;
    final hasFilter = hasQuery || widget.entryFilter != EntryFilter.all;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: '过滤当前文件夹',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          height: 20,
          padding: const EdgeInsets.only(left: 6, right: 2),
          decoration: BoxDecoration(
            color: _hovering || _focusNode.hasFocus
                ? c.surfaceHover
                : c.surface,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            border: Border.all(
              width: 1,
              color: _focusNode.hasFocus
                  ? c.accent
                  : _hovering
                  ? c.borderStrong
                  : c.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (_) => setState(() {}),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (hasQuery) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: '清除过滤',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppMetrics.controlRadius,
                    ),
                    onTap: () {
                      _textController.clear();
                      widget.onChanged('');
                      _focusNode.requestFocus();
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Tooltip(
                message: '$_modeTooltip，点击选择',
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
                  onTap: _openModeMenu,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Icon(
                        _modeIcon,
                        size: AppMetrics.iconSm,
                        color: hasFilter ? c.accent : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openModeMenu() {
    final box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset(box.size.width, box.size.height));
    showCommandMenu(
      context,
      position: position,
      items: [
        CommandMenuItem(
          icon: Symbols.match_case_off,
          label: '关键字（忽略大小写）',
          checked: _isActive(QueryFilterMode.keyword, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.keyword, false),
        ),
        CommandMenuItem(
          icon: Symbols.match_case,
          label: '关键字（大小写敏感）',
          checked: _isActive(QueryFilterMode.keyword, true),
          onAction: () => widget.onModeSelected(QueryFilterMode.keyword, true),
        ),
        const CommandMenuItem.divider(),
        CommandMenuItem(
          icon: Symbols.g_mobiledata_badge,
          label: 'glob（* ? 通配）',
          checked: _isActive(QueryFilterMode.glob, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.glob, false),
        ),
        CommandMenuItem(
          icon: Symbols.regular_expression,
          label: '正则表达式',
          checked: _isActive(QueryFilterMode.regex, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.regex, false),
        ),
        const CommandMenuItem.divider(),
        buildEntryFilterCommandMenuItem(
          selected: widget.entryFilter,
          onSelected: widget.onEntryFilterSelected,
        ),
      ],
    );
  }
}
