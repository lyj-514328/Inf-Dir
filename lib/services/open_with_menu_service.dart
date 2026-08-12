import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class OpenWithMenuEntry {
  final String label;
  final int commandId;
  final bool enabled;
  final bool isDivider;
  final Uint8List? iconPng;

  const OpenWithMenuEntry._({
    this.label = '',
    this.commandId = 0,
    this.enabled = false,
    this.isDivider = false,
    this.iconPng,
  });

  OpenWithMenuEntry.command({
    required String label,
    required int commandId,
    required bool enabled,
    required Uint8List? iconPng,
  }) : this._(
         label: label,
         commandId: commandId,
         enabled: enabled,
         iconPng: iconPng,
       );

  const OpenWithMenuEntry.divider() : this._(isDivider: true);
}

class OpenWithMenuData {
  final Uint8List? defaultAppIconPng;
  final List<OpenWithMenuEntry> entries;

  const OpenWithMenuData({this.defaultAppIconPng, this.entries = const []});
}

typedef _GetEntriesNative =
    Pointer<Uint8> Function(
      Pointer<Utf16> filePath,
      Int32 iconSize,
      Pointer<Int32> outSize,
    );
typedef _GetEntriesDart =
    Pointer<Uint8> Function(
      Pointer<Utf16> filePath,
      int iconSize,
      Pointer<Int32> outSize,
    );

typedef _FreeEntriesNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeEntriesDart = void Function(Pointer<Uint8> ptr);

typedef _InvokeEntryNative = Int32 Function(Int32 commandId);
typedef _InvokeEntryDart = int Function(int commandId);

/// Enumerates Windows association handlers and exposes them to the Flutter
/// command menu. Native handlers remain valid until [invoke] is called or
/// another file is queried.
class OpenWithMenuService {
  OpenWithMenuService._();

  static final _getEntries = DynamicLibrary.process()
      .lookupFunction<_GetEntriesNative, _GetEntriesDart>(
        'GetOpenWithMenuEntriesW',
      );
  static final _freeEntries = DynamicLibrary.process()
      .lookupFunction<_FreeEntriesNative, _FreeEntriesDart>(
        'FreeOpenWithMenuEntries',
      );
  static final _invokeEntry = DynamicLibrary.process()
      .lookupFunction<_InvokeEntryNative, _InvokeEntryDart>(
        'InvokeOpenWithMenuEntry',
      );
  static OpenWithMenuData getData(String filePath, {required int iconSize}) {
    final path = filePath.toNativeUtf16();
    final outSize = calloc<Int32>();
    try {
      final ptr = _getEntries(path, iconSize, outSize);
      if (ptr == nullptr || outSize.value < 8) {
        return const OpenWithMenuData();
      }
      try {
        return _parse(ptr, outSize.value);
      } finally {
        _freeEntries(ptr);
      }
    } finally {
      calloc.free(path);
      calloc.free(outSize);
    }
  }

  static void invoke(int commandId) {
    _invokeEntry(commandId);
  }

  static OpenWithMenuData _parse(Pointer<Uint8> buffer, int byteSize) {
    var offset = 0;
    final count = _readInt32(buffer, offset, byteSize);
    offset += 4;
    if (count == null || count < 0 || count > 256) {
      return const OpenWithMenuData();
    }

    final defaultIconLength = _readInt32(buffer, offset, byteSize);
    offset += 4;
    if (defaultIconLength == null ||
        defaultIconLength < 0 ||
        offset + defaultIconLength > byteSize) {
      return const OpenWithMenuData();
    }
    final defaultAppIconPng = defaultIconLength == 0
        ? null
        : Uint8List.fromList((buffer + offset).asTypedList(defaultIconLength));
    offset += defaultIconLength;

    final entries = <OpenWithMenuEntry>[];
    for (var index = 0; index < count; index++) {
      final kind = _readInt32(buffer, offset, byteSize);
      offset += 4;
      final commandId = _readInt32(buffer, offset, byteSize);
      offset += 4;
      final enabled = _readInt32(buffer, offset, byteSize);
      offset += 4;
      final labelLength = _readInt32(buffer, offset, byteSize);
      offset += 4;
      if (kind == null ||
          commandId == null ||
          enabled == null ||
          labelLength == null ||
          labelLength < 0 ||
          offset + labelLength * 2 > byteSize) {
        return const OpenWithMenuData();
      }

      final label = _readUtf16(buffer, offset, labelLength);
      offset += labelLength * 2;
      final iconLength = _readInt32(buffer, offset, byteSize);
      offset += 4;
      if (iconLength == null ||
          iconLength < 0 ||
          offset + iconLength > byteSize) {
        return const OpenWithMenuData();
      }
      final iconPng = iconLength == 0
          ? null
          : Uint8List.fromList((buffer + offset).asTypedList(iconLength));
      offset += iconLength;
      if (kind == 1) {
        entries.add(const OpenWithMenuEntry.divider());
      } else if (kind == 0 && commandId > 0 && label.isNotEmpty) {
        entries.add(
          OpenWithMenuEntry.command(
            label: label,
            commandId: commandId,
            enabled: enabled != 0,
            iconPng: iconPng,
          ),
        );
      }
    }
    return OpenWithMenuData(
      defaultAppIconPng: defaultAppIconPng,
      entries: entries,
    );
  }

  static int? _readInt32(Pointer<Uint8> buffer, int offset, int byteSize) {
    if (offset < 0 || offset + 4 > byteSize) return null;
    return (buffer + offset).cast<Int32>().value;
  }

  static String _readUtf16(Pointer<Uint8> buffer, int offset, int length) {
    if (length == 0) return '';
    final units = <int>[];
    for (var index = 0; index < length; index++) {
      final low = (buffer + offset + index * 2).value;
      final high = (buffer + offset + index * 2 + 1).value;
      units.add((high << 8) | low);
    }
    return String.fromCharCodes(units);
  }
}
