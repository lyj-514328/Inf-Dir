import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _GetPngNative = Pointer<Uint8> Function(
    Pointer<Utf16> path, Int32 size, Pointer<Int32> outSize);
typedef _GetPngDart = Pointer<Uint8> Function(
    Pointer<Utf16> path, int size, Pointer<Int32> outSize);

typedef _FreePngNative = Void Function(Pointer<Uint8> ptr);
typedef _FreePngDart = void Function(Pointer<Uint8> ptr);

class IconService {
  static final _GetPngDart _getPng = DynamicLibrary.process()
      .lookupFunction<_GetPngNative, _GetPngDart>('GetFileIconPngW');

  static final _FreePngDart _freePng = DynamicLibrary.process()
      .lookupFunction<_FreePngNative, _FreePngDart>('FreeIconPngW');

  static final Map<String, Uint8List> _pngCache = {};

  static Uint8List? getFileIconPng(String path, bool isDirectory, int size) {
    final cacheKey = '${isDirectory ? 'D' : 'F'}:$path:$size';
    final cached = _pngCache[cacheKey];
    if (cached != null) return cached;

    final pathPtr = path.toNativeUtf16();
    final outSize = calloc<Int32>();
    try {
      final ptr = _getPng(pathPtr, size, outSize);
      if (ptr == nullptr || outSize.value <= 0) return null;
      final len = outSize.value;
      final bytes = Uint8List(len);
      for (int i = 0; i < len; i++) {
        bytes[i] = ptr[i];
      }
      _freePng(ptr);
      _pngCache[cacheKey] = bytes;
      return bytes;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outSize);
    }
  }

  static void clearCache() {
    _pngCache.clear();
  }
}
