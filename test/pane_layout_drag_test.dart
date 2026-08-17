import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/layout_node.dart';
import 'package:inf_dir/models/pane_drag_payload.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:inf_dir/widgets/alt_overlay.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/layout_view.dart';
import 'package:provider/provider.dart';

DirectoryRepository _emptyRepository() => DirectoryRepository(
  cursorFactory: (path, {bool directoriesOnly = false}) async => null,
  yieldFrame: () async {},
  hasChildrenProbe: (_) => false,
);

LayoutNode _pane(LayoutTree tree, String paneId) {
  LayoutNode? find(LayoutNode node) {
    if (node.paneId == paneId) return node;
    for (final child in node.children) {
      final result = find(child);
      if (result != null) return result;
    }
    return null;
  }

  return find(tree.activeWorkspace)!;
}

void _expectValidTree(LayoutNode node) {
  if (node.children.isNotEmpty) {
    expect(
      node.children.fold<double>(0, (total, child) => total + child.percent),
      closeTo(1, 0.000001),
    );
  }
  for (final child in node.children) {
    expect(child.parent, same(node));
    _expectValidTree(child);
  }
}

List<String> _paneIds(LayoutNode node) {
  if (node.isPane) return [node.paneId!];
  return [for (final child in node.children) ..._paneIds(child)];
}

