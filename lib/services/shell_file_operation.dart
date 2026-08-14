import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RunNative =
    Int32 Function(
      Int32 operation,
      Pointer<Pointer<Utf16>> sourcePaths,
      Int32 sourceCount,
      Pointer<Utf16> destinationFolder,
      Int32 permanentDelete,
    );

typedef _RunDart =
    int Function(
      int operation,
      Pointer<Pointer<Utf16>> sourcePaths,
      int sourceCount,
      Pointer<Utf16> destinationFolder,
      int permanentDelete,
    );

typedef _StartAsyncNative =
    Int32 Function(
      Int32 operation,
      Pointer<Pointer<Utf16>> sourcePaths,
      Int32 sourceCount,
      Pointer<Utf16> destinationFolder,
      Int32 permanentDelete,
      Int32 collisionMode,
      Pointer<Int64> operationId,
    );
typedef _StartAsyncDart =
    int Function(
      int operation,
      Pointer<Pointer<Utf16>> sourcePaths,
      int sourceCount,
      Pointer<Utf16> destinationFolder,
      int permanentDelete,
      int collisionMode,
      Pointer<Int64> operationId,
    );
typedef _PollAsyncNative =
    Int32 Function(
      Int64 operationId,
      Pointer<Int32> status,
      Pointer<Int32> progress,
      Pointer<Int32> result,
    );
typedef _PollAsyncDart =
    int Function(
      int operationId,
      Pointer<Int32> status,
      Pointer<Int32> progress,
      Pointer<Int32> result,
    );
typedef _CancelAsyncNative = Int32 Function(Int64 operationId);
typedef _CancelAsyncDart = int Function(int operationId);

typedef _EmptyRecycleBinNative = Int32 Function(IntPtr owner);
typedef _EmptyRecycleBinDart = int Function(int owner);
typedef _GetActiveWindowNative = IntPtr Function();
typedef _GetActiveWindowDart = int Function();
typedef _RestoreRecycleBinNative =
    Int32 Function(
      IntPtr owner,
      Pointer<Pointer<Utf16>> sourcePaths,
      Int32 sourceCount,
      Pointer<Pointer<Utf16>> destinationOverrides,
      Int32 collisionMode,
    );
typedef _RestoreRecycleBinDart =
    int Function(
      int owner,
      Pointer<Pointer<Utf16>> sourcePaths,
      int sourceCount,
      Pointer<Pointer<Utf16>> destinationOverrides,
      int collisionMode,
    );
typedef _PickFolderNative =
    Int32 Function(
      IntPtr owner,
      Pointer<Utf16> initialPath,
      Pointer<Pointer<Utf16>> outPath,
    );
typedef _PickFolderDart =
    int Function(
      int owner,
      Pointer<Utf16> initialPath,
      Pointer<Pointer<Utf16>> outPath,
    );
typedef _FreeCoTaskMemNative = Void Function(Pointer<Utf16> ptr);
typedef _FreeCoTaskMemDart = void Function(Pointer<Utf16> ptr);

/// Windows Shell `IFileOperation` wrapper: copy/move/delete go through the
/// shell so they participate in the undo stack (FOF_ALLOWUNDO) and the shared
/// Recycle Bin, matching Explorer and other file managers.
class ShellFileOperation {
  static const int opCopy = 0;
  static const int opMove = 1;
  static const int opDelete = 2;

  static _RunDart? _run;
  static _StartAsyncDart? _startAsync;
  static _PollAsyncDart? _pollAsync;
  static _CancelAsyncDart? _cancelAsync;
  static _EmptyRecycleBinDart? _emptyRecycleBin;
  static _GetActiveWindowDart? _getActiveWindow;
  static _RestoreRecycleBinDart? _restoreRecycleBin;
  static _PickFolderDart? _pickFolder;
  static _FreeCoTaskMemDart? _freeCoTaskMem;
  static bool _tried = false;
  static bool _asyncTried = false;

