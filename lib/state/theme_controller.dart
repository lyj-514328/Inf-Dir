import 'package:flutter/material.dart';

/// 明暗主题切换 —— system / light / dark 三态循环，默认跟随系统。
/// 不做持久化，重启后回到 system。
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// system → light → dark → system
  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
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
