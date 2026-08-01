/// 路径规范化与比较工具（供 Sidebar / Repository / Pane 共用）。
library;

/// 规范化为小写、反斜杠、去尾部分隔符（保留盘符根如 `c:\`）。
String normPath(String path) {
  var s = path.replaceAll('/', '\\');
  while (s.length > 3 && s.endsWith('\\')) {
    s = s.substring(0, s.length - 1);
  }
  return s.toLowerCase();
}

bool pathEquals(String a, String b) => normPath(a) == normPath(b);

/// [child] 是否等于或位于 [parent] 之下。
bool isUnder(String child, String parent) {
  final nc = normPath(child);
  final np = normPath(parent);
  return nc == np || nc.startsWith(np.endsWith('\\') ? np : '$np\\');
}

/// 从 [drive] 到 [targetPath] 的有序路径链：
/// `C:\` → `C:\Users` → `C:\Users\Alice` ...
List<String> pathChain(String drive, String targetPath) {
  final paths = <String>[drive];
  if (normPath(targetPath) == normPath(drive)) return paths;

  var rel = targetPath.replaceAll('/', '\\');
  if (rel.toLowerCase().startsWith(drive.toLowerCase())) {
    rel = rel.substring(drive.length);
  }
  final segments = rel.split('\\').where((s) => s.isNotEmpty).toList();

  var current =
      drive.endsWith('\\') ? drive.substring(0, drive.length - 1) : drive;
  for (final seg in segments) {
    current = '$current\\$seg';
    paths.add(current);
  }
  return paths;
}
