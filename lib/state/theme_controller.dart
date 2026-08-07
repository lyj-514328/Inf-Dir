import 'package:flutter/material.dart';

import '../services/theme_store.dart';

/// 明暗主题切换 —— system / light / dark 三态循环，默认跟随系统。
/// 构造时从 [ThemeStore] 同步加载上次选择，切换时持久化。
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeStore? store}) : _store = store ?? ThemeStore() {
    final saved = _store.load();
    if (saved != null) {
      _mode = ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
    }
  }

  final ThemeStore _store;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// system → light → dark → system
  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    _store.save(_mode.name);
    notifyListeners();
  }

  IconData get icon => switch (_mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      };

  String get label => switch (_mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '亮色',
        ThemeMode.dark => '深色',
      };
}
