import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/widgets/app_menu.dart';

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
  });
}
