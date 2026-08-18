import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RegOpenKeyExNative =
    Int32 Function(
      IntPtr hKey,
      Pointer<Utf16> subKey,
      Uint32 options,
      Uint32 desired,
      Pointer<IntPtr> result,
    );

typedef _RegOpenKeyExDart =
    int Function(
      int hKey,
      Pointer<Utf16> subKey,
      int options,
      int desired,
      Pointer<IntPtr> result,
    );

typedef _RegQueryValueExNative =
    Int32 Function(
      IntPtr hKey,
      Pointer<Utf16> valueName,
      Pointer<Uint32> reserved,
      Pointer<Uint32> type,
      Pointer<Uint8> data,
      Pointer<Uint32> dataLength,
    );

typedef _RegQueryValueExDart =
    int Function(
      int hKey,
      Pointer<Utf16> valueName,
      Pointer<Uint32> reserved,
      Pointer<Uint32> type,
      Pointer<Uint8> data,
      Pointer<Uint32> dataLength,
    );

typedef _RegCloseKeyNative = Int32 Function(IntPtr hKey);
typedef _RegCloseKeyDart = int Function(int hKey);

/// 读取 Windows「App Paths」注册表项，解析系统安装程序的可执行文件路径。
abstract final class AppPathsService {
  static const int _hkeyLocalMachine = 0x80000002;
  static const int _hkeyCurrentUser = 0x80000001;
  static const int _keyRead = 0x20019;
  static const int _keyWow6464Key = 0x0100;
  static const int _regSz = 1;
  static const int _regExpandSz = 2;

  static final _advapi = DynamicLibrary.open('advapi32.dll');

  static final _openKey = _advapi
      .lookupFunction<_RegOpenKeyExNative, _RegOpenKeyExDart>('RegOpenKeyExW');

  static final _queryValue = _advapi
      .lookupFunction<_RegQueryValueExNative, _RegQueryValueExDart>(
        'RegQueryValueExW',
      );

  static final _closeKey = _advapi
      .lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

  static final Map<String, String?> _cache = {};

  /// 返回 `App Paths\<fileName>` 默认值指向的可执行文件路径；
  /// 先 HKLM 后 HKCU；REG_EXPAND_SZ 会展开环境变量；任何失败返回 null。
  static String? findExecutable(String fileName) {
    return _cache.putIfAbsent(
      fileName.toLowerCase(),
      () => _lookup(fileName),
    );
  }

  static String? _lookup(String fileName) {
    for (final root in const [_hkeyLocalMachine, _hkeyCurrentUser]) {
      final value = _readDefault(root, fileName);
      if (value != null) return value;
    }
    return null;
  }

  static String? _readDefault(int root, String fileName) {
    final subKey =
        'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$fileName'
            .toNativeUtf16();
    final key = calloc<IntPtr>();
    try {
      if (_openKey(
            root,
            subKey,
            0,
            _keyRead | _keyWow6464Key,
            key,
          ) !=
          0) {
        return null;
      }
      final type = calloc<Uint32>();
      final length = calloc<Uint32>();
      Pointer<Uint8> data = nullptr;
      try {
        if (_queryValue(
              key.value,
              nullptr.cast<Utf16>(),
              nullptr,
              type,
              nullptr,
              length,
            ) !=
            0) {
          return null;
        }
        if (type.value != _regSz && type.value != _regExpandSz) return null;
        if (length.value == 0) return null;
        data = calloc<Uint8>(length.value);
        if (_queryValue(
              key.value,
              nullptr.cast<Utf16>(),
              nullptr,
              type,
              data,
              length,
            ) !=
            0) {
          return null;
        }
        var value = data
            .cast<Utf16>()
            .toDartString(length: length.value ~/ 2)
            .split('\x00')
            .first
            .trim();
        if (value.length >= 2 &&
            value.startsWith('"') &&
            value.endsWith('"')) {
          value = value.substring(1, value.length - 1).trim();
        }
        if (value.isEmpty) return null;
        if (type.value == _regExpandSz) {
          value = _expandEnvironment(value);
        }
        return value;
      } finally {
        calloc.free(type);
        calloc.free(length);
        if (data != nullptr) calloc.free(data);
      }
    } finally {
      _closeKey(key.value);
      calloc.free(key);
      calloc.free(subKey);
    }
  }

  static String _expandEnvironment(String value) {
    return value.replaceAllMapped(RegExp('%([^%]+)%'), (match) {
      final name = match.group(1)!.toUpperCase();
      for (final entry in _environment.entries) {
        if (entry.key.toUpperCase() == name) return entry.value;
      }
      return match.group(0)!;
    });
  }

  static final Map<String, String> _environment = Platform.environment;
}
