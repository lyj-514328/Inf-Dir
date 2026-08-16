import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/widgets/app_menu.dart';
import 'package:inf_dir/widgets/command_menu.dart';
import 'package:inf_dir/widgets/tab_context_menu.dart';

void main() {
  test('top-level menus expose only implemented commands', () {
    final repository = DirectoryRepository(
      cursorFactory: (_, {bool directoriesOnly = false}) async => null,
      hasChildrenProbe: (_) => false,
    );
    final layoutState = LayoutState(repository: repository);
    final appState = AppState(repository: repository);
    addTearDown(layoutState.dispose);
    addTearDown(appState.dispose);

    final groups = buildAppMenuGroups(
      layoutState: layoutState,
      appState: appState,
      activePane: layoutState.controllerFor(layoutState.focusedNode),
      isFavorite: false,
      canUndo: false,
      canRedo: false,
      canRestoreClosedTab: layoutState.canRestoreClosedTab,
      onRestoreClosedTab: layoutState.restoreClosedTab,
      onUndo: () {},
      onRedo: () {},
      onExit: () {},
      onViewerAssociations: () {},
      onAddFavorite: () {},
      onRemoveFavorite: () {},
      onManageFavorites: () {},
      onAbout: () {},
      onClearThumbnailCache: () {},
      onCopy: () {},
      onCut: () {},
      onPaste: () {},
    );

    expect(groups.map((group) => group.label), [
      '文件(F)',
      '编辑(E)',
      '收藏夹(A)',
      '信息(I)',
      '视图(V)',
      '选项(O)',
    ]);
    expect(groups[0].items.map((item) => item.label), [
      '新建标签页',
      '关闭标签页',
      '复制标签页',
      '恢复最近关闭的标签页',
      '关闭面板',
      '退出',
    ]);
    expect(groups[1].items.map((item) => item.label), [
      '撤销',
      '重做',
      '剪切',
      '复制',
      '粘贴',
      '全选',
      '反选',
    ]);
    expect(groups[0].items[0].enabled, isTrue);
    expect(groups[0].items[1].enabled, isFalse);
    expect(groups[0].items[2].enabled, isTrue);
    expect(groups[0].items[3].enabled, isFalse);
    expect(groups[1].items[0].enabled, isFalse);
    expect(groups[1].items[1].enabled, isFalse);
    expect(groups[1].items[2].enabled, isFalse);
    expect(groups[1].items[4].enabled, isFalse);
    expect(groups[2].items[0].enabled, isTrue);
    expect(groups[4].items[0].enabled, isTrue);
    expect(groups[5].items.map((item) => item.label), [
      '显示缩略图',
      '清除缩略图缓存',
      '查看器管理',
    ]);
    expect(groups[5].items[0].checked, isTrue);

    // 关闭一个标签后，「恢复最近关闭的标签页」变为可用。
    final pane = layoutState.controllerFor(layoutState.focusedNode)!;
    pane.addTab();
    pane.closeTab(0);
    final refreshed = buildAppMenuGroups(
      layoutState: layoutState,
      appState: appState,
      activePane: layoutState.controllerFor(layoutState.focusedNode),
      isFavorite: false,
      canUndo: false,
      canRedo: false,
      canRestoreClosedTab: layoutState.canRestoreClosedTab,
      onRestoreClosedTab: layoutState.restoreClosedTab,
      onUndo: () {},
      onRedo: () {},
      onExit: () {},
      onViewerAssociations: () {},
      onAddFavorite: () {},
      onRemoveFavorite: () {},
      onManageFavorites: () {},
      onAbout: () {},
      onClearThumbnailCache: () {},
      onCopy: () {},
      onCut: () {},
      onPaste: () {},
    );
    expect(refreshed[0].items[3].enabled, isTrue);
  });

  test('tab context menu respects close and restore availability', () {
    List<CommandMenuItem> visible(List<CommandMenuItem> items) =>
        items.where((item) => !item.isDivider).toList();

    final items = visible(
      buildTabContextMenuItems(
        onNewTab: () {},
        onDuplicateTab: () {},
        canClose: false,
        onCloseTab: () {},
        onCloseOtherTabs: () {},
        onCloseTabsToTheLeft: () {},
        onCloseTabsToTheRight: () {},
        onCloseAllTabs: () {},
        canRestoreClosedTab: false,
        onRestoreClosedTab: () {},
      ),
    );
    expect(items.map((item) => item.label), [
      '新建标签页',
      '复制标签页',
      '关闭',
      '关闭其他标签页',
      '关闭左侧标签页',
      '关闭右侧标签页',
      '关闭全部标签页',
      '恢复最近关闭的标签页',
    ]);
    expect(items[2].enabled, isFalse);
    expect(items[6].enabled, isFalse);
    expect(items[7].enabled, isFalse);

    final enabledItems = visible(
      buildTabContextMenuItems(
        onNewTab: () {},
        onDuplicateTab: () {},
        canClose: true,
        onCloseTab: () {},
        onCloseOtherTabs: () {},
        onCloseTabsToTheLeft: () {},
        onCloseTabsToTheRight: () {},
        onCloseAllTabs: () {},
        canRestoreClosedTab: true,
        onRestoreClosedTab: () {},
      ),
    );
    expect(enabledItems[2].enabled, isTrue);
    expect(enabledItems[7].enabled, isTrue);
  });
}
