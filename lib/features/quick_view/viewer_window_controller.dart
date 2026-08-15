import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

class ViewerWindowPlacement {
  const ViewerWindowPlacement({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.maximized,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final bool maximized;

  Map<String, Object> toProtocolV1Json() => {
    'version': 1,
    'x': left,
    'y': top,
    'width': right - left,
    'height': bottom - top,
    'maximized': maximized,
  };

  @override
  String toString() {
    return 'rect=($left,$top)-($right,$bottom) '
        'size=${right - left}x${bottom - top} maximized=$maximized';
  }
}

abstract interface class ViewerWindowController {
  Future<int?> waitForTopLevelWindow(
    int processId, {
    required Duration timeout,
  });

  ViewerWindowPlacement? capturePlacement(int windowHandle, {String? logLabel});

  bool applyPlacement(int windowHandle, ViewerWindowPlacement placement);

  bool requestClose(int windowHandle);
}

typedef ViewerWindowLogger = void Function(String message);

class Win32ViewerWindowController implements ViewerWindowController {
  const Win32ViewerWindowController({
    this.pollInterval = const Duration(milliseconds: 25),
    this.logger,
  });

  final Duration pollInterval;
  final ViewerWindowLogger? logger;

  @override
  Future<int?> waitForTopLevelWindow(
    int processId, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    int? observedHandle;
    ViewerWindowPlacement? observedPlacement;
    var stableSamples = 0;
    do {
      final handle = _findTopLevelWindow(processId);
      final placement = handle == null ? null : capturePlacement(handle);
      if (handle != null && placement != null && _hasUsableSize(placement)) {
        if (handle == observedHandle &&
            _samePlacement(placement, observedPlacement)) {
          stableSamples++;
        } else {
          observedHandle = handle;
          observedPlacement = placement;
          stableSamples = 1;
        }
        if (stableSamples >= _stableSampleCount) {
          logger?.call(
            '[QuickViewWindow] ready pid=$processId hwnd=$handle '
            '${_describeWindow(handle)} selected=$placement',
          );
          return handle;
        }
      } else {
        observedHandle = null;
        observedPlacement = null;
        stableSamples = 0;
      }
      if (stopwatch.elapsed >= timeout) break;
      await Future<void>.delayed(pollInterval);
    } while (true);
    return null;
  }

  @override
  ViewerWindowPlacement? capturePlacement(
    int windowHandle, {
    String? logLabel,
  }) {
    final snapshot = _readWindowSnapshot(windowHandle);
    if (snapshot == null) {
      if (logLabel != null) {
        logger?.call(
          '[QuickViewWindow] $logLabel hwnd=$windowHandle unavailable',
        );
      }
      return null;
    }
    final maximized = snapshot.isMaximized;
    final rect = maximized || snapshot.isMinimized
        ? snapshot.normalRect
        : snapshot.currentRect;
    final selected = ViewerWindowPlacement(
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
      maximized: maximized,
    );
    if (logLabel != null) {
      logger?.call(
        '[QuickViewWindow] $logLabel hwnd=$windowHandle $snapshot '
        'selected=$selected',
      );
    }
    return selected;
  }

  @override
  bool applyPlacement(int windowHandle, ViewerWindowPlacement placement) {
    if (_User32.isWindow(windowHandle) == 0) return false;

    logger?.call(
      '[QuickViewWindow] apply hwnd=$windowHandle target=$placement '
      'before=${_describeWindow(windowHandle)}',
    );

    final bool applied;
    if (placement.maximized) {
      final nativePlacement = calloc<_WindowPlacement>();
      try {
        nativePlacement.ref
          ..length = sizeOf<_WindowPlacement>()
          ..flags = 0
          ..showCommand = _swShowMaximized;
        nativePlacement.ref.normalPosition
          ..left = placement.left
          ..top = placement.top
          ..right = placement.right
          ..bottom = placement.bottom;
        applied =
            _User32.setWindowPlacement(windowHandle, nativePlacement) != 0;
      } finally {
        calloc.free(nativePlacement);
      }
    } else {
      applied =
          _User32.setWindowPosition(
            windowHandle,
            0,
            placement.left,
            placement.top,
            placement.right - placement.left,
            placement.bottom - placement.top,
            _swpNoZOrder,
          ) !=
          0;
    }

    if (applied) _User32.setForegroundWindow(windowHandle);
    logger?.call(
      '[QuickViewWindow] applied=$applied hwnd=$windowHandle '
      'after=${_describeWindow(windowHandle)}',
    );
    return applied;
  }

  _WindowSnapshot? _readWindowSnapshot(int windowHandle) {
    if (_User32.isWindow(windowHandle) == 0) return null;
    final nativePlacement = calloc<_WindowPlacement>();
    final currentRect = calloc<_Rect>();
    try {
      nativePlacement.ref.length = sizeOf<_WindowPlacement>();
      if (_User32.getWindowPlacement(windowHandle, nativePlacement) == 0 ||
          _User32.getWindowRect(windowHandle, currentRect) == 0) {
        return null;
      }
      return _WindowSnapshot(
        currentRect: _WindowRect.fromNative(currentRect.ref),
        normalRect: _WindowRect.fromNative(nativePlacement.ref.normalPosition),
        flags: nativePlacement.ref.flags,
        showCommand: nativePlacement.ref.showCommand,
      );
    } finally {
      calloc.free(nativePlacement);
      calloc.free(currentRect);
    }
  }

  String _describeWindow(int windowHandle) =>
      _readWindowSnapshot(windowHandle)?.toString() ?? 'unavailable';

  @override
  bool requestClose(int windowHandle) {
    if (_User32.isWindow(windowHandle) == 0) return false;
    return _User32.postMessage(windowHandle, _wmClose, 0, 0) != 0;
  }

  int? _findTopLevelWindow(int processId) {
    final context = calloc<IntPtr>(2);
    try {
      context[0] = processId;
      _User32.enumWindows(_enumWindowsCallbackPointer, context.address);
      return context[1] == 0 ? null : context[1];
    } finally {
      calloc.free(context);
    }
  }
}

class _WindowRect {
  const _WindowRect(this.left, this.top, this.right, this.bottom);

  factory _WindowRect.fromNative(_Rect rect) =>
      _WindowRect(rect.left, rect.top, rect.right, rect.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  @override
  String toString() => '($left,$top)-($right,$bottom)';
}

class _WindowSnapshot {
  const _WindowSnapshot({
    required this.currentRect,
    required this.normalRect,
    required this.flags,
    required this.showCommand,
  });

  final _WindowRect currentRect;
  final _WindowRect normalRect;
  final int flags;
  final int showCommand;

  bool get isMaximized =>
      showCommand == _swShowMaximized || (flags & _wpfRestoreToMaximized) != 0;

  bool get isMinimized =>
      showCommand == _swShowMinimized ||
      showCommand == _swMinimize ||
      showCommand == _swShowMinNoActive;

  @override
  String toString() =>
      'currentRect=$currentRect normalRect=$normalRect '
      'showCmd=$showCommand flags=$flags';
}

bool _hasUsableSize(ViewerWindowPlacement placement) =>
    placement.right - placement.left >= _minimumWindowExtent &&
    placement.bottom - placement.top >= _minimumWindowExtent;

bool _samePlacement(
  ViewerWindowPlacement placement,
  ViewerWindowPlacement? other,
) =>
    other != null &&
    placement.left == other.left &&
    placement.top == other.top &&
    placement.right == other.right &&
    placement.bottom == other.bottom &&
    placement.maximized == other.maximized;

const int _gwOwner = 4;
const int _minimumWindowExtent = 64;
const int _stableSampleCount = 3;
const int _swShowMinimized = 2;
const int _swShowMaximized = 3;
const int _swMinimize = 6;
const int _swShowMinNoActive = 7;
const int _swpNoZOrder = 0x0004;
const int _wmClose = 0x0010;
const int _wpfRestoreToMaximized = 0x0002;

int _enumWindowsCallback(int windowHandle, int parameter) {
  final context = Pointer<IntPtr>.fromAddress(parameter);
  if (_User32.isWindowVisible(windowHandle) == 0 ||
      _User32.getWindow(windowHandle, _gwOwner) != 0) {
    return 1;
  }

  final processId = calloc<Uint32>();
  try {
    _User32.getWindowThreadProcessId(windowHandle, processId);
    if (processId.value != context[0]) return 1;
    context[1] = windowHandle;
    return 0;
  } finally {
    calloc.free(processId);
  }
}

final _enumWindowsCallbackPointer =
    Pointer.fromFunction<_EnumWindowsCallbackNative>(_enumWindowsCallback, 0);

final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

final class _WindowPlacement extends Struct {
  @Uint32()
  external int length;

  @Uint32()
  external int flags;

  @Uint32()
  external int showCommand;

  external _Point minPosition;
  external _Point maxPosition;
  external _Rect normalPosition;
}

typedef _EnumWindowsCallbackNative = Int32 Function(IntPtr, IntPtr);
typedef _EnumWindowsNative =
    Int32 Function(
      Pointer<NativeFunction<_EnumWindowsCallbackNative>> callback,
      IntPtr parameter,
    );
typedef _EnumWindowsDart =
    int Function(
      Pointer<NativeFunction<_EnumWindowsCallbackNative>> callback,
      int parameter,
    );
typedef _GetWindowThreadProcessIdNative =
    Uint32 Function(IntPtr windowHandle, Pointer<Uint32> processId);
typedef _GetWindowThreadProcessIdDart =
    int Function(int windowHandle, Pointer<Uint32> processId);
typedef _WindowPredicateNative = Int32 Function(IntPtr windowHandle);
typedef _WindowPredicateDart = int Function(int windowHandle);
typedef _GetWindowNative = IntPtr Function(IntPtr windowHandle, Uint32 command);
typedef _GetWindowDart = int Function(int windowHandle, int command);
typedef _GetWindowPlacementNative =
    Int32 Function(IntPtr windowHandle, Pointer<_WindowPlacement> placement);
typedef _GetWindowPlacementDart =
    int Function(int windowHandle, Pointer<_WindowPlacement> placement);
typedef _GetWindowRectNative =
    Int32 Function(IntPtr windowHandle, Pointer<_Rect> rect);
typedef _GetWindowRectDart =
    int Function(int windowHandle, Pointer<_Rect> rect);
typedef _SetWindowPositionNative =
    Int32 Function(
      IntPtr windowHandle,
      IntPtr insertAfter,
      Int32 x,
      Int32 y,
      Int32 width,
      Int32 height,
      Uint32 flags,
    );
typedef _SetWindowPositionDart =
    int Function(
      int windowHandle,
      int insertAfter,
      int x,
      int y,
      int width,
      int height,
      int flags,
    );
typedef _PostMessageNative =
    Int32 Function(
      IntPtr windowHandle,
      Uint32 message,
      IntPtr wordParameter,
      IntPtr longParameter,
    );
typedef _PostMessageDart =
    int Function(
      int windowHandle,
      int message,
      int wordParameter,
      int longParameter,
    );

abstract final class _User32 {
  static final DynamicLibrary _library = DynamicLibrary.open('user32.dll');

  static final _EnumWindowsDart enumWindows = _library
      .lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');
  static final _GetWindowThreadProcessIdDart getWindowThreadProcessId = _library
      .lookupFunction<
        _GetWindowThreadProcessIdNative,
        _GetWindowThreadProcessIdDart
      >('GetWindowThreadProcessId');
  static final _WindowPredicateDart isWindow = _library
      .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>('IsWindow');
  static final _WindowPredicateDart isWindowVisible = _library
      .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>(
        'IsWindowVisible',
      );
  static final _GetWindowDart getWindow = _library
      .lookupFunction<_GetWindowNative, _GetWindowDart>('GetWindow');
  static final _GetWindowPlacementDart getWindowPlacement = _library
      .lookupFunction<_GetWindowPlacementNative, _GetWindowPlacementDart>(
        'GetWindowPlacement',
      );
  static final _GetWindowPlacementDart setWindowPlacement = _library
      .lookupFunction<_GetWindowPlacementNative, _GetWindowPlacementDart>(
        'SetWindowPlacement',
      );
  static final _GetWindowRectDart getWindowRect = _library
      .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
        'GetWindowRect',
      );
  static final _SetWindowPositionDart setWindowPosition = _library
      .lookupFunction<_SetWindowPositionNative, _SetWindowPositionDart>(
        'SetWindowPos',
      );
  static final _WindowPredicateDart setForegroundWindow = _library
      .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>(
        'SetForegroundWindow',
      );
  static final _PostMessageDart postMessage = _library
      .lookupFunction<_PostMessageNative, _PostMessageDart>('PostMessageW');
}
