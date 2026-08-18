import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../services/app_paths_service.dart';
import 'plugin_manifest.dart';

typedef _GetFileAttributesWNative = Uint32 Function(Pointer<Utf16> path);
typedef _GetFileAttributesWDart = int Function(Pointer<Utf16> path);

/// 解析 openDirectory 插件实际使用的可执行文件路径。
///
/// 顺序：环境变量覆盖 → App Paths 注册表 → PATH 扫描 → 常见安装位置。
class DirectoryOpenerResolver {
  DirectoryOpenerResolver({
    Map<String, String>? environment,
    String? Function(String fileName)? appPathsLookup,
    List<String> Function()? pathDirectories,
    bool Function(String path)? fileExists,
  }) : _environment = environment ?? Platform.environment,
       _appPathsLookup = appPathsLookup ?? AppPathsService.findExecutable,
       _pathDirectories =
           pathDirectories ??
           (() => _defaultPathDirectories(
             environment ?? Platform.environment,
           )),
       _fileExists =
           fileExists ??
           (Platform.isWindows ? _win32FileExists : _defaultFileExists);

  final Map<String, String> _environment;
  final String? Function(String fileName) _appPathsLookup;
  final List<String> Function() _pathDirectories;
  final bool Function(String path) _fileExists;

  /// `inf-dir.vscode-open` → `INF_DIR_VSCODE_OPEN_PATH`
  static String environmentOverrideName(String pluginId) {
    return '${pluginId.toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '_')}_PATH';
  }

  String? resolve(PluginManifest manifest) {
    final capability = manifest.openDirectory;
    if (capability == null) return null;

    final override = _environment[environmentOverrideName(manifest.id)];
    if (override != null && override.trim().isNotEmpty) {
      final path = _expand(override.trim());
      if (path != null && _fileExists(path)) return path;
    }

    for (final name in capability.appPaths) {
      final path = _appPathsLookup(name);
      if (path == null) continue;
      final expanded = _expand(path);
      if (expanded != null && _fileExists(expanded)) return expanded;
    }

    for (final directory in _pathDirectories()) {
      if (directory.trim().isEmpty) continue;
      for (final name in capability.executables) {
        final candidate = p.join(directory, name);
        if (_fileExists(candidate)) return candidate;
      }
    }

    for (final template in capability.installPaths) {
      final path = _expand(template);
      if (path != null && _fileExists(path)) return path;
    }

    return null;
  }

  /// 展开 `%NAME%`；存在未知变量时返回 null。
  String? _expand(String value) {
    var unknown = false;
    final expanded = value.replaceAllMapped(RegExp('%([^%]+)%'), (match) {
      final name = match.group(1)!.toUpperCase();
      for (final entry in _environment.entries) {
        if (entry.key.toUpperCase() == name) return entry.value;
      }
      unknown = true;
      return '';
    });
    return unknown ? null : expanded;
  }

  static List<String> _defaultPathDirectories(Map<String, String> environment) {
    for (final entry in environment.entries) {
      if (entry.key.toUpperCase() == 'PATH') {
        return entry.value.split(';');
      }
    }
    return const [];
  }

  static bool _defaultFileExists(String path) => File(path).existsSync();

  static const int _invalidFileAttributes = 0xFFFFFFFF;

  static final _getFileAttributes = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_GetFileAttributesWNative, _GetFileAttributesWDart>(
        'GetFileAttributesW',
      );

  /// Windows 下的存在性检查：App 执行别名（如
  /// `%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe`）是 reparse point，
  /// Dart 的 stat 会报告为不存在，而 GetFileAttributesW 能正确识别。
  static bool _win32FileExists(String path) {
    final nativePath = path.toNativeUtf16();
    try {
      return _getFileAttributes(nativePath) != _invalidFileAttributes;
    } finally {
      calloc.free(nativePath);
    }
  }
}
