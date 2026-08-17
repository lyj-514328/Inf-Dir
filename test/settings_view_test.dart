import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/features/quick_view/quick_view_service.dart';
import 'package:inf_dir/features/quick_view/viewer_association_config.dart';
import 'package:inf_dir/features/settings/settings_view.dart';
import 'package:inf_dir/models/app_settings.dart';
import 'package:inf_dir/services/settings_store.dart';
import 'package:inf_dir/state/settings_controller.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SettingsController settings;
  late QuickViewService quickView;
  late int clearCount;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_settings_ui_');
    settings = SettingsController(
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
    );
    final pluginRoot = Directory(p.join(temp.path, 'plugins'))..createSync();
    quickView = QuickViewService(
      pluginRoots: [pluginRoot],
      associationStore: ViewerAssociationStore(
        filePath: p.join(temp.path, 'associations.json'),
      ),
      mimeTypeResolver: (_) => null,
    );
    clearCount = 0;
  });

  tearDown(() {
    settings.dispose();
    quickView.dispose();
    temp.deleteSync(recursive: true);
  });

  testWidgets('shows categories and edits appearance settings', (tester) async {
    await _pumpSettings(
      tester,
      settings,
      quickView,
      onClearThumbnailCache: () => clearCount++,
    );

    expect(find.text('常规'), findsWidgets);
    expect(find.text('外观与浏览'), findsOneWidget);
    expect(find.text('文件操作'), findsOneWidget);
    expect(find.text('查看器'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-category-appearance')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('setting-theme')), findsOneWidget);
    await tester.tap(find.text('暗色'));
    await tester.pump();
    expect(settings.themeMode, ThemeMode.dark);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('setting-show-thumbnails')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(settings.showThumbnails, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters to matching setting and can clear cache', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      settings,
      quickView,
      onClearThumbnailCache: () => clearCount++,
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      '回收站',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('setting-confirm-recycle-delete')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('setting-theme')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      '缩略图缓存',
    );
    await tester.pump();
    await tester.tap(find.text('清除'));
    await tester.pump();
    expect(clearCount, 1);
  });

  testWidgets('custom new-tab location uses injected folder picker', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      settings,
      quickView,
      onClearThumbnailCache: () => clearCount++,
      folderPicker: (_) => r'D:\Projects',
    );

    await tester.tap(find.byType(DropdownButton<NewTabLocation>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义目录').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择'));
    await tester.pump();

    expect(settings.newTabLocation, NewTabLocation.custom);
    expect(settings.customNewTabPath, r'D:\Projects');
    expect(find.text(r'D:\Projects'), findsOneWidget);
  });

  testWidgets('viewer category embeds association management', (tester) async {
    await _pumpSettings(
      tester,
      settings,
      quickView,
      onClearThumbnailCache: () => clearCount++,
    );

    await tester.tap(find.byKey(const ValueKey('settings-category-viewers')));
    await tester.pumpAndSettle();

    expect(find.text('路径'), findsOneWidget);
    expect(find.text('扩展名'), findsOneWidget);
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('MIME'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('viewer-rule-group-builtin-path')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  SettingsController settings,
  QuickViewService quickView, {
  required VoidCallback onClearThumbnailCache,
  SettingsFolderPicker? folderPicker,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<QuickViewService>.value(value: quickView),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsView(
            folderPicker: folderPicker,
            onShowHiddenFilesChanged: settings.setShowHiddenFiles,
            onShowFileExtensionsChanged: settings.setShowFileExtensions,
            onShowThumbnailsChanged: settings.setShowThumbnails,
            onClearThumbnailCache: onClearThumbnailCache,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
