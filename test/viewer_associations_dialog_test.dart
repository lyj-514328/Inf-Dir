import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/plugin_manifest.dart';
import 'package:inf_dir/features/quick_view/quick_view_service.dart';
import 'package:inf_dir/features/quick_view/viewer_association_config.dart';
import 'package:inf_dir/features/quick_view/viewer_associations_dialog.dart';
import 'package:inf_dir/features/quick_view/viewer_rule.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late QuickViewService service;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_plugin_ui_');
    final pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
    _writePlugin(pluginRoot, 'viewer.a', 'A Viewer');
    _writePlugin(pluginRoot, 'viewer.b', 'B Viewer');
    service = QuickViewService(
      pluginRoots: [pluginRoot],
      associationStore: ViewerAssociationStore(
        filePath: p.join(temp.path, 'associations.json'),
      ),
      mimeTypeResolver: (_) => null,
    );
  });

  tearDown(() {
    service.dispose();
    temp.deleteSync(recursive: true);
  });

  testWidgets('shows four untyped default groups and their rule tree', (
    tester,
  ) async {
    await _openDialog(tester, service);

    expect(find.text('路径'), findsOneWidget);
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('扩展名'), findsOneWidget);
    expect(find.text('MIME'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-rule-groups-list')), findsOne);

    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsOneWidget);

    await tester.tap(find.text('.txt'));
    await tester.pumpAndSettle();
    expect(find.text('A Viewer'), findsOneWidget);
    expect(find.text('B Viewer'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reorders rule groups through the list callback', (tester) async {
    await _openDialog(tester, service);

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('viewer-rule-groups-list')),
    );
    list.onReorderItem!(0, 3);
    await tester.pump();

    expect(service.ruleGroups.map((group) => group.id), [
      ViewerAssociationConfig.builtInFileNameGroupId,
      ViewerAssociationConfig.builtInExtensionGroupId,
      ViewerAssociationConfig.builtInMimeTypeGroupId,
      ViewerAssociationConfig.builtInPathGroupId,
    ]);
    final saved =
        jsonDecode(
              File(p.join(temp.path, 'associations.json')).readAsStringSync(),
            )
            as Map;
    expect(
      ((saved['groups'] as List).first as Map)['id'],
      ViewerAssociationConfig.builtInFileNameGroupId,
    );
  });

  testWidgets('splitters preserve trailing rule and viewer editors', (
    tester,
  ) async {
    await _openDialog(tester, service);

    await tester.drag(
      find.byKey(const ValueKey('viewer-rule-groups-splitter')),
      const Offset(1000, 0),
    );
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('viewer-rule-groups-column')))
          .width,
      lessThanOrEqualTo(424),
    );

    await tester.drag(
      find.byKey(const ValueKey('viewer-rules-splitter')),
      const Offset(1000, 0),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('viewer-rules-column'))).width,
      lessThanOrEqualTo(272),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds an untyped custom rule group', (tester) async {
    await _openDialog(tester, service);

    await tester.tap(find.byTooltip('新建规则组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-group-name')),
      '项目规则',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(service.ruleGroups, hasLength(5));
    expect(service.ruleGroups.last.name, '项目规则');
    expect(service.ruleGroups.last.rules, isEmpty);
    expect(find.text('项目规则'), findsOneWidget);
  });

  testWidgets('allows mixed rules and nested child rules', (tester) async {
    await _openDialog(tester, service);
    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('.txt'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加子规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer-rule-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MIME').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-value')),
      'text/x-special',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final parent = service.rule(
      ViewerAssociationConfig.defaultRuleId(
        ViewerAssociationKind.extension,
        '.txt',
      ),
    );
    expect(parent.rules, hasLength(1));
    expect(parent.rules.single.type, ViewerRuleType.mimeType);
    expect(parent.rules.single.value, 'text/x-special');
    expect(find.text('text/x-special'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Draggable),
      findsWidgets,
    );
  });

  testWidgets('viewer checkboxes and drag order persist', (tester) async {
    await _openDialog(tester, service);
    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('.txt'));
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('viewer-candidates-list')),
    );
    list.onReorderItem!(0, 1);
    await tester.pump();
    expect(
      service
          .candidatesForAssociation(ViewerAssociationKind.extension, '.txt')
          .map((plugin) => plugin.manifest.id),
      ['viewer.b', 'viewer.a'],
    );

    await tester.tap(find.byKey(const ValueKey('viewer-enabled-viewer.b')));
    await tester.pump();
    expect(
      service
          .candidatesForAssociation(ViewerAssociationKind.extension, '.txt')
          .map((plugin) => plugin.manifest.id),
      ['viewer.a'],
    );
    expect(File(p.join(temp.path, 'associations.json')).existsSync(), isTrue);
  });

  testWidgets('path rules use the same recursive rule editor', (tester) async {
    final rule = service.addPathRule(
      pattern: r'C:\Work\**\*.txt',
      mode: ViewerPathMatchMode.glob,
      viewerIds: ['viewer.a'],
    );
    await _openDialog(tester, service);

    expect(find.text(rule.value), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('viewer-rule-enabled-${rule.id}')));
    await tester.pump();
    expect(service.rule(rule.id).enabled, isFalse);
  });

  testWidgets('rule filter matches the rule name only', (tester) async {
    await _openDialog(tester, service);
    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();

    // 默认显示 .txt 规则
    expect(find.text('.txt'), findsOneWidget);

    // 按名称（匹配值）过滤
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-filter')),
      'txt',
    );
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsOneWidget);

    // 说明（副标题"扩展名"）不参与过滤：只匹配名称时无结果
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-filter')),
      '扩展名',
    );
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsNothing);
    expect(find.text('没有匹配的规则'), findsOneWidget);

    // 无匹配时显示空状态
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-filter')),
      '不存在的关键字',
    );
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsNothing);
    expect(find.text('没有匹配的规则'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDialog(WidgetTester tester, QuickViewService service) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<QuickViewService>.value(
      value: service,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showViewerAssociationsDialog(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void _writePlugin(Directory root, String id, String name) {
  final directory = Directory(p.join(root.path, id))..createSync();
  File(p.join(directory.path, 'viewer.exe')).writeAsBytesSync(const []);
  File(p.join(directory.path, 'plugin.json')).writeAsStringSync(
    jsonEncode({
      'manifestVersion': 1,
      'id': id,
      'name': name,
      'version': '1.0.0',
      'entrypoint': 'viewer.exe',
      'capabilities': {
        'quickView': {
          'extensions': ['.txt'],
        },
      },
    }),
  );
}
