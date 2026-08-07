import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/window_layout_snapshot.dart';

class WindowLayoutStore {
  WindowLayoutStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  String get _backupPath => '$filePath.bak';
  String get _temporaryPath => '$filePath.tmp';

  static String defaultFilePath() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? p.dirname(Platform.resolvedExecutable)
        : localAppData;
    return p.join(root, 'Inf-Dir', 'window_layout.json');
  }

  WindowLayoutSnapshot? load() {
    for (final path in [filePath, _backupPath]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        return WindowLayoutSnapshot.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      } on Object {
        // A cache must never prevent the application from starting. Try the
        // previous snapshot, then let LayoutState create its default layout.
      }
    }
    return null;
  }

  void save(WindowLayoutSnapshot snapshot) {
    const encoder = JsonEncoder.withIndent('  ');
    final contents = '${encoder.convert(snapshot.toJson())}\n';
    final target = File(filePath);

    if (target.existsSync() && target.readAsStringSync() == contents) return;

    target.parent.createSync(recursive: true);
    final temporary = File(_temporaryPath);
    temporary.writeAsStringSync(contents, flush: true);

    try {
      final backup = File(_backupPath);
      if (backup.existsSync()) backup.deleteSync();
      if (target.existsSync()) {
        target.copySync(backup.path);
        target.deleteSync();
      }
      temporary.renameSync(target.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}
