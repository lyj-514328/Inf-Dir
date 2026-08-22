import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  late File defaultConfigFile;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_plugin_ui_');
    final pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
    _writePlugin(pluginRoot, 'viewer.a', 'A Viewer');
    _writePlugin(pluginRoot, 'viewer.b', 'B Viewer');
    defaultConfigFile = File(p.join(pluginRoot.path, 'quick-view.default.json'))
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 3,
          'id': 'default',
          'name': '默认',
          'rules': [
            _rule('ext-txt', 'extension', '.txt', ['viewer.a', 'viewer.b']),
          ],
        }),
      );
    service = QuickViewService(
      pluginRoots: [pluginRoot],
      associationStore: ViewerAssociationStore(
        filePath: p.join(temp.path, 'associations.json'),
      ),
      defaultConfigFile: defaultConfigFile,
      mimeTypeResolver: (_) => null,
    );
  });

  tearDown(() {
    service.dispose();
    temp.deleteSync(recursive: true);
  });

  testWidgets('shows the fully locked preset default group', (tester) async {
    await _openDialog(tester, service);

    expect(find.text('默认'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-rule-groups-list')), findsOne);

    // 预置组（默认选中）：无勾选、无拖拽手柄、规则操作全禁用。
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(_iconButton(tester, '新建规则').onPressed, isNull);
    expect(_iconButton(tester, '添加子规则').onPressed, isNull);
    expect(_iconButton(tester, '编辑规则').onPressed, isNull);
    expect(_iconButton(tester, '删除规则').onPressed, isNull);
    expect(_iconButton(tester, '重命名').onPressed, isNull);
    expect(_iconButton(tester, '删除规则组').onPressed, isNull);

    // 预置规则只读，Viewer 列表只读。
    await tester.tap(find.text('.txt'));
    await tester.pumpAndSettle();
    expect(find.text('A Viewer'), findsOneWidget);
    expect(find.text('B Viewer'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-enabled-viewer.a')), findsNothing);
    expect(_iconButton(tester, '添加 Viewer').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaf and parent rules share the same name column', (
    tester,
  ) async {
    // 带子规则的父规则与叶子规则同深度：名称列必须对齐。
    defaultConfigFile.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 3,
        'id': 'default',
        'name': '默认',
        'rules': [
          _rule('name-makefile', 'fileName', 'makefile', ['viewer.a']),
          {
            ..._rule('ext-markdown', 'extension', '.markdown', ['viewer.a']),
            'rules': [
              _rule('mime-markdown', 'mimeType', 'text/markdown', [
                'viewer.b',
              ]),
              _rule('mime-x-markdown', 'mimeType', 'text/x-markdown', [
                'viewer.b',
              ]),
            ],
          },
        ],
      }),
    );
    service.reload();
    await _openDialog(tester, service);

    final leafX = tester.getTopLeft(find.text('makefile')).dx;
    final parentX = tester.getTopLeft(find.text('.markdown')).dx;
    expect(parentX, leafX);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user groups reorder around the locked preset group', (
    tester,
  ) async {
    await _openDialog(tester, service);

    await tester.tap(find.byTooltip('新建规则组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-group-name')),
      '项目规则',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(service.ruleGroups.map((group) => group.id), [
      ViewerAssociationConfig.defaultGroupId,
      service.ruleGroups.last.id,
    ]);

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('viewer-rule-groups-list')),
    );
    list.onReorderItem!(1, 0);
    await tester.pump();

    expect(service.ruleGroups.first.id, isNot(ViewerAssociationConfig.defaultGroupId));
    expect(service.ruleGroups.last.id, ViewerAssociationConfig.defaultGroupId);

    // 用户配置只记录 default 引用，不存默认规则。
    final saved =
        jsonDecode(
              File(p.join(temp.path, 'associations.json')).readAsStringSync(),
            )
            as Map;
    final savedGroups = saved['groups']! as List;
    expect((savedGroups.first as Map)['id'], isNot('default'));
    expect((savedGroups.last as Map)['id'], 'default');
    expect((savedGroups.last as Map)['preset'], isTrue);
    expect(savedGroups.last, isNot(contains('rules')));
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

    expect(service.ruleGroups, hasLength(2));
    expect(service.ruleGroups.last.name, '项目规则');
    expect(service.ruleGroups.last.rules, isEmpty);
    expect(find.text('项目规则'), findsOneWidget);
  });

  testWidgets('allows mixed rules and nested child rules in a user group', (
    tester,
  ) async {
    await _openDialog(tester, service);
    await tester.tap(find.byTooltip('新建规则组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-group-name')),
      '项目规则',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    // 用户组规则列可编辑
    await tester.tap(find.byTooltip('新建规则'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-value')),
      '.txt',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsOneWidget);

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

    final group = service.ruleGroups.last;
    final parent = group.rules.single;
    expect(parent.rules, hasLength(1));
    expect(parent.rules.single.type, ViewerRuleType.mimeType);
    expect(parent.rules.single.value, 'text/x-special');
    expect(find.text('text/x-special'), findsOneWidget);
  });

  testWidgets('viewer checkboxes and drag order persist in a user rule', (
    tester,
  ) async {
    final group = service.addRuleGroup(name: '自定义');
    final valueRule = service.addRule(
      groupId: group.id,
      type: ViewerRuleType.extension,
      value: '.txt',
      viewerIds: ['viewer.a', 'viewer.b'],
    );

    await _openDialog(tester, service);
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('.txt'));
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('viewer-candidates-list')),
    );
    list.onReorderItem!(0, 1);
    await tester.pump();
    expect(
      service.rule(valueRule.id).viewers.map((viewer) => viewer.id),
      ['viewer.b', 'viewer.a'],
    );

    await tester.tap(find.byKey(const ValueKey('viewer-enabled-viewer.b')));
    await tester.pump();
    expect(
      service.rule(valueRule.id).viewers.map((viewer) => viewer.enabled),
      [false, true],
    );
    expect(File(p.join(temp.path, 'associations.json')).existsSync(), isTrue);
  });

  testWidgets('path rules use the same recursive rule editor', (tester) async {
    final group = service.addRuleGroup(name: '路径组');
    await _openDialog(tester, service);
    await tester.tap(find.text('路径组'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer-rule-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('路径').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-value')),
      r'C:\Work\**\*.txt',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final rule = group.rules.single;
    expect(rule.type, ViewerRuleType.path);
    expect(rule.value, r'C:\Work\**\*.txt');
    expect(find.text(rule.value), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('viewer-rule-enabled-${rule.id}')));
    await tester.pump();
    expect(service.rule(rule.id).enabled, isFalse);
  });

  testWidgets('rule filter matches the rule name only', (tester) async {
    await _openDialog(tester, service);

    // 默认组（预置）已选中，规则列显示 .txt
    expect(find.text('.txt'), findsOneWidget);

    // 按名称（匹配值）过滤
    await tester.enterText(
      find.byKey(const ValueKey('viewer-rule-filter')),
      'txt',
    );
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsOneWidget);

    // 说明（副标题"扩展名 · 2 个 Viewer"）不参与过滤：只匹配名称时无结果
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

Map<String, Object?> _rule(
  String id,
  String type,
  String value,
  List<String> viewerIds,
) => {
  'id': id,
  'enabled': true,
  'type': type,
  'value': value,
  'rules': <Object?>[],
  'viewers': [
    for (final viewerId in viewerIds) {'id': viewerId, 'enabled': true},
  ],
};

IconButton _iconButton(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
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
