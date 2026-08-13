import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RunNative = Int32 Function(
  Int32 operation,
  Pointer<Pointer<Utf16>> sourcePaths,
  Int32 sourceCount,
  Pointer<Utf16> destinationFolder,
  Int32 permanentDelete,
);

typedef _RunDart = int Function(
  int operation,
  Pointer<Pointer<Utf16>> sourcePaths,
  int sourceCount,
  Pointer<Utf16> destinationFolder,
  int permanentDelete,
);

/// Windows Shell `IFileOperation` wrapper: copy/move/delete go through the
/// shell so they participate in the undo stack (FOF_ALLOWUNDO) and the shared
/// Recycle Bin, matching Explorer and other file managers.
class ShellFileOperation {
  static const int opCopy = 0;
  static const int opMove = 1;
  static const int opDelete = 2;

  static _RunDart? _run;
  static bool _tried = false;

  /// Whether the native `RunFileOperationW` symbol is available. False when
  /// running under the Dart VM (tests) or on non-Windows, so callers fall back
  /// to `dart:io`.
  static bool get isAvailable {
    if (!_tried) {
      _tried = true;
      try {
        _run = DynamicLibrary.process()
            .lookupFunction<_RunNative, _RunDart>('RunFileOperationW');
      } on Object {
        _run = null;
      }
    }
    return _run != null;
  }

  static void _runOperation(
    int operation,
    List<String> sources,
    String? destination,
    bool permanent,
  ) {
    if (sources.isEmpty) return;
    final fn = _run;
    if (fn == null) {
      throw FileSystemException('Shell file operation unavailable');
    }

    final sourcePtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> sourceArray = nullptr;
    final destinationPtr =
        destination == null ? nullptr : destination.toNativeUtf16();

    try {
      sourceArray = calloc<Pointer<Utf16>>(sources.length);
      for (int i = 0; i < sources.length; i++) {
        sourcePtrs.add(sources[i].toNativeUtf16());
        sourceArray[i] = sourcePtrs[i];
      }

      final hr = fn(
        operation,
        sourceArray,
        sources.length,
        destinationPtr,
        permanent ? 1 : 0,
      );
      if (hr != 0) {
        throw FileSystemException(
          'Shell file operation failed (hr=0x${hr.toRadixString(16)})',
        );
      }
    } finally {
      for (final ptr in sourcePtrs) {
        calloc.free(ptr);
      }
      if (sourceArray != nullptr) calloc.free(sourceArray);
      if (destinationPtr != nullptr) calloc.free(destinationPtr);
    }
  }

  static void copy(List<String> sources, String destination) =>
      _runOperation(opCopy, sources, destination, false);

  static void move(List<String> sources, String destination) =>
      _runOperation(opMove, sources, destination, false);

  static void delete(List<String> sources, {bool permanent = false}) =>
      _runOperation(opDelete, sources, null, permanent);
}
