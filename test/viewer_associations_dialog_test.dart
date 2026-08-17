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

  testWidgets('shows path and three manifest association groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDialog(tester, service);

    expect(find.text('路径'), findsOneWidget);
    expect(find.text('扩展名'), findsOneWidget);
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('MIME'), findsOneWidget);
    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();
    expect(find.text('.txt'), findsOneWidget);
    expect(find.text('A Viewer'), findsOneWidget);
    expect(find.text('B Viewer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkbox and move controls persist candidate order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDialog(tester, service);

    await tester.tap(find.text('扩展名'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下移').first);
    await tester.pump();
    expect(
      service
          .candidatesForAssociation(ViewerAssociationKind.extension, '.txt')
          .map((plugin) => plugin.manifest.id),
      ['viewer.b', 'viewer.a'],
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(
      service
          .candidatesForAssociation(ViewerAssociationKind.extension, '.txt')
          .map((plugin) => plugin.manifest.id),
      ['viewer.a'],
    );
    expect(File(p.join(temp.path, 'associations.json')).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('path rules can be enabled and disabled', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rule = service.addPathRule(
      pattern: r'C:\Work\**\*.txt',
      mode: ViewerPathMatchMode.glob,
      viewerIds: ['viewer.a'],
    );

    await _openDialog(tester, service);

    expect(find.text(rule.pattern), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('path-rule-enabled-${rule.id}')));
    await tester.pump();
    expect(service.pathRules.single.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a path rule with an initial viewer', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openDialog(tester, service);
    await tester.tap(find.byTooltip('添加路径规则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), r'C:\Work\**\*.txt');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(service.pathRules, hasLength(1));
    expect(service.pathRules.single.pattern, r'C:\Work\**\*.txt');
    expect(service.pathRules.single.viewerIds, ['viewer.a']);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDialog(WidgetTester tester, QuickViewService service) async {
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
