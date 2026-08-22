import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/file_operation_task.dart';

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
typedef _StartRestoreNative =
    Int32 Function(
      Pointer<Pointer<Utf16>> sourcePaths,
      Int32 sourceCount,
      Pointer<Pointer<Utf16>> destinationOverrides,
      Int32 collisionMode,
      Pointer<Int64> operationId,
    );
typedef _StartRestoreDart =
    int Function(
      Pointer<Pointer<Utf16>> sourcePaths,
      int sourceCount,
      Pointer<Pointer<Utf16>> destinationOverrides,
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
typedef _GetResultsNative =
    Int32 Function(Int64 operationId, Pointer<Pointer<Utf8>> outJson);
typedef _GetResultsDart =
    int Function(int operationId, Pointer<Pointer<Utf8>> outJson);
typedef _CloseAsyncNative = Int32 Function(Int64 operationId);
typedef _CloseAsyncDart = int Function(int operationId);
typedef _FreeUtf8Native = Void Function(Pointer<Utf8> ptr);
typedef _FreeUtf8Dart = void Function(Pointer<Utf8> ptr);
typedef _BuildSortKeyNative =
    Int32 Function(
      Pointer<Utf16> name,
      Pointer<Pointer<Uint8>> outKey,
      Pointer<Int32> outKeyLen,
    );
typedef _BuildSortKeyDart =
    int Function(
      Pointer<Utf16> name,
      Pointer<Pointer<Uint8>> outKey,
      Pointer<Int32> outKeyLen,
    );
typedef _FreeBytesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeBytesDart = void Function(Pointer<Uint8> ptr);

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
typedef _ShellExecuteNative =
    IntPtr Function(
      Pointer<Void> hwnd,
      Pointer<Utf16> verb,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      Int32 show,
    );
typedef _ShellExecuteDart =
    int Function(
      Pointer<Void> hwnd,
      Pointer<Utf16> verb,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      int show,
    );
typedef _OpenShellItemNative = Int32 Function(Pointer<Utf16> path);
typedef _OpenShellItemDart = int Function(Pointer<Utf16> path);

/// Windows Shell `IFileOperation` wrapper: copy/move/delete go through the
/// shell so they participate in the undo stack (FOF_ALLOWUNDO) and the shared
/// Recycle Bin, matching Explorer and other file managers.
class ShellFileOperation {
  static const int opCopy = 0;
  static const int opMove = 1;
  static const int opDelete = 2;

  static _RunDart? _run;
  static _StartAsyncDart? _startAsync;
  static _StartRestoreDart? _startRestore;
  static _PollAsyncDart? _pollAsync;
  static _CancelAsyncDart? _cancelAsync;
  static _GetResultsDart? _getResults;
  static _CloseAsyncDart? _closeAsync;
  static _FreeUtf8Dart? _freeUtf8;
  static _BuildSortKeyDart? _buildSortKey;
  static _FreeBytesDart? _freeCoTaskMemBytes;
  static _EmptyRecycleBinDart? _emptyRecycleBin;
  static _GetActiveWindowDart? _getActiveWindow;
  static _RestoreRecycleBinDart? _restoreRecycleBin;
  static _PickFolderDart? _pickFolder;
  static _FreeCoTaskMemDart? _freeCoTaskMem;
  static _ShellExecuteDart? _shellExecute;
  static _OpenShellItemDart? _openShellItem;
  static bool _tried = false;
  static bool _asyncTried = false;
  static bool _shellExecuteTried = false;
  static bool _openShellItemTried = false;

  /// Opens a virtual Shell item with its default Windows `open` verb.
  static bool openShellItem(String path) {
    if (!Platform.isWindows) return false;
    if (!_openShellItemTried) {
      _openShellItemTried = true;
      try {
        _openShellItem = DynamicLibrary.process()
            .lookupFunction<_OpenShellItemNative, _OpenShellItemDart>(
              'OpenShellItemW',
            );
      } on Object {
        _openShellItem = null;
      }
    }
    final nativeOpen = _openShellItem;
    if (nativeOpen != null && path.isNotEmpty) {
      final target = path.toNativeUtf16();
      try {
        return nativeOpen(target) == 0;
      } finally {
        calloc.free(target);
      }
    }

    if (!_shellExecuteTried) {
      _shellExecuteTried = true;
      try {
        _shellExecute = DynamicLibrary.open('shell32.dll')
            .lookupFunction<_ShellExecuteNative, _ShellExecuteDart>(
              'ShellExecuteW',
            );
      } on Object {
        _shellExecute = null;
      }
    }
    final execute = _shellExecute;
    if (execute == null || path.isEmpty) return false;

    final verb = 'open'.toNativeUtf16();
    final target = path.toNativeUtf16();
    try {
      return execute(nullptr, verb, target, nullptr, nullptr, 1) > 32;
    } finally {
      calloc.free(verb);
      calloc.free(target);
    }
  }

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

  /// Runs a copy via the shell worker and returns the per-item results
  /// reported by the native progress sink.
  static Future<List<FileOperationItemResult>> copyAsync(
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

  static Future<List<FileOperationItemResult>> moveAsync(
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

  static Future<List<FileOperationItemResult>> deleteAsync(
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

  static Future<List<FileOperationItemResult>> _runAsync(
    int operation,
    List<String> sources,
    String? destination,
    bool permanent, {
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (sources.isEmpty) return const [];
    _loadAsyncSymbols();
    final start = _startAsync;
    final poll = _pollAsync;
    final cancel = _cancelAsync;
    if (start == null || poll == null || cancel == null) {
      try {
        _runOperation(operation, sources, destination, permanent);
        onProgress?.call(1);
        return const [];
      } on FileSystemException catch (error) {
        throw ShellFileOperationException(
          _hrFromMessage(error.message),
          const [],
        );
      }
    }

    final sourcePtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> sourceArray = nullptr;
    final destinationPtr = destination == null
        ? nullptr
        : destination.toNativeUtf16();
    final operationId = calloc<Int64>();
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
        throw ShellFileOperationException(startHr, const []);
      }
      return await _awaitOperation(
        operationId.value,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    } finally {
      for (final ptr in sourcePtrs) {
        calloc.free(ptr);
      }
      if (sourceArray != nullptr) calloc.free(sourceArray);
      if (destinationPtr != nullptr) calloc.free(destinationPtr);
      calloc.free(operationId);
    }
  }

  /// Runs a Recycle Bin restore on the native worker thread and returns the
  /// per-item results reported by the progress sink. Falls back to the
  /// synchronous path when the async native symbols are unavailable.
  static Future<List<FileOperationItemResult>> restoreRecycleBinAsync(
    List<String> sourcePaths, {
    List<String?>? destinations,
    bool keepBothOnCollision = false,
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    if (sourcePaths.isEmpty) return const [];
    _loadAsyncSymbols();
    final start = _startRestore;
    final poll = _pollAsync;
    final cancel = _cancelAsync;
    if (start == null || poll == null || cancel == null) {
      try {
        restoreRecycleBin(
          sourcePaths,
          destinations: destinations,
          keepBothOnCollision: keepBothOnCollision,
        );
        onProgress?.call(1);
        return const [];
      } on FileSystemException catch (error) {
        throw ShellFileOperationException(
          _hrFromMessage(error.message),
          const [],
        );
      }
    }

    final sourcePtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> sourceArray = nullptr;
    final overridePtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> overrideArray = nullptr;
    final hasOverrides =
        destinations != null && destinations.any((dest) => dest != null);
    final operationId = calloc<Int64>();
    try {
      sourceArray = calloc<Pointer<Utf16>>(sourcePaths.length);
      for (var i = 0; i < sourcePaths.length; i++) {
        final ptr = sourcePaths[i].toNativeUtf16();
        sourcePtrs.add(ptr);
        sourceArray[i] = ptr;
      }
      if (hasOverrides) {
        overrideArray = calloc<Pointer<Utf16>>(sourcePaths.length);
        for (var i = 0; i < sourcePaths.length; i++) {
          final dest = destinations[i];
          if (dest != null) {
            final ptr = dest.toNativeUtf16();
            overridePtrs.add(ptr);
            overrideArray[i] = ptr;
          }
        }
      }
      final startHr = start(
        sourceArray,
        sourcePaths.length,
        overrideArray,
        keepBothOnCollision ? 1 : 0,
        operationId,
      );
      if (startHr != 0) {
        throw ShellFileOperationException(startHr, const []);
      }
      return await _awaitOperation(
        operationId.value,
        cancelRequested: cancelRequested,
        onProgress: onProgress,
      );
    } finally {
      for (final ptr in sourcePtrs) {
        calloc.free(ptr);
      }
      calloc.free(sourceArray);
      for (final ptr in overridePtrs) {
        calloc.free(ptr);
      }
      if (overrideArray != nullptr) calloc.free(overrideArray);
      calloc.free(operationId);
    }
  }

  /// Polls a running native operation to its terminal state, forwarding
  /// progress and translating failures. Consumes and returns the per-item
  /// results when the operation finishes.
  static Future<List<FileOperationItemResult>> _awaitOperation(
    int operationId, {
    bool Function()? cancelRequested,
    void Function(double progress)? onProgress,
  }) async {
    final poll = _pollAsync!;
    final cancel = _cancelAsync!;
    final status = calloc<Int32>();
    final progress = calloc<Int32>();
    final result = calloc<Int32>();
    var cancelSent = false;
    try {
      while (true) {
        final pollHr = poll(operationId, status, progress, result);
        if (pollHr != 0) {
          throw ShellFileOperationException(pollHr, _takeResults(operationId));
        }
        onProgress?.call((progress.value / 100).clamp(0, 1).toDouble());
        if (cancelRequested?.call() == true && !cancelSent) {
          cancel(operationId);
          cancelSent = true;
        }

        if (status.value == 2) return _takeResults(operationId);
        if (status.value == 4) {
          throw const FileOperationCancelledException();
        }
        if (status.value == 3) {
          throw ShellFileOperationException(
            result.value,
            _takeResults(operationId),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _closeOperation(operationId);
      calloc.free(status);
      calloc.free(progress);
      calloc.free(result);
    }
  }

  /// Fetches and decodes the per-item results of a finished operation.
  /// Consumes the native buffer once; later calls return an empty list.
  static List<FileOperationItemResult> _takeResults(int operationId) {
    final getResults = _getResults;
    final free = _freeUtf8;
    if (getResults == null || free == null) return const [];
    final out = calloc<Pointer<Utf8>>();
    try {
      final hr = getResults(operationId, out);
      if (hr != 0 || out.value == nullptr) return const [];
      final text = out.value.toDartString();
      free(out.value);
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> &&
              item['path'] is String &&
              item['hr'] is int)
            FileOperationItemResult(
              item['path'] as String,
              item['hr'] as int,
              createdPath: item['createdPath'] as String?,
              recycledPath: item['recycledPath'] as String?,
            ),
      ];
    } on FormatException catch (error) {
      debugPrint('[ShellOp] takeResults JSON error: ${error.message}');
      return const [];
    } finally {
      calloc.free(out);
    }
  }

  static void _closeOperation(int operationId) {
    _closeAsync?.call(operationId);
  }

  static int _hrFromMessage(String message) {
    final match = RegExp(r'hr=0x([0-9a-fA-F]+)').firstMatch(message);
    return match == null ? -1 : int.parse(match.group(1)!, radix: 16);
  }

  static bool _sortKeyTried = false;

  /// Builds the Windows natural-sort key for a file name, identical to the
  /// one the directory enumerator produces. Returns null when the native
  /// symbol is unavailable (tests) or the name produces no key.
  static Uint8List? buildNameSortKey(String name) {
    if (!_sortKeyTried) {
      _sortKeyTried = true;
      try {
        _buildSortKey = DynamicLibrary.process()
            .lookupFunction<_BuildSortKeyNative, _BuildSortKeyDart>(
              'InfDirBuildNameSortKeyW',
            );
        _freeCoTaskMemBytes = DynamicLibrary.process()
            .lookupFunction<_FreeBytesNative, _FreeBytesDart>('FreeCoTaskMemW');
      } on Object {
        _buildSortKey = null;
        _freeCoTaskMemBytes = null;
      }
    }
    final fn = _buildSortKey;
    final free = _freeCoTaskMemBytes;
    if (fn == null || free == null || name.isEmpty) return null;

    final namePtr = name.toNativeUtf16();
    final outKey = calloc<Pointer<Uint8>>();
    final outLen = calloc<Int32>();
    try {
      final hr = fn(namePtr, outKey, outLen);
      if (hr != 0 || outKey.value == nullptr || outLen.value <= 0) {
        return null;
      }
      final result = Uint8List.fromList(outKey.value.asTypedList(outLen.value));
      free(outKey.value);
      return result;
    } finally {
      calloc.free(namePtr);
      calloc.free(outKey);
      calloc.free(outLen);
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
      _startRestore = library
          .lookupFunction<_StartRestoreNative, _StartRestoreDart>(
            'InfDirStartRestoreOperationW',
          );
      _pollAsync = library.lookupFunction<_PollAsyncNative, _PollAsyncDart>(
        'InfDirPollFileOperationW',
      );
      _cancelAsync = library
          .lookupFunction<_CancelAsyncNative, _CancelAsyncDart>(
            'InfDirCancelFileOperationW',
          );
      _getResults = library.lookupFunction<_GetResultsNative, _GetResultsDart>(
        'InfDirGetFileOperationResultsW',
      );
      _closeAsync = library.lookupFunction<_CloseAsyncNative, _CloseAsyncDart>(
        'InfDirCloseFileOperationW',
      );
      _freeUtf8 = library.lookupFunction<_FreeUtf8Native, _FreeUtf8Dart>(
        'FreeCoTaskMemW',
      );
    } on Object {
      _startAsync = null;
      _startRestore = null;
      _pollAsync = null;
      _cancelAsync = null;
      _getResults = null;
      _closeAsync = null;
      _freeUtf8 = null;
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

/// Failure of a whole shell file operation. Carries the overall HRESULT and
/// the per-item results reported by the native progress sink, so callers can
/// show exactly which paths failed.
class ShellFileOperationException implements Exception {
  const ShellFileOperationException(this.hr, this.items);

  final int hr;
  final List<FileOperationItemResult> items;

  String get message =>
      'Shell 文件操作失败 (hr=0x'
      '${hr.toUnsigned(32).toRadixString(16).toUpperCase()})';

  @override
  String toString() => message;
}
