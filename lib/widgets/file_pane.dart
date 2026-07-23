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

  void _handleDoubleTap(
      BuildContext context, PaneController controller, String path) {
    FileEntry? entry;
    for (final e in controller.entries) {
      if (e.path == path) {
        entry = e;
        break;
      }
    }
    if (entry == null) return;

    if (entry.isDirectory) {
      controller.navigateTo(path);
    } else {
      FileService.openFile(path);
    }
  }

  void _openSelected(BuildContext context, PaneController controller) {
    if (controller.selectedPaths.isEmpty) return;
    final path = controller.selectedPaths.first;
    _handleDoubleTap(context, controller, path);
  }
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
