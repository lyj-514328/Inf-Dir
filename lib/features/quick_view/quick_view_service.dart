import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 一个 viewer 程序的配置。
class ViewerConfig {
  final String name;
  final String exeName; // plugins/ 下的 exe 文件名
  final String args; // 参数模板，{file} 会被替换为文件路径
  final List<String> exts; // 支持的文件扩展名（小写，含点）

  const ViewerConfig({
    required this.name,
    required this.exeName,
    this.args = '{file}',
    this.exts = const [],
  });
}

/// QuickView 服务：根据文件扩展名找到对应的 viewer exe 并启动。
class QuickViewService {
  // ── 内置 viewer 注册表 ──────────────────────────────────────────
  static const List<ViewerConfig> _viewers = [
    ViewerConfig(
      name: '图片查看器',
      exeName: 'img-view.exe',
      args: '--width 960 --height 720 {file}',
      exts: [
        '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp',
        '.avif', '.tiff', '.tif', '.ico', '.hdr',
      ],
    ),
    ViewerConfig(
      name: '文本查看器',
      exeName: 'text-view.exe',
      args: '--width 960 --height 720 {file}',
      exts: [
        '.txt', '.md', '.log', '.csv', '.json', '.xml', '.yaml', '.yml',
        '.ini', '.conf', '.cfg', '.bat', '.cmd', '.ps1', '.sh',
        '.dart', '.py', '.js', '.ts', '.rs', '.go', '.c', '.cpp',
        '.h', '.hpp', '.java', '.cs', '.html', '.css', '.sql',
        '.toml', '.gradle', '.properties', '.env', '.gitignore',
      ],
    ),
    ViewerConfig(
      name: 'PDF 查看器',
      exeName: 'pdf-view.exe',
      args: '--width 960 --height 720 {file}',
      exts: ['.pdf'],
    ),
    ViewerConfig(
      name: 'Office 查看器',
      exeName: 'office-view.exe',
      args: '--width 960 --height 720 {file}',
      exts: ['.docx', '.xlsx', '.pptx', '.docm', '.xlsm', '.pptm'],
    ),
    ViewerConfig(
      name: '视频查看器',
      exeName: 'video-view.exe',
      args: '--width 960 --height 720 {file}',
      exts: [
        '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv',
        '.wmv', '.m4v', '.mpg', '.mpeg', '.ts', '.3gp',
      ],
    ),
    ViewerConfig(
      name: '压缩包查看器',
      exeName: 'archive-view.exe',
      exts: [
        '.zip', '.7z', '.rar', '.tar', '.gz', '.xz',
        '.bz2', '.iso', '.cab', '.arj', '.lzh',
      ],
    ),
  ];

  /// 根据文件路径查找匹配的 viewer。
  static ViewerConfig? match(String filePath) {
    final lower = filePath.toLowerCase();
    for (final v in _viewers) {
      if (v.exts.any((ext) => lower.endsWith(ext))) return v;
    }
    return null;
  }

  // ── plugins/ 目录定位 ──────────────────────────────────────────
  /// 返回可用的 plugins 目录路径（第一个存在的）。
  static String? get _pluginsDir {
    const candidates = <String>[
      // 开发期：cwd 就是项目根目录
      'plugins',
      // 发布期：exe 旁边的 plugins 目录
    ];

    for (final c in candidates) {
      if (Directory(c).existsSync()) return c;
    }

    // 通过 exe 路径反推（发布版、flutter build windows）
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      for (final rel in ['plugins', '../plugins', '../../plugins']) {
        final candidate = p.normalize(p.join(exeDir, rel));
        if (Directory(candidate).existsSync()) return candidate;
      }
    } catch (_) {}

    return null;
  }

  /// 查找 viewer exe 的完整路径。
  static String? resolveExe(ViewerConfig config) {
    final dir = _pluginsDir;
    if (dir == null) return null;

    final full = p.join(dir, config.exeName);
    if (File(full).existsSync()) return full;

    debugPrint('[QuickView] exe not found: $full');
    return null;
  }

  // ── 启动 viewer ────────────────────────────────────────────────
  /// 为指定文件启动 QuickView。返回 true 表示成功启动。
  static Future<bool> open(String filePath) async {
    final config = match(filePath);
    if (config == null) {
      debugPrint('[QuickView] no viewer for: $filePath');
      return false;
    }

    final exe = resolveExe(config);
    if (exe == null) return false;

    final cmd = config.args.replaceAll('{file}', filePath);
    final argsList = _splitArgs(cmd);

    debugPrint('[QuickView] launching: $exe ${argsList.join(' ')}');

    try {
      await Process.run(exe, argsList);
      return true;
    } catch (e) {
      debugPrint('[QuickView] launch failed: $e');
      return false;
    }
  }

  /// 简单参数拆分（按空格，双引号保留）。
  static List<String> _splitArgs(String cmd) {
    final result = <String>[];
    var buf = StringBuffer();
    var inQuote = false;

    for (var i = 0; i < cmd.length; i++) {
      final ch = cmd[i];
      if (ch == '"') {
        inQuote = !inQuote;
      } else if (ch == ' ' && !inQuote) {
        if (buf.isNotEmpty) {
          result.add(buf.toString());
          buf = StringBuffer();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }
}
