import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';

class SettingsStore {
  SettingsStore({
    String? filePath,
    String? legacyPrefsPath,
    String? legacyThemePath,
  }) : filePath = filePath ?? defaultFilePath(),
       legacyPrefsPath =
           legacyPrefsPath ??
           p.join(p.dirname(filePath ?? defaultFilePath()), 'prefs.json'),
       legacyThemePath =
           legacyThemePath ??
           p.join(p.dirname(filePath ?? defaultFilePath()), 'theme.json');

  final String filePath;
  final String legacyPrefsPath;
  final String legacyThemePath;
  bool _writesEnabled = true;

  bool get writesEnabled => _writesEnabled;

  String get _backupPath => '$filePath.bak';
  String get _temporaryPath => '$filePath.tmp';

  static String defaultFilePath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'settings.json');
  }

  AppSettings load() {
    _writesEnabled = true;
    for (final path in [filePath, _backupPath]) {
      final json = _readJson(path);
      if (json == null) continue;
      try {
        final version = AppSettings.schemaVersionOf(json);
        if (version > AppSettings.currentSchemaVersion) {
          _writesEnabled = false;
          debugPrint(
            '[Settings] schema v$version is newer than supported '
            'v${AppSettings.currentSchemaVersion}; writes disabled',
          );
          return const AppSettings();
        }
        final settings = AppSettings.fromJson(json);
        if (path == filePath && version < AppSettings.currentSchemaVersion) {
          save(settings);
        }
        return settings;
      } on Object catch (error) {
        debugPrint('[Settings] decode failed from $path: $error');
      }
    }

    final migrated = _loadLegacy();
    if (migrated != null) {
      save(migrated);
      return migrated;
    }
    return const AppSettings();
  }

  Map<String, Object?>? _readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      }
    } on Object catch (error) {
      debugPrint('[Settings] load failed from $path: $error');
    }
    return null;
  }

  AppSettings? _loadLegacy() {
    final prefs = _readJson(legacyPrefsPath);
    final theme = _readJson(legacyThemePath);
    if (prefs == null && theme == null) return null;

    return AppSettings.fromJson({
      if (theme?['themeMode'] is String) 'themeMode': theme!['themeMode'],
      if (prefs?['showHiddenFiles'] is bool)
        'showHiddenFiles': prefs!['showHiddenFiles'],
      if (prefs?['showFileExtensions'] is bool)
        'showFileExtensions': prefs!['showFileExtensions'],
      if (prefs?['showThumbnails'] is bool)
        'showThumbnails': prefs!['showThumbnails'],
    });
  }

  void save(AppSettings settings) {
    if (!_writesEnabled) return;
    const encoder = JsonEncoder.withIndent('  ');
    final contents = '${encoder.convert(settings.toJson())}\n';
    final target = File(filePath);
    try {
      if (target.existsSync() && target.readAsStringSync() == contents) return;
      target.parent.createSync(recursive: true);
      final temporary = File(_temporaryPath);
      temporary.writeAsStringSync(contents, flush: true);

      final backup = File(_backupPath);
      if (backup.existsSync()) backup.deleteSync();
      if (target.existsSync()) {
        target.copySync(backup.path);
        target.deleteSync();
      }
      temporary.renameSync(target.path);
    } on Object catch (error) {
      debugPrint('[Settings] save failed: $error');
    } finally {
      final temporary = File(_temporaryPath);
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}
