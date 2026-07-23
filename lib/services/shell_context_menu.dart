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

class ShellContextMenu {
  static final _ShowMenuDart _showMenu = _load();
  static final _GetActiveWindowDart _getActiveWindow =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
              'GetActiveWindow');

  static _ShowMenuDart _load() {
    return DynamicLibrary.process()
        .lookupFunction<_ShowMenuNative, _ShowMenuDart>('ShowShellContextMenuW');
  }

  /// Verbs that Dart handles internally (not invoked by the shell).
  static const interceptVerbs = ['rename', 'open', 'explore'];

  /// Shows the native Windows Shell context menu.
  ///
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
