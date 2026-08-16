import 'package:flutter/material.dart';

import '../models/layout_node.dart';
import '../services/file_service.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/pane_controller.dart';
import 'command_menu.dart';

class AppMenuGroup {
  final String label;
  final List<CommandMenuItem> items;

  const AppMenuGroup(this.label, this.items);
}

List<AppMenuGroup> buildAppMenuGroups({
  required LayoutState layoutState,
  required AppState appState,
  required PaneController? activePane,
  required bool isFavorite,
  required VoidCallback onExit,
  required VoidCallback onViewerAssociations,
  required VoidCallback onAddFavorite,
  required VoidCallback onRemoveFavorite,
  required VoidCallback onManageFavorites,
  required VoidCallback onAbout,
  required VoidCallback onClearThumbnailCache,
  required bool canUndo,
  required bool canRedo,
  required bool canRestoreClosedTab,
  VoidCallback? onRestoreClosedTab,
  VoidCallback? onUndo,
  VoidCallback? onRedo,
  VoidCallback? onCopy,
  VoidCallback? onCut,
  VoidCallback? onPaste,
}) {
  final pane = activePane;
  final hasPane = pane != null;
  final canModify =
      hasPane &&
      pane.selectedPaths.isNotEmpty &&
      !FileService.isSpecialPath(pane.currentPath) &&
      !FileService.isRecycleBinPath(pane.currentPath);
  final canPaste =
      hasPane &&
      appState.hasClipboard &&
      !FileService.isSpecialPath(pane.currentPath);
  final canSelect = hasPane && pane.visibleEntries.isNotEmpty;
  final canFavorite = hasPane && !FileService.isSpecialPath(pane.currentPath);
  final canClosePane = layoutState.allPaneNodes.length > 1;
  final canCloseTab = hasPane && pane.tabs.length > 1;

  return [
    AppMenuGroup('文件(F)', [
      CommandMenuItem(
        label: '新建标签页',
        shortcut: 'Ctrl+T',
        enabled: hasPane,
        onAction: hasPane ? pane.addTab : null,
      ),
      CommandMenuItem(
        label: '关闭标签页',
        shortcut: 'Ctrl+W',
        enabled: canCloseTab,
        onAction: canCloseTab ? () => pane.closeTab(pane.activeTabIndex) : null,
      ),
      CommandMenuItem(
        label: '复制标签页',
        enabled: hasPane,
        onAction: hasPane ? pane.duplicateTab : null,
      ),
      CommandMenuItem(
        label: '恢复最近关闭的标签页',
        shortcut: 'Ctrl+Shift+T',
        enabled: canRestoreClosedTab && onRestoreClosedTab != null,
        onAction: canRestoreClosedTab ? onRestoreClosedTab : null,
      ),
      CommandMenuItem(
        label: '关闭面板',
        enabled: canClosePane,
        onAction: canClosePane
            ? () => layoutState.closePane(layoutState.focusedNode)
            : null,
      ),
      CommandMenuItem(label: '退出', onAction: onExit),
    ]),
    AppMenuGroup('编辑(E)', [
      CommandMenuItem(
        label: '撤销',
        shortcut: 'Ctrl+Z',
        enabled: canUndo && onUndo != null,
        onAction: canUndo ? onUndo : null,
      ),
      CommandMenuItem(
        label: '重做',
        shortcut: 'Ctrl+Y',
        enabled: canRedo && onRedo != null,
        onAction: canRedo ? onRedo : null,
      ),
      CommandMenuItem(
        label: '剪切',
        shortcut: 'Ctrl+X',
        enabled: canModify && onCut != null,
        onAction: canModify ? onCut : null,
      ),
      CommandMenuItem(
        label: '复制',
        shortcut: 'Ctrl+C',
        enabled: canModify && onCopy != null,
        onAction: canModify ? onCopy : null,
      ),
      CommandMenuItem(
        label: '粘贴',
        shortcut: 'Ctrl+V',
        enabled: canPaste && onPaste != null,
        onAction: canPaste ? onPaste : null,
      ),
      CommandMenuItem(
        label: '全选',
        shortcut: 'Ctrl+A',
        enabled: canSelect,
        onAction: canSelect ? pane.selectAll : null,
      ),
      CommandMenuItem(
        label: '反选',
        enabled: canSelect,
        onAction: canSelect ? pane.invertSelection : null,
      ),
    ]),
    AppMenuGroup('收藏夹(A)', [
      CommandMenuItem(
        label: isFavorite ? '从收藏夹移除' : '添加到收藏夹',
        enabled: canFavorite,
        onAction: canFavorite
            ? (isFavorite ? onRemoveFavorite : onAddFavorite)
            : null,
      ),
      CommandMenuItem(label: '管理收藏夹', onAction: onManageFavorites),
    ]),
    AppMenuGroup('信息(I)', [
      CommandMenuItem(label: '关于 Inf-Dir', onAction: onAbout),
    ]),
    AppMenuGroup('视图(V)', [
      CommandMenuItem(
        label: '关闭面板',
        enabled: canClosePane,
        onAction: canClosePane
            ? () => layoutState.closePane(layoutState.focusedNode)
            : null,
      ),
      CommandMenuItem(
        label: '水平切分',
        enabled: hasPane,
        onAction: hasPane
            ? () => layoutState.splitPane(
                layoutState.focusedNode,
                SplitDirection.vertical,
              )
            : null,
      ),
      CommandMenuItem(
        label: '垂直切分',
        enabled: hasPane,
        onAction: hasPane
            ? () => layoutState.splitPane(
                layoutState.focusedNode,
                SplitDirection.horizontal,
              )
            : null,
      ),
    ]),
    AppMenuGroup('选项(O)', [
      CommandMenuItem(
        label: '显示缩略图',
        checked: appState.showThumbnails,
        onAction: () => appState.setShowThumbnails(!appState.showThumbnails),
      ),
      CommandMenuItem(label: '清除缩略图缓存', onAction: onClearThumbnailCache),
      CommandMenuItem(label: '查看器管理', onAction: onViewerAssociations),
    ]),
  ];
}
