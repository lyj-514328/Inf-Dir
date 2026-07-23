import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _GetIconIndexNative = Int32 Function(
    Pointer<Utf16> path, Uint32 attrs);
typedef _GetIconIndexDart = int Function(Pointer<Utf16> path, int attrs);

typedef _GetPngNative = Pointer<Uint8> Function(Int32 index, Pointer<Int32> outSize);
typedef _GetPngDart = Pointer<Uint8> Function(int index, Pointer<Int32> outSize);

typedef _FreePngNative = Void Function(Pointer<Uint8> ptr);
typedef _FreePngDart = void Function(Pointer<Uint8> ptr);

class IconService {
  static final _GetIconIndexDart _getIndex = DynamicLibrary.process()
      .lookupFunction<_GetIconIndexNative, _GetIconIndexDart>('GetFileIconIndexW');

  static final _GetPngDart _getPng = DynamicLibrary.process()
      .lookupFunction<_GetPngNative, _GetPngDart>('GetIconPngByIndexW');

  static final _FreePngDart _freePng = DynamicLibrary.process()
      .lookupFunction<_FreePngNative, _FreePngDart>('FreeIconPngW');

  static const int _attrDirectory = 0x10; // FILE_ATTRIBUTE_DIRECTORY
  static const int _attrNormal = 0x80; // FILE_ATTRIBUTE_NORMAL

  static final Map<String, int> _indexCache = {};
  static final Map<int, Uint8List> _pngCache = {};

  static int getIconIndex(String path, bool isDirectory) {
    final cached = _indexCache[path];
    if (cached != null) return cached;

    final ptr = path.toNativeUtf16();
    try {
      final idx = _getIndex(ptr, isDirectory ? _attrDirectory : _attrNormal);
      _indexCache[path] = idx;
      return idx;
    } finally {
      calloc.free(ptr);
    }
  }

  static Uint8List? getIconPng(int iconIndex) {
    if (iconIndex < 0) return null;
    final cached = _pngCache[iconIndex];
    if (cached != null) return cached;

    final outSize = calloc<Int32>();
    try {
      final ptr = _getPng(iconIndex, outSize);
      if (ptr == nullptr || outSize.value <= 0) return null;

      final size = outSize.value;
      final bytes = Uint8List(size);
      for (int i = 0; i < size; i++) {
        bytes[i] = ptr[i];
      }
      _freePng(ptr);
      _pngCache[iconIndex] = bytes;
      return bytes;
    } finally {
      calloc.free(outSize);
    }
  }

  static void clearCache() {
    _indexCache.clear();
    _pngCache.clear();
  }
}
