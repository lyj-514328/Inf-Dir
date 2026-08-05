import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _AssocQueryStringNative =
    Int32 Function(
      Uint32 flags,
      Int32 stringType,
      Pointer<Utf16> association,
      Pointer<Utf16> extra,
      Pointer<Utf16> output,
      Pointer<Uint32> outputLength,
    );

typedef _AssocQueryStringDart =
    int Function(
      int flags,
      int stringType,
      Pointer<Utf16> association,
      Pointer<Utf16> extra,
      Pointer<Utf16> output,
      Pointer<Uint32> outputLength,
    );

abstract final class MimeTypeService {
  static const int _assocStrContentType = 14;
  static const int _bufferLength = 256;

  static final _query = DynamicLibrary.open('shlwapi.dll')
      .lookupFunction<_AssocQueryStringNative, _AssocQueryStringDart>(
        'AssocQueryStringW',
      );

  static final Map<String, String?> _cache = {};

  /// Returns the Content Type registered by Windows for the file extension.
  /// This is association metadata, not content sniffing.
  static String? forPath(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    if (extension.isEmpty) return null;
    return _cache.putIfAbsent(extension, () => _forExtension(extension));
  }

  static String? _forExtension(String extension) {
    final association = extension.toNativeUtf16();
    final output = calloc<Uint16>(_bufferLength).cast<Utf16>();
    final outputLength = calloc<Uint32>()..value = _bufferLength;
    try {
      final result = _query(
        0,
        _assocStrContentType,
        association,
        nullptr.cast<Utf16>(),
        output,
        outputLength,
      );
      if (result != 0 || outputLength.value <= 1) return null;
      final value = output.toDartString().trim().toLowerCase();
      return value.isEmpty ? null : value;
    } finally {
      calloc.free(association);
      calloc.free(output);
      calloc.free(outputLength);
    }
  }
}
