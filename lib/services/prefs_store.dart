import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PrefsStore {
  PrefsStore({String? filePath}) : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'prefs.json');
  }

  Map<String, Object?> load() {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return const {};
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
    } on Object {
      // 缓存损坏不应阻止应用启动。
    }
    return const {};
  }

  void save(Map<String, Object?> values) {
    try {
      final target = File(filePath);
      final contents = '${jsonEncode(values)}\n';
      if (target.existsSync() && target.readAsStringSync() == contents) return;
      target.parent.createSync(recursive: true);
      final temporary = File('$filePath.tmp');
      temporary.writeAsStringSync(contents, flush: true);
      temporary.renameSync(target.path);
    } on Object {
      // 持久化失败不影响运行时开关。
    }
  }
}
