import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/app_settings.dart';
import 'package:inf_dir/services/file_service.dart';
import 'package:inf_dir/services/settings_store.dart';
import 'package:inf_dir/state/pane_controller.dart';
import 'package:inf_dir/state/settings_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String settingsPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_settings_');
    settingsPath = p.join(temp.path, 'settings.json');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('migrates legacy preference and theme files into settings.json', () {
    final prefsPath = p.join(temp.path, 'prefs.json');
    final themePath = p.join(temp.path, 'theme.json');
    File(prefsPath).writeAsStringSync(
      jsonEncode({
        'showHiddenFiles': true,
        'showFileExtensions': false,
        'showThumbnails': false,
      }),
    );
    File(themePath).writeAsStringSync(jsonEncode({'themeMode': 'dark'}));

    final settings = SettingsStore(
      filePath: settingsPath,
      legacyPrefsPath: prefsPath,
      legacyThemePath: themePath,
    ).load();

    expect(settings.themeMode, 'dark');
    expect(settings.showHiddenFiles, isTrue);
    expect(settings.showFileExtensions, isFalse);
    expect(settings.showThumbnails, isFalse);
    expect(File(settingsPath).existsSync(), isTrue);
    final json = jsonDecode(File(settingsPath).readAsStringSync()) as Map;
    expect(json['schemaVersion'], AppSettings.currentSchemaVersion);
  });

  test(
    'decodes v1 into current settings and rewrites only the latest JSON',
    () {
      File(settingsPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'themeMode': 'light',
          'showThumbnails': false,
          'removedSetting': 'legacy',
        }),
      );

      final settings = SettingsStore(filePath: settingsPath).load();

      final json = jsonDecode(File(settingsPath).readAsStringSync()) as Map;
      expect(settings.themeMode, 'light');
      expect(settings.showThumbnails, isFalse);
      expect(json['schemaVersion'], AppSettings.currentSchemaVersion);
      expect(json['themeMode'], 'light');
      expect(json.containsKey('removedSetting'), isFalse);
    },
  );

  test('does not overwrite a settings file from a future version', () {
    final original = jsonEncode({
      'schemaVersion': AppSettings.currentSchemaVersion + 1,
      'themeMode': 'future-theme',
      'futureSetting': true,
    });
    File(settingsPath).writeAsStringSync(original);
    final store = SettingsStore(filePath: settingsPath);
    final controller = SettingsController(store: store);
    addTearDown(controller.dispose);

    expect(store.writesEnabled, isFalse);
    expect(controller.themeMode, ThemeMode.system);
    controller.setThemeMode(ThemeMode.dark);

    expect(File(settingsPath).readAsStringSync(), original);
  });

  test('invalid enum values fall back without discarding valid values', () {
    final settings = AppSettings.fromJson({
      'schemaVersion': AppSettings.currentSchemaVersion,
      'themeMode': 'midnight',
      'defaultViewMode': 'gallery',
      'newTabLocation': 'cloud',
      'confirmRecycleDelete': false,
    });

    expect(settings.themeMode, 'system');
    expect(settings.defaultViewMode, 'details');
    expect(settings.newTabLocation, NewTabLocation.current);
    expect(settings.confirmRecycleDelete, isFalse);
  });

  test('resolves current, home and custom new-tab locations', () {
    final controller = SettingsController(
      store: SettingsStore(filePath: settingsPath),
    );
    addTearDown(controller.dispose);

    expect(controller.resolveNewTabPath(r'C:\Current'), r'C:\Current');

    controller.setNewTabLocation(NewTabLocation.home);
    expect(
      controller.resolveNewTabPath(r'C:\Current'),
      FileService.homeViewPath,
    );

    controller.setCustomNewTabPath(r'D:\Work');
    expect(controller.newTabLocation, NewTabLocation.custom);
    expect(controller.resolveNewTabPath(r'C:\Current'), r'D:\Work');
  });

  test('exposes typed default view mode', () {
    final controller = SettingsController(
      store: SettingsStore(filePath: settingsPath),
    );
    addTearDown(controller.dispose);

    controller.setDefaultViewMode(PaneViewMode.tiles);

    expect(controller.defaultViewMode, PaneViewMode.tiles);
    expect(
      SettingsStore(filePath: settingsPath).load().defaultViewMode,
      'tiles',
    );
  });
}
