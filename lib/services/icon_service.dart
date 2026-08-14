import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _GetPngNative =
    Pointer<Uint8> Function(
      Pointer<Utf16> path,
      Int32 size,
      Pointer<Int32> outSize,
    );
typedef _GetPngDart =
    Pointer<Uint8> Function(
      Pointer<Utf16> path,
      int size,
      Pointer<Int32> outSize,
    );

typedef _FreePngNative = Void Function(Pointer<Uint8> ptr);
typedef _FreePngDart = void Function(Pointer<Uint8> ptr);

typedef _GetCloudStatusNative = Int32 Function(Pointer<Utf16> path);
typedef _GetCloudStatusDart = int Function(Pointer<Utf16> path);

class IconService {
  static final _GetPngDart? _getPng = _lookupPng('GetFileIconPngW');

  static final _GetPngDart? _getOverlayPng = _lookupPng('GetFileOverlayPngW');

  static final _GetCloudStatusDart? _getCloudStatus = _lookupCloudStatus();

  static final _FreePngDart? _freePng = _lookupFreePng();

  static final Map<String, Uint8List> _pngCache = {};
  static final Map<String, Uint8List?> _overlayCache = {};
  static final Map<String, int> _cloudStatusCache = {};

  static _GetPngDart? _lookupPng(String symbol) {
    try {
      return DynamicLibrary.process()
          .lookupFunction<_GetPngNative, _GetPngDart>(symbol);
    } on ArgumentError {
      return null;
    }
  }

  static _GetCloudStatusDart? _lookupCloudStatus() {
    try {
      return DynamicLibrary.process()
          .lookupFunction<_GetCloudStatusNative, _GetCloudStatusDart>(
            'GetFileCloudStatusW',
          );
    } on ArgumentError {
      return null;
    }
  }

  static _FreePngDart? _lookupFreePng() {
    try {
      return DynamicLibrary.process()
          .lookupFunction<_FreePngNative, _FreePngDart>('FreeIconPngW');
    } on ArgumentError {
      return null;
    }
  }

  static Uint8List? getFileIconPng(String path, bool isDirectory, int size) {
    final cacheKey = '${isDirectory ? 'D' : 'F'}:$path:$size';
    final cached = _pngCache[cacheKey];
    if (cached != null) return cached;
    final getPng = _getPng;
    final freePng = _freePng;
    if (getPng == null || freePng == null) return null;

    final pathPtr = path.toNativeUtf16();
    final outSize = calloc<Int32>();
    try {
      final ptr = getPng(pathPtr, size, outSize);
      if (ptr == nullptr || outSize.value <= 0) return null;
      final len = outSize.value;
      final bytes = Uint8List(len);
      for (int i = 0; i < len; i++) {
        bytes[i] = ptr[i];
      }
      freePng(ptr);
      _pngCache[cacheKey] = bytes;
      return bytes;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outSize);
    }
  }

  /// Shell overlay icon (shortcut arrow, OneDrive badge, etc.) or null.
  static Uint8List? getFileOverlayPng(String path, int size) {
    final cacheKey = '$path:$size';
    if (_overlayCache.containsKey(cacheKey)) return _overlayCache[cacheKey];
    final getOverlayPng = _getOverlayPng;
    final freePng = _freePng;
    if (getOverlayPng == null || freePng == null) return null;

    final pathPtr = path.toNativeUtf16();
    final outSize = calloc<Int32>();
    try {
      final ptr = getOverlayPng(pathPtr, size, outSize);
      if (ptr == nullptr || outSize.value <= 0) {
        _overlayCache[cacheKey] = null;
        return null;
      }
      final len = outSize.value;
      final bytes = Uint8List(len);
      for (int i = 0; i < len; i++) {
        bytes[i] = ptr[i];
      }
      freePng(ptr);
      _overlayCache[cacheKey] = bytes;
      return bytes;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outSize);
    }
  }

  /// 云同步状态语义编码（-1 = 非云条目）：
  /// 0 仅联机 / 1 本地可用 / 2 固定保留 / 3 同步中 / 4 已排除（不同步）。
  static int getCloudStatus(String path) {
    final cached = _cloudStatusCache[path];
    if (cached != null) return cached;
    final getCloudStatus = _getCloudStatus;
    if (getCloudStatus == null) return -1;

    final pathPtr = path.toNativeUtf16();
    try {
      final status = getCloudStatus(pathPtr);
      _cloudStatusCache[path] = status;
      return status;
    } finally {
      calloc.free(pathPtr);
    }
  }

  static void clearCache() {
    _pngCache.clear();
    _overlayCache.clear();
    _cloudStatusCache.clear();
  }
}
