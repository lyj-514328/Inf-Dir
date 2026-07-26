import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/pane_controller.dart';
import '../services/file_service.dart';
import '../services/shell_context_menu.dart';
import 'file_list_view.dart';
import 'address_bar.dart';
import 'nav_toolbar.dart';
import 'pane_tab_bar.dart';

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
    final controller = context.watch<PaneController>();
    final layoutState = context.watch<LayoutState>();
    final isActive = layoutState.focusedNodeId == paneNode.id;

    final result = Column(
      children: [
        PaneTabBar(
          tabs: controller.tabs,
          activeIndex: controller.activeTabIndex,
          onSwitchTab: controller.switchTab,
          onCloseTab: controller.closeTab,
          onAddTab: () => controller.addTab(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: NavToolbar(
            canGoBack: controller.canGoBack,
            canGoForward: controller.canGoForward,
            canGoUp: controller.canGoUp,
            onBack: controller.goBack,
            onForward: controller.goForward,
            onUp: controller.goUp,
            onHome: controller.goHome,
            onRefresh: controller.refresh,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AddressBar(
            currentPath: controller.displayPath,
            iconPath: controller.currentPath,
            onSubmit: (path) => controller.navigateTo(path),
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Focus(
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
                  if (!FileService.isRecycleBinPath(controller.currentPath)) {
                    _deleteSelected(context);
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.f2) {
                  if (!FileService.isRecycleBinPath(controller.currentPath)) {
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
                  if (FileService.isRecycleBinPath(controller.currentPath)) {
                    return KeyEventResult.handled;
                  }
                  _cutSelected(context);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.keyV &&
                    HardwareKeyboard.instance.isControlPressed) {
                  if (FileService.isRecycleBinPath(controller.currentPath)) {
                    return KeyEventResult.handled;
                  }
                  _paste(context);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: FileListView(
              entries: controller.entries,
              selectedPaths: controller.selectedPaths,
              isActive: isActive,
              loading: controller.isLoading,
              sortColumn: controller.sortColumn,
              sortAscending: controller.sortAscending,
              onSort: controller.sortBy,
              columnWidths: controller.columnWidths,
              onResizeColumn: controller.resizeColumn,
              onInitWidths: controller.initColumnWidths,
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
              onDoubleTap: (path) =>
                  _handleDoubleTap(context, controller, path),
              onItemRightClick: (path, pos) =>
                  _showNativeMenu(context, [path], pos),
              onEmptyRightClick: (pos) =>
                  _showNativeMenu(context, [], pos),
            ),
          ),
        ),
        _StatusBar(
          loaded: controller.entryCount,
          isLoading: controller.isLoading,
          selectedCount: controller.selectedCount,
        ),
      ],
    );

    sw.stop();
    if (sw.elapsedMilliseconds > 10) {
      debugPrint('[Perf] _PaneContent build: ${sw.elapsedMilliseconds}ms, entries=${controller.entries.length}');
    }
    return result;
  }

  // ── Helpers ────────────────────────────────────────────────────────

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

  // ── Open / Navigate ────────────────────────────────────────────────

  void _handleDoubleTap(
      BuildContext context, PaneController controller, String path) {
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

  void _openSelected(BuildContext context, PaneController controller) {
    // In the Recycle Bin, Enter does nothing
    if (FileService.isRecycleBinPath(controller.currentPath)) return;
    if (controller.selectedPaths.isEmpty) return;
    _handleDoubleTap(context, controller, controller.selectedPaths.first);
  }

  // ── Native Shell Context Menu ──────────────────────────────────────

  void _showNativeMenu(
      BuildContext context, List<String> selectedPaths, Offset position) {
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
    final paths = selectedPaths.isEmpty ? <String>[] : controller.selectedPaths.toList();

    // Convert logical (window-relative) → screen physical coordinates
    final dpr = View.of(context).devicePixelRatio;
    final (screenX, screenY) = ShellContextMenu.toScreenCoords(
      position.dx, position.dy, dpr,
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
      BuildContext context, String? verb, List<String> selectedPaths) {
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
        // Properties, shell extensions, etc. — just refresh
        controller.refresh();
    }
  }

  // ── Keyboard-triggered operations ──────────────────────────────────

  void _copySelected(BuildContext context) {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    if (controller.selectedPaths.isNotEmpty) {
      appState.copyPaths(controller.selectedPaths.toList());
      Clipboard.setData(
          ClipboardData(text: controller.selectedPaths.join('\n')));
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
    if (FileService.isRecycleBinPath(controller.currentPath)) return;

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
        title: const Text('确认删除', style: TextStyle(fontSize: 14)),
        content: Text(
          selected.length == 1
              ? '确定要删除 "${_basename(selected.first)}" 吗？'
              : '确定要删除 ${selected.length} 个项目吗？',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
              duration: const Duration(seconds: 2)),
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
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
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
      height: 20,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
      ),
    );
  }
}
