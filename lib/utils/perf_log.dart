import 'dart:io';

/// Simple performance log that writes to a file on Desktop.
class PerfLog {
  static File? _file;
  static Future<void> _pendingWrite = Future<void>.value();

  static File get _logFile {
    if (_file != null) return _file!;
    final desktop = Platform.environment['USERPROFILE'] ?? '.';
    _file = File('$desktop\\Desktop\\inf_dir_perf.txt');
    // Clear on startup
    _file!.writeAsStringSync('=== Inf-Dir Perf Log ${DateTime.now()} ===\n');
    return _file!;
  }

  static void write(String msg) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final line = '[$ts] $msg\n';
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      await _logFile.writeAsString(line, mode: FileMode.append);
    });
  }
}
