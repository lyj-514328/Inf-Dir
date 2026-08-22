import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'thumbnail_cache.dart';
import 'thumbnail_ffi.dart';
import 'thumbnail_worker.dart';

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
  static const int imageIconOnly = 0x1;
  static const int imageThumbnailOnly = 0x2;
  static const int imageInCacheOnly = 0x4;
  static const double thumbnailMinLogicalSize = 34;

  static final _GetPngDart? _getPng = _lookupPng('GetFileIconPngW');
  static final _GetPngDart? _getOverlayPng = _lookupPng('GetFileOverlayPngW');
  static final _GetCloudStatusDart? _getCloudStatus = _lookupCloudStatus();
  static final _FreePngDart? _freePng = _lookupFreePng();

  static final Map<String, Uint8List> _pngCache = {};
  static final Map<String, Uint8List?> _overlayCache = {};
  static final Map<String, int> _cloudStatusCache = {};
  static final Map<String, Future<Uint8List?>> _inflightThumbs = {};
  static final Set<String> _failedThumbs = {};
  static ThumbnailCache thumbs = ThumbnailCache();

  static bool wantsThumbnail(double logicalSize) =>
      logicalSize >= thumbnailMinLogicalSize;

  static String thumbnailCacheKey({
    required String path,
    required int size,
    DateTime? modified,
  }) => ThumbnailCache.cacheKey(path: path, size: size, modified: modified);

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
      final bytes = _copyPng(ptr, outSize.value);
      freePng(ptr);
      _pngCache[cacheKey] = bytes;
      return bytes;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outSize);
    }
  }

  /// Resolves Shell namespace icons off the UI isolate. Third-party namespace
  /// extensions can block both Shell image APIs while starting up.
  static Future<Uint8List?> getFileIconPngAsync(
    String path,
    bool isDirectory,
    int size,
  ) async {
    final cacheKey = '${isDirectory ? 'D' : 'F'}:$path:$size';
    final cached = _pngCache[cacheKey];
    if (cached != null) return cached;

    final bytes = path.startsWith(r'\\SHELL\')
        ? await ThumbnailWorker.instance.extract(
            path: path,
            size: size,
            flags: imageIconOnly,
          )
        : getFileIconPng(path, isDirectory, size);
    if (bytes != null) _pngCache[cacheKey] = bytes;
    return bytes;
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
      final bytes = _copyPng(ptr, outSize.value);
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

  static Uint8List? peekThumbnail(String cacheKey) => thumbs.getMemory(cacheKey);

  static Uint8List? extractImagePng(String path, int size, int flags) {
    return extractFileImagePng(path, size, flags);
  }

  static Future<Uint8List?> getThumbnailPng({
    required String path,
    required int size,
    DateTime? modified,
  }) {
    final key = thumbnailCacheKey(path: path, size: size, modified: modified);
    final memory = thumbs.getMemory(key);
    if (memory != null) return Future<Uint8List?>.value(memory);
    if (_failedThumbs.contains(key)) return Future<Uint8List?>.value(null);

    return _inflightThumbs.putIfAbsent(key, () async {
      try {
        final disk = thumbs.getDisk(key);
        if (disk != null) return disk;
        final bytes = await ThumbnailWorker.instance.extract(
          path: path,
          size: size,
          flags: imageThumbnailOnly,
        );
        if (bytes == null || bytes.isEmpty) {
          _failedThumbs.add(key);
          return null;
        }
        thumbs.putMemory(key, bytes);
        await thumbs.putDisk(key, bytes);
        return bytes;
      } finally {
        _inflightThumbs.remove(key);
      }
    });
  }

  static void clearCache() {
    _pngCache.clear();
    _overlayCache.clear();
    _cloudStatusCache.clear();
    clearThumbnailCache();
  }

  static void clearThumbnailCache() {
    _inflightThumbs.clear();
    _failedThumbs.clear();
    thumbs.clear();
  }

  static void debugReset({ThumbnailCache? cache}) {
    _pngCache.clear();
    _overlayCache.clear();
    _cloudStatusCache.clear();
    _inflightThumbs.clear();
    _failedThumbs.clear();
    thumbs = cache ?? ThumbnailCache();
  }

  static Uint8List _copyPng(Pointer<Uint8> ptr, int len) {
    final bytes = Uint8List(len);
    for (int i = 0; i < len; i++) {
      bytes[i] = ptr[i];
    }
    return bytes;
  }
}
