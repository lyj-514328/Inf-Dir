import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/file_service.dart';
import '../services/settings_store.dart';
import 'pane_controller.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStore? store})
    : _store = store ?? SettingsStore() {
    _settings = _store.load();
  }

  final SettingsStore _store;
  late AppSettings _settings;

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_settings.themeMode] ?? ThemeMode.system;
  bool get showHiddenFiles => _settings.showHiddenFiles;
  bool get showFileExtensions => _settings.showFileExtensions;
  bool get showThumbnails => _settings.showThumbnails;
  PaneViewMode get defaultViewMode =>
      PaneViewMode.values.asNameMap()[_settings.defaultViewMode] ??
      PaneViewMode.details;
  NewTabLocation get newTabLocation => _settings.newTabLocation;
  String? get customNewTabPath => _settings.customNewTabPath;
  bool get confirmRecycleDelete => _settings.confirmRecycleDelete;

  IconData get themeIcon => switch (themeMode) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };

  String get themeLabel => switch (themeMode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '亮色',
    ThemeMode.dark => '暗色',
  };

  void setThemeMode(ThemeMode value) {
    if (themeMode == value) return;
    _update(_settings.copyWith(themeMode: value.name));
  }

  void cycleTheme() {
    setThemeMode(switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    });
  }

  void setShowHiddenFiles(bool value) {
    if (showHiddenFiles == value) return;
    _update(_settings.copyWith(showHiddenFiles: value));
  }

  void setShowFileExtensions(bool value) {
    if (showFileExtensions == value) return;
    _update(_settings.copyWith(showFileExtensions: value));
  }

  void setShowThumbnails(bool value) {
    if (showThumbnails == value) return;
    _update(_settings.copyWith(showThumbnails: value));
  }

  void setDefaultViewMode(PaneViewMode value) {
    if (defaultViewMode == value) return;
    _update(_settings.copyWith(defaultViewMode: value.name));
  }

  void setNewTabLocation(NewTabLocation value) {
    if (newTabLocation == value) return;
    _update(_settings.copyWith(newTabLocation: value));
  }

  void setCustomNewTabPath(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || customNewTabPath == normalized) return;
    _update(
      _settings.copyWith(
        customNewTabPath: normalized,
        newTabLocation: NewTabLocation.custom,
      ),
    );
  }

  void setConfirmRecycleDelete(bool value) {
    if (confirmRecycleDelete == value) return;
    _update(_settings.copyWith(confirmRecycleDelete: value));
  }

  String resolveNewTabPath(String currentPath) {
    return switch (newTabLocation) {
      NewTabLocation.current => currentPath,
      NewTabLocation.home => FileService.homeViewPath,
      NewTabLocation.custom => customNewTabPath ?? currentPath,
    };
  }

  void _update(AppSettings value) {
    _settings = value;
    _store.save(value);
    notifyListeners();
  }
}
