import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _ShowMenuNative = Int32 Function(
    IntPtr hwnd,
    Pointer<Utf16> folderPath,
    Pointer<Pointer<Utf16>> selectedPaths,
    Int32 selectedCount,
    Int32 x,
    Int32 y,
    Pointer<Pointer<Utf16>> interceptVerbs,
    Int32 interceptCount,
    Pointer<Utf16> verbOut,
    Int32 verbOutCch);

typedef _ShowMenuDart = int Function(
    int hwnd,
    Pointer<Utf16> folderPath,
    Pointer<Pointer<Utf16>> selectedPaths,
    int selectedCount,
    int x,
    int y,
    Pointer<Pointer<Utf16>> interceptVerbs,
    int interceptCount,
    Pointer<Utf16> verbOut,
    int verbOutCch);

typedef _GetActiveWindowNative = IntPtr Function();
typedef _GetActiveWindowDart = int Function();

typedef _ClientToScreenNative = Int32 Function(IntPtr hWnd, Pointer<Int32> lpPoint);
typedef _ClientToScreenDart = int Function(int hWnd, Pointer<Int32> lpPoint);

class ShellContextMenu {
  static final _ShowMenuDart _showMenu = _load();
  static final _GetActiveWindowDart _getActiveWindow =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
              'GetActiveWindow');
  static final _ClientToScreenDart _clientToScreen =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<_ClientToScreenNative, _ClientToScreenDart>(
              'ClientToScreen');

  static _ShowMenuDart _load() {
    return DynamicLibrary.process()
        .lookupFunction<_ShowMenuNative, _ShowMenuDart>('ShowShellContextMenuW');
  }

  /// Verbs that Dart handles internally (not invoked by the shell).
  static const interceptVerbs = ['rename', 'open', 'explore'];

  /// Converts client-area logical coordinates to screen physical coordinates.
  static (int, int) toScreenCoords(double logicalX, double logicalY, double dpr) {
    final hwnd = _getActiveWindow();
    // POINT struct: two int32 (x, y)
    final point = calloc<Int32>(2);
    point[0] = (logicalX * dpr).round();
    point[1] = (logicalY * dpr).round();
    _clientToScreen(hwnd, point);
    final sx = point[0];
    final sy = point[1];
    calloc.free(point);
    return (sx, sy);
  }

  /// Shows the native Windows Shell context menu.
  ///
  /// [screenX] and [screenY] must be in screen physical pixel coordinates.
  /// Returns the command verb, or null if cancelled.
  static String? show({
    required String folderPath,
    required List<String> selectedPaths,
    required int screenX,
    required int screenY,
  }) {
    final hwnd = _getActiveWindow();
    final folderPtr = folderPath.toNativeUtf16();
    final verbBuf = calloc<Uint16>(256).cast<Utf16>();

    Pointer<Pointer<Utf16>> pathsArray = nullptr;
    final pathPtrs = <Pointer<Utf16>>[];

    Pointer<Pointer<Utf16>> interceptArray = nullptr;
    final interceptPtrs = <Pointer<Utf16>>[];

    try {
      if (selectedPaths.isNotEmpty) {
        pathsArray = calloc<Pointer<Utf16>>(selectedPaths.length);
        for (int i = 0; i < selectedPaths.length; i++) {
          pathPtrs.add(selectedPaths[i].toNativeUtf16());
          pathsArray[i] = pathPtrs[i];
        }
      }

      interceptArray = calloc<Pointer<Utf16>>(interceptVerbs.length);
      for (int i = 0; i < interceptVerbs.length; i++) {
        interceptPtrs.add(interceptVerbs[i].toNativeUtf16());
        interceptArray[i] = interceptPtrs[i];
      }

      final hr = _showMenu(
        hwnd,
        folderPtr,
        pathsArray,
        selectedPaths.length,
        screenX,
        screenY,
        interceptArray,
        interceptVerbs.length,
        verbBuf,
        256,
      );

      if (hr == 0) {
        final verb = verbBuf.toDartString();
        return verb.isEmpty ? null : verb;
      }
      return null;
    } finally {
      calloc.free(folderPtr);
      calloc.free(verbBuf);
      for (final p in pathPtrs) {
        calloc.free(p);
      }
      if (pathsArray != nullptr) calloc.free(pathsArray);
      for (final p in interceptPtrs) {
        calloc.free(p);
      }
      if (interceptArray != nullptr) calloc.free(interceptArray);
    }
  }
}

class ShellOperations {
  static final _CreateShortcutDart _createShortcut = DynamicLibrary.process()
      .lookupFunction<_CreateShortcutNative, _CreateShortcutDart>(
          'CreateShortcutW');

  static final _InvokeShellVerbDart _invokeShellVerb = DynamicLibrary.process()
      .lookupFunction<_InvokeShellVerbNative, _InvokeShellVerbDart>(
          'InvokeShellVerbW');

  /// Creates a .lnk shortcut at [linkPath] pointing to [targetPath].
  static void createShortcut(String targetPath, String linkPath) {
    final targetPtr = targetPath.toNativeUtf16();
    final linkPtr = linkPath.toNativeUtf16();
    try {
      _createShortcut(targetPtr, linkPtr);
    } finally {
      calloc.free(targetPtr);
      calloc.free(linkPtr);
    }
  }

  /// Invokes a shell verb (e.g. "properties") on [selectedPaths].
  static int invokeVerb({
    required String folderPath,
    required List<String> selectedPaths,
    required String verb,
  }) {
    final hwnd = ShellContextMenu._getActiveWindow();
    final folderPtr = folderPath.toNativeUtf16();
    final verbPtr = verb.toNativeUtf16();
    final pathPtrs = <Pointer<Utf16>>[];
    Pointer<Pointer<Utf16>> pathsArray = nullptr;

    try {
      if (selectedPaths.isNotEmpty) {
        pathsArray = calloc<Pointer<Utf16>>(selectedPaths.length);
        for (int i = 0; i < selectedPaths.length; i++) {
          pathPtrs.add(selectedPaths[i].toNativeUtf16());
          pathsArray[i] = pathPtrs[i];
        }
      }
      return _invokeShellVerb(
        hwnd,
        folderPtr,
        pathsArray,
        selectedPaths.length,
        verbPtr,
      );
    } finally {
      calloc.free(folderPtr);
      calloc.free(verbPtr);
      for (final p in pathPtrs) {
        calloc.free(p);
      }
      if (pathsArray != nullptr) calloc.free(pathsArray);
    }
  }
}

typedef _CreateShortcutNative = Int32 Function(
    Pointer<Utf16> targetPath, Pointer<Utf16> linkPath);

typedef _CreateShortcutDart = int Function(
    Pointer<Utf16> targetPath, Pointer<Utf16> linkPath);

typedef _InvokeShellVerbNative = Int32 Function(
    IntPtr hwnd,
    Pointer<Utf16> folderPath,
    Pointer<Pointer<Utf16>> selectedPaths,
    Int32 selectedCount,
    Pointer<Utf16> verb);

typedef _InvokeShellVerbDart = int Function(
    int hwnd,
    Pointer<Utf16> folderPath,
    Pointer<Pointer<Utf16>> selectedPaths,
    int selectedCount,
    Pointer<Utf16> verb);
