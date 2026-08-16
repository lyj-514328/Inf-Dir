import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetImageNative =
    Pointer<Uint8> Function(
      Pointer<Utf16> path,
      Int32 size,
      Int32 flags,
      Pointer<Int32> outSize,
    );
typedef _GetImageDart =
    Pointer<Uint8> Function(
      Pointer<Utf16> path,
      int size,
      int flags,
      Pointer<Int32> outSize,
    );
typedef _FreePngNative = Void Function(Pointer<Uint8> ptr);
typedef _FreePngDart = void Function(Pointer<Uint8> ptr);

final _GetImageDart? _getImage = _lookupImage();
final _FreePngDart? _freePng = _lookupFreePng();

_GetImageDart? _lookupImage() {
  try {
    return DynamicLibrary.process()
        .lookupFunction<_GetImageNative, _GetImageDart>('GetFileImagePngW');
  } on ArgumentError {
    return null;
  }
}

_FreePngDart? _lookupFreePng() {
  try {
    return DynamicLibrary.process()
        .lookupFunction<_FreePngNative, _FreePngDart>('FreeIconPngW');
  } on ArgumentError {
    return null;
  }
}

Uint8List? extractFileImagePng(String path, int size, int flags) {
  final getImage = _getImage;
  final freePng = _freePng;
  if (getImage == null || freePng == null) return null;

  final pathPtr = path.toNativeUtf16();
  final outSize = calloc<Int32>();
  try {
    final ptr = getImage(pathPtr, size, flags, outSize);
    if (ptr == nullptr || outSize.value <= 0) return null;
    final len = outSize.value;
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = ptr[i];
    }
    freePng(ptr);
    return bytes;
  } finally {
    calloc.free(pathPtr);
    calloc.free(outSize);
  }
}
