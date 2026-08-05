import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/layout_state.dart';

void main() {
  test('活动位置只随当前 Pane 的路径或焦点变化', () {
    final repo = DirectoryRepository(
      cursorFactory: (_, {directoriesOnly = false}) => null,
      hasChildrenProbe: (_) => false,
    );
    final layout = LayoutState(repository: repo);
    final initial = layout.activePaneLocation.value!;
    final events = <ActivePaneLocation?>[];
    layout.activePaneLocation.addListener(
      () => events.add(layout.activePaneLocation.value),
    );

    final first = layout.focusedNode;
    layout.navigateActivePane('C:\\A');
    expect(layout.activePaneLocation.value, isNot(initial));
    expect(layout.activePaneLocation.value!.paneId, initial.paneId);
    expect(layout.activePaneLocation.value!.path, 'C:\\A');

    final second = layout.allPaneNodes.firstWhere(
      (node) => node.id != first.id,
    );
    layout.focusNode(second);
    expect(layout.activePaneLocation.value!.paneId, second.paneId);
    expect(
      layout.activePaneLocation.value!.path,
      layout.controllerFor(second)!.currentPath,
    );
    expect(events.length, 2);

    layout.dispose();
  });
}
