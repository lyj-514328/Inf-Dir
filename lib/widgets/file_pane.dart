import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/file_entry.dart';
import '../state/app_state.dart';
import '../state/pane_controller.dart';
import '../services/file_service.dart';
import 'file_list_view.dart';
import 'address_bar.dart';
import 'nav_toolbar.dart';
import 'pane_tab_bar.dart';

enum _CtxAction {
  open,
  openInNewTab,
  copyPath,
  cut,
  copy,
  paste,
  delete,
  rename,
  newFolder,
  refresh,
  selectAll,
}

class FilePane extends StatelessWidget {
  final int paneIndex;

  const FilePane({super.key, required this.paneIndex});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final controller = appState.panes[paneIndex];
    final isActive = appState.activePaneIndex == paneIndex;

    return GestureDetector(
      onTap: () => appState.setActivePane(paneIndex),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? const Color(0xFF0078D4) : const Color(0xFFC0C0C0),
            width: isActive ? 2 : 1,
          ),
        ),
        child: ChangeNotifierProvider<PaneController>.value(
          value: controller,
          child: _PaneContent(paneIndex: paneIndex),
        ),
      ),
    );
  }
}

class _PaneContent extends StatelessWidget {
  final int paneIndex;

  const _PaneContent({required this.paneIndex});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PaneController>();

    return Focus(
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
            _deleteSelected(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f2) {
            _renameSelected(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyC &&
              HardwareKeyboard.instance.isControlPressed) {
            _copySelected(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyX &&
              HardwareKeyboard.instance.isControlPressed) {
            _cutSelected(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyV &&
              HardwareKeyboard.instance.isControlPressed) {
            _paste(context);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
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
              currentPath: controller.currentPath,
              onSubmit: (path) => controller.navigateTo(path),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: FileListView(
              entries: controller.entries,
              selectedPaths: controller.selectedPaths,
              loading: controller.isLoading,
              onSingleTap: (path) => controller.toggleSelection(path),
              onDoubleTap: (path) => _handleDoubleTap(context, controller, path),
              onItemRightClick: (path, pos) =>
                  _showItemContextMenu(context, path, pos),
              onEmptyRightClick: (pos) =>
                  _showEmptyContextMenu(context, pos),
            ),
          ),
          _StatusBar(
            total: controller.entryCount,
            selected: controller.selectedCount,
          ),
        ],
      ),
    );
  }

  // ── Navigation / Open ──────────────────────────────────────────────

  void _handleDoubleTap(
      BuildContext context, PaneController controller, String path) {
    final entry = _findEntry(controller, path);
    if (entry == null) return;
    if (entry.isDirectory) {
      controller.navigateTo(path);
    } else {
      FileService.openFile(path);
    }
  }

  void _openSelected(BuildContext context, PaneController controller) {
    if (controller.selectedPaths.isEmpty) return;
    _handleDoubleTap(context, controller, controller.selectedPaths.first);
  }

  FileEntry? _findEntry(PaneController controller, String path) {
    for (final e in controller.entries) {
      if (e.path == path) return e;
    }
    return null;
  }

  // ── Context Menus ──────────────────────────────────────────────────

  Future<void> _showItemContextMenu(
      BuildContext context, String path, Offset position) async {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();

    if (!controller.selectedPaths.contains(path)) {
      controller.clearSelection();
      controller.toggleSelection(path);
    }

    final action = await _showMenu(context, position, [
      _MenuItem(_CtxAction.open, Icons.open_in_new, '打开'),
      _MenuItem(_CtxAction.openInNewTab, Icons.tab, '在新标签页中打开'),
      null,
      _MenuItem(_CtxAction.copyPath, Icons.link, '复制路径'),
      _MenuItem(_CtxAction.cut, Icons.content_cut, '剪切  (Ctrl+X)'),
      _MenuItem(_CtxAction.copy, Icons.content_copy, '复制  (Ctrl+C)'),
      if (appState.hasClipboard)
        _MenuItem(_CtxAction.paste, Icons.content_paste, '粘贴  (Ctrl+V)'),
      null,
      _MenuItem(_CtxAction.delete, Icons.delete_outline, '删除  (Del)'),
      _MenuItem(_CtxAction.rename, Icons.edit, '重命名  (F2)'),
      null,
      _MenuItem(_CtxAction.refresh, Icons.refresh, '刷新  (F5)'),
      _MenuItem(_CtxAction.selectAll, Icons.select_all, '全选  (Ctrl+A)'),
    ]);

    if (action != null) {
      if (!context.mounted) return;
      _executeAction(context, action);
    }
  }

