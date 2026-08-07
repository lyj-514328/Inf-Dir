import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// ThemeMode 持久化：与 WindowLayoutStore 同一目录
/// （%LOCALAPPDATA%/Inf-Dir）下的小型 JSON 文件。
class ThemeStore {
  ThemeStore({String? filePath}) : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'theme.json');
  }

  /// 返回持久化的 [ThemeMode.name]；文件缺失或损坏时返回 null。
  String? load() {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map && decoded['themeMode'] is String) {
        return decoded['themeMode'] as String;
      }
    } on Object {
      // 缓存损坏不应阻止应用启动。
    }
    return null;
  }

  void save(String modeName) {
    try {
      final target = File(filePath);
      final contents = '${jsonEncode({'themeMode': modeName})}\n';
      if (target.existsSync() && target.readAsStringSync() == contents) return;
      target.parent.createSync(recursive: true);
      final temporary = File('$filePath.tmp');
      temporary.writeAsStringSync(contents, flush: true);
      temporary.renameSync(target.path);
    } on Object {
      // 持久化失败不影响主题切换功能。
    }
  }
}