  /// Whether the native `RunFileOperationW` symbol is available. False when
  /// running under the Dart VM (tests) or on non-Windows, so callers fall back
  /// to `dart:io`.
  static bool get isAvailable {
    if (!_tried) {
      _tried = true;
      try {
        _run = DynamicLibrary.process().lookupFunction<_RunNative, _RunDart>(
          'RunFileOperationW',
        );
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
    final destinationPtr = destination == null
        ? nullptr
        : destination.toNativeUtf16();

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
          'Shell file operation failed '
          '(hr=0x${hr.toUnsigned(32).toRadixString(16)})',
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

  static Future<void> copyAsync(
    List<String> sources,
    String destination, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) => _runAsync(
    opCopy,
    sources,
    destination,
    false,
    keepBothOnCollision: keepBothOnCollision,
    cancelRequested: cancelRequested,
    onProgress: onProgress,
  );

  static Future<void> moveAsync(
    List<String> sources,
    String destination, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) => _runAsync(
    opMove,
    sources,
    destination,
    false,
    keepBothOnCollision: keepBothOnCollision,
    cancelRequested: cancelRequested,
    onProgress: onProgress,
  );

  static Future<void> deleteAsync(
    List<String> sources, {
    bool permanent = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) => _runAsync(
    opDelete,
    sources,
    null,
    permanent,
    cancelRequested: cancelRequested,
    onProgress: onProgress,
  );

  static Future<void> _runAsync(
    int operation,
    List<String> sources,
    String? destination,
    bool permanent, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (sources.isEmpty) return;
    _loadAsyncSymbols();
    final start = _startAsync;
    final poll = _pollAsync;
    final cancel = _cancelAsync;
    if (start == null || poll == null || cancel == null) {
      _runOperation(operation, sources, destination, permanent);
      onProgress?.call(1);
      return;
    }

    final sourcePtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> sourceArray = nullptr;
    final destinationPtr = destination == null
        ? nullptr
        : destination.toNativeUtf16();
    final operationId = calloc<Int64>();
    final status = calloc<Int32>();
    final progress = calloc<Int32>();
    final result = calloc<Int32>();
    var cancelSent = false;
    try {
      sourceArray = calloc<Pointer<Utf16>>(sources.length);
      for (var i = 0; i < sources.length; i++) {
        final ptr = sources[i].toNativeUtf16();
        sourcePtrs.add(ptr);
        sourceArray[i] = ptr;
      }
      final startHr = start(
        operation,
        sourceArray,
        sources.length,
        destinationPtr,
        permanent ? 1 : 0,
        keepBothOnCollision ? 1 : 0,
        operationId,
      );
      if (startHr != 0) {
        throw FileSystemException(
          'Failed to start shell file operation '
          '(hr=0x${startHr.toUnsigned(32).toRadixString(16)})',
        );
      }

      while (true) {
        final pollHr = poll(operationId.value, status, progress, result);
        if (pollHr != 0) {
          throw FileSystemException(
            'Failed to poll shell file operation '
            '(hr=0x${pollHr.toUnsigned(32).toRadixString(16)})',
          );
        }
        onProgress?.call((progress.value / 100).clamp(0, 1).toDouble());
        if (cancelRequested?.call() == true && !cancelSent) {
          cancel(operationId.value);
          cancelSent = true;
        }

        if (status.value == 2) return;
        if (status.value == 4) {
          throw const FileOperationCancelledException();
        }
        if (status.value == 3) {
          throw FileSystemException(
            'Shell file operation failed '
            '(hr=0x${result.value.toUnsigned(32).toRadixString(16)})',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      for (final ptr in sourcePtrs) {
        calloc.free(ptr);
      }
      if (sourceArray != nullptr) calloc.free(sourceArray);
      if (destinationPtr != nullptr) calloc.free(destinationPtr);
      calloc.free(operationId);
      calloc.free(status);
      calloc.free(progress);
      calloc.free(result);
    }
  }

  static void _loadAsyncSymbols() {
    if (_asyncTried) return;
    _asyncTried = true;
    try {
      final library = DynamicLibrary.process();
      _startAsync = library.lookupFunction<_StartAsyncNative, _StartAsyncDart>(
        'InfDirStartFileOperationW',
      );
      _pollAsync = library.lookupFunction<_PollAsyncNative, _PollAsyncDart>(
        'InfDirPollFileOperationW',
      );
      _cancelAsync = library
          .lookupFunction<_CancelAsyncNative, _CancelAsyncDart>(
            'InfDirCancelFileOperationW',
          );
    } on Object {
      _startAsync = null;
      _pollAsync = null;
      _cancelAsync = null;
    }
  }

  static void emptyRecycleBin() {
    if (!Platform.isWindows) {
      throw const FileSystemException(
        'Recycle Bin is only available on Windows',
      );
    }
    _emptyRecycleBin ??= DynamicLibrary.process()
        .lookupFunction<_EmptyRecycleBinNative, _EmptyRecycleBinDart>(
          'EmptyRecycleBinW',
        );
    _getActiveWindow ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
          'GetActiveWindow',
        );
    final hr = _emptyRecycleBin!(_getActiveWindow!());
    if (hr != 0) {
      throw FileSystemException(
        'Failed to empty Recycle Bin '
        '(hr=0x${hr.toUnsigned(32).toRadixString(16)})',
      );
    }
  }

  /// Restores Recycle Bin items to their original directories. When
  /// [destinations] is provided it must match [sourcePaths] in length: a
  /// non-null entry replaces the item's original directory (used when the
  /// original folder no longer exists). [keepBothOnCollision] asks the Shell
  /// to rename the restored item when a same-named item already exists;
  /// otherwise the Shell silently replaces it.
  static void restoreRecycleBin(
    List<String> sourcePaths, {
    List<String?>? destinations,
    bool keepBothOnCollision = false,
  }) {
    if (sourcePaths.isEmpty) return;
    if (destinations != null && destinations.length != sourcePaths.length) {
      throw ArgumentError('destinations must match sourcePaths length');
    }
    if (!Platform.isWindows) {
      throw const FileSystemException(
        'Recycle Bin is only available on Windows',
      );
    }
    _restoreRecycleBin ??= DynamicLibrary.process()
        .lookupFunction<_RestoreRecycleBinNative, _RestoreRecycleBinDart>(
          'RestoreRecycleBinItemsW',
        );

    final sourcePtrs = <Pointer<Utf16>>[];
    final sourceArray = calloc<Pointer<Utf16>>(sourcePaths.length);
    final overridePtrs = <Pointer<Utf16>>[];
    // `hasOverride` promotes `destinations` to non-null inside the `if`, and
    // `overrideArray` may still hold the null `Pointer` sentinel at runtime.
    final hasOverride =
        destinations != null && destinations.any((dest) => dest != null);
    final overrideArray = hasOverride
        ? calloc<Pointer<Utf16>>(sourcePaths.length)
        : nullptr;
    if (hasOverride) {
      for (var i = 0; i < sourcePaths.length; i++) {
        final dest = destinations[i];
        if (dest != null) {
          final destPtr = dest.toNativeUtf16();
          overridePtrs.add(destPtr);
          overrideArray[i] = destPtr;
        }
      }
    }
    try {
      for (var i = 0; i < sourcePaths.length; i++) {
        final ptr = sourcePaths[i].toNativeUtf16();
        sourcePtrs.add(ptr);
        sourceArray[i] = ptr;
      }
      _getActiveWindow ??= DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
            'GetActiveWindow',
          );
      final hr = _restoreRecycleBin!(
        _getActiveWindow!(),
        sourceArray,
        sourcePaths.length,
        overrideArray,
        keepBothOnCollision ? 1 : 0,
      );
      if (hr != 0) {
        throw FileSystemException(
          'Restore from Recycle Bin failed '
          '(hr=0x${hr.toUnsigned(32).toRadixString(16)})',
        );
      }
    } finally {
      for (final ptr in sourcePtrs) {
        calloc.free(ptr);
      }
      calloc.free(sourceArray);
      for (final ptr in overridePtrs) {
        calloc.free(ptr);
      }
      if (overrideArray != nullptr) calloc.free(overrideArray);
    }
  }

  /// Shows the native folder-picker dialog and returns the chosen path, or
  /// null when the user cancels.
  static String? pickFolder({String? initialPath}) {
    if (!Platform.isWindows) {
      throw const FileSystemException(
        'Folder picker is only available on Windows',
      );
    }
    _pickFolder ??= DynamicLibrary.process()
        .lookupFunction<_PickFolderNative, _PickFolderDart>('PickFolderW');
    _freeCoTaskMem ??= DynamicLibrary.process()
        .lookupFunction<_FreeCoTaskMemNative, _FreeCoTaskMemDart>(
          'FreeCoTaskMemW',
        );
    _getActiveWindow ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
          'GetActiveWindow',
        );

    final initialPtr = initialPath?.toNativeUtf16();
    final outPath = calloc<Pointer<Utf16>>();
    try {
      final hr = _pickFolder!(
        _getActiveWindow!(),
        initialPtr ?? nullptr,
        outPath,
      );
      // HRESULT_FROM_WIN32(ERROR_CANCELLED): user dismissed the dialog.
      if (hr == 0x800704C7) return null;
      if (hr != 0) {
        throw FileSystemException(
          'Failed to pick folder '
          '(hr=0x${hr.toUnsigned(32).toRadixString(16)})',
        );
      }
      final result = outPath.value;
      if (result == nullptr) return null;
      final path = result.toDartString();
      _freeCoTaskMem!(result);
      return path;
    } finally {
      if (initialPtr != null) calloc.free(initialPtr);
      calloc.free(outPath);
    }
  }
}

class FileOperationCancelledException implements Exception {
  const FileOperationCancelledException();
}