  Future<void> _showEmptyContextMenu(
      BuildContext context, Offset position) async {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    controller.clearSelection();

    final action = await _showMenu(context, position, [
      if (appState.hasClipboard)
        _MenuItem(_CtxAction.paste, Icons.content_paste, '粘贴  (Ctrl+V)'),
      _MenuItem(_CtxAction.newFolder, Icons.create_new_folder_outlined, '新建文件夹'),
      null,
      _MenuItem(_CtxAction.refresh, Icons.refresh, '刷新  (F5)'),
      _MenuItem(_CtxAction.selectAll, Icons.select_all, '全选  (Ctrl+A)'),
    ]);

    if (action != null) {
      if (!context.mounted) return;
      _executeAction(context, action);
    }
  }

  Future<_CtxAction?> _showMenu(
      BuildContext context, Offset position, List<_MenuItem?> items) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = overlay.size;
    final rect = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      size.width - position.dx,
      size.height - position.dy,
    );

    return showMenu<_CtxAction>(
      context: context,
      position: rect,
      constraints: const BoxConstraints(minWidth: 180),
      items: items.map<PopupMenuEntry<_CtxAction>>((item) {
        if (item == null) {
          return const PopupMenuDivider(height: 4);
        }
        return PopupMenuItem<_CtxAction>(
          value: item.action,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(item.icon, size: 16, color: const Color(0xFF555555)),
              const SizedBox(width: 8),
              Text(item.label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Action Execution ───────────────────────────────────────────────

  void _executeAction(BuildContext context, _CtxAction action) {
    final controller = context.read<PaneController>();
    final selected = controller.selectedPaths.toList();

    switch (action) {
      case _CtxAction.open:
        if (selected.isNotEmpty) {
          _handleDoubleTap(context, controller, selected.first);
        }
      case _CtxAction.openInNewTab:
        if (selected.isNotEmpty) {
          final entry = _findEntry(controller, selected.first);
          if (entry != null && entry.isDirectory) {
            controller.addTab(selected.first);
          }
        }
      case _CtxAction.copyPath:
        if (selected.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: selected.join('\n')));
        }
      case _CtxAction.cut:
        _cutSelected(context);
      case _CtxAction.copy:
        _copySelected(context);
      case _CtxAction.paste:
        _paste(context);
      case _CtxAction.delete:
        _deleteSelected(context);
      case _CtxAction.rename:
        _renameSelected(context);
      case _CtxAction.newFolder:
        _showNewFolderDialog(context);
      case _CtxAction.refresh:
        controller.refresh();
      case _CtxAction.selectAll:
        controller.selectAll();
    }
  }

  // ── Clipboard Operations ───────────────────────────────────────────

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

  // ── Delete ────────────────────────────────────────────────────────

  Future<void> _deleteSelected(BuildContext context) async {
    final controller = context.read<PaneController>();
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

  // ── Rename ─────────────────────────────────────────────────────────

  Future<void> _renameSelected(BuildContext context) async {
    final controller = context.read<PaneController>();
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
          SnackBar(content: Text('重命名失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  // ── New Folder ─────────────────────────────────────────────────────

  Future<void> _showNewFolderDialog(BuildContext context) async {
    final controller = context.read<PaneController>();

    final name = await _showInputDialog(
      context,
      title: '新建文件夹',
      initialValue: '新建文件夹',
      confirmText: '创建',
    );

    if (name == null || name.isEmpty) return;

    try {
      await FileService.createFolder(controller.currentPath, name);
      controller.refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String _basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
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

class _MenuItem {
  final _CtxAction action;
  final IconData icon;
  final String label;
  const _MenuItem(this.action, this.icon, this.label);
}

class _StatusBar extends StatelessWidget {
  final int total;
  final int selected;

  const _StatusBar({required this.total, required this.selected});

  @override
  Widget build(BuildContext context) {
    String text = '$total 个对象';
    if (selected > 0) {
      text = '已选择 $selected 个对象  |  $text';
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