void main() {
  group('LayoutTree.movePaneBeside', () {
    for (final edge in PaneDropEdge.values) {
      test('moves a pane to the target ${edge.name} edge', () {
        final tree = createDefaultLayout(['A', 'B', 'C', 'D']);
        final source = _pane(tree, 'A');
        final target = _pane(tree, 'D');

        expect(tree.movePaneBeside(source, target, edge), isTrue);

        final split = target.parent!;
        final sourceFirst =
            edge == PaneDropEdge.left || edge == PaneDropEdge.top;
        expect(split.isSplit, isTrue);
        expect(
          split.layout,
          edge == PaneDropEdge.left || edge == PaneDropEdge.right
              ? SplitDirection.horizontal
              : SplitDirection.vertical,
        );
        expect(
          split.children,
          sourceFirst ? [source, target] : [target, source],
        );
        expect(split.percent, closeTo(0.5, 0.000001));
        expect(source.percent, closeTo(0.5, 0.000001));
        expect(target.percent, closeTo(0.5, 0.000001));

        // A 原来的二叉父节点只剩 B，必须自动折叠。
        expect(tree.activeWorkspace.children.first.paneId, 'B');
        _expectValidTree(tree.activeWorkspace);
      });
    }

    test('keeps an existing direct placement and ratio unchanged', () {
      final tree = createDefaultLayout(['A', 'B', 'C', 'D']);
      final source = _pane(tree, 'A');
      final target = _pane(tree, 'B');
      source.percent = 0.3;
      target.percent = 0.7;
      final parent = source.parent;

      expect(tree.movePaneBeside(source, target, PaneDropEdge.left), isFalse);
      expect(source.parent, same(parent));
      expect(source.percent, 0.3);
      expect(target.percent, 0.7);
    });

    test('reorders direct siblings without moving their divider', () {
      final tree = createDefaultLayout(['A', 'B', 'C', 'D']);
      final source = _pane(tree, 'A');
      final target = _pane(tree, 'B');
      source.percent = 0.3;
      target.percent = 0.7;
      final parent = source.parent!;

      expect(tree.movePaneBeside(source, target, PaneDropEdge.right), isTrue);
      expect(parent.children, [target, source]);
      expect(target.percent, 0.3);
      expect(source.percent, 0.7);
      _expectValidTree(tree.activeWorkspace);
    });

    test('preserves invariants for every default pane pair and edge', () {
      const paneIds = ['A', 'B', 'C', 'D'];
      for (final sourceId in paneIds) {
        for (final targetId in paneIds) {
          if (sourceId == targetId) continue;
          for (final edge in PaneDropEdge.values) {
            final tree = createDefaultLayout(paneIds);
            tree.movePaneBeside(
              _pane(tree, sourceId),
              _pane(tree, targetId),
              edge,
            );

            expect(_paneIds(tree.activeWorkspace).toSet(), paneIds.toSet());
            expect(_paneIds(tree.activeWorkspace), hasLength(paneIds.length));
            _expectValidTree(tree.activeWorkspace);
          }
        }
      }
    });
  });

  test('LayoutState preserves the moved pane controller and focus', () {
    final layout = LayoutState(repository: _emptyRepository());
    addTearDown(layout.dispose);
    final source = layout.allPaneNodes.first;
    final target = layout.allPaneNodes.last;
    final controller = layout.controllerFor(source)!;
    controller.addTab(r'C:\Kept');

    layout.beginPaneDrag(source);
    expect(layout.draggedPaneNodeId, source.id);
    expect(layout.movePaneBeside(source, target, PaneDropEdge.right), isTrue);

    expect(layout.controllerFor(source), same(controller));
    expect(controller.tabs.map((tab) => tab.path), contains(r'C:\Kept'));
    expect(layout.focusedNodeId, source.id);
    expect(layout.allPaneNodes, hasLength(4));

    layout.endPaneDrag();
    expect(layout.paneDragActive, isFalse);
  });

  test('pane drop position uses four aspect-correct directional regions', () {
    const size = Size(200, 100);
    expect(
      paneDropEdgeForPosition(const Offset(10, 50), size),
      PaneDropEdge.left,
    );
    expect(
      paneDropEdgeForPosition(const Offset(190, 50), size),
      PaneDropEdge.right,
    );
    expect(
      paneDropEdgeForPosition(const Offset(100, 5), size),
      PaneDropEdge.top,
    );
    expect(
      paneDropEdgeForPosition(const Offset(100, 95), size),
      PaneDropEdge.bottom,
    );
  });

  testWidgets('Alt overlay exposes a dedicated pane drag handle', (
    tester,
  ) async {
    final node = LayoutNode(id: 'pane-a', type: NodeType.pane, paneId: 'A');
    var dragStarted = 0;
    var dragEnded = 0;

    await tester.binding.setSurfaceSize(const Size(220, 140));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SizedBox.expand(
          child: AltOverlay(
            node: node,
            isSwapSelected: false,
            onClose: () {},
            onSplit: (_) {},
            onSwap: () {},
            dragLabel: r'C:\Alpha',
            isDragging: false,
            onDragStarted: () => dragStarted++,
            onDragEnded: () => dragEnded++,
          ),
        ),
      ),
    );

    final handle = find.byKey(const ValueKey('pane-drag-handle-pane-a'));
    expect(handle, findsOneWidget);
    expect(find.byType(Draggable<PaneDragPayload>), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(dragStarted, 1);

    await gesture.up();
    await tester.pump();
    expect(dragEnded, 1);
  });

  testWidgets('dragging a pane onto a target edge reparents it', (
    tester,
  ) async {
    final repository = _emptyRepository();
    final layout = LayoutState(repository: repository);
    final appState = AppState(repository: repository);
    addTearDown(layout.dispose);
    addTearDown(appState.dispose);

    final source = layout.allPaneNodes.first;
    final target = layout.allPaneNodes.last;
    layout.showAltOverlay();

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LayoutState>.value(value: layout),
          ChangeNotifierProvider<AppState>.value(value: appState),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LayoutView(
              node: layout.activeWorkspace,
              cloudZoneResolver: (_) => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = find.byKey(ValueKey('pane-drag-handle-${source.id}'));
    final targetDrop = find.byKey(ValueKey('pane-drop-target-${target.id}'));
    expect(handle, findsOneWidget);
    expect(targetDrop, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(layout.paneDragActive, isTrue);

    final targetRect = tester.getRect(targetDrop);
    await gesture.moveTo(Offset(targetRect.right - 20, targetRect.center.dy));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pane-drop-preview-right')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(source.parent, same(target.parent));
    expect(source.parent!.layout, SplitDirection.horizontal);
    expect(source.parent!.children, [target, source]);
    expect(layout.paneDragActive, isFalse);
    _expectValidTree(layout.activeWorkspace);
  });
}
