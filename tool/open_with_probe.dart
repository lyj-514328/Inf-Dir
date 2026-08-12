import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _CoInitializeExNative = Int32 Function(IntPtr, Uint32);
typedef _CoInitializeExDart = int Function(int, int);
typedef _CoUninitializeNative = Void Function();
typedef _CoUninitializeDart = void Function();

typedef _GetEntriesNative =
    Pointer<Uint8> Function(Pointer<Utf16>, Pointer<Int32>);
typedef _GetEntriesDart = Pointer<Uint8> Function(Pointer<Utf16>, Pointer<Int32>);
typedef _FreeEntriesNative = Void Function(Pointer<Uint8>);
typedef _FreeEntriesDart = void Function(Pointer<Uint8>);

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Usage: <runner.exe> <file-path>');
  }
  final ole32 = DynamicLibrary.open('ole32.dll');
  final initialize = ole32
      .lookupFunction<_CoInitializeExNative, _CoInitializeExDart>(
        'CoInitializeEx',
      );
  final uninitialize = ole32
      .lookupFunction<_CoUninitializeNative, _CoUninitializeDart>(
        'CoUninitialize',
      );
  final result = initialize(0, 0x2);
  if (result < 0) throw StateError('CoInitializeEx failed: $result');

  final runner = DynamicLibrary.open(args[0]);
  final getEntries = runner.lookupFunction<_GetEntriesNative, _GetEntriesDart>(
    'GetOpenWithMenuEntriesW',
  );
  final freeEntries =
      runner.lookupFunction<_FreeEntriesNative, _FreeEntriesDart>(
        'FreeOpenWithMenuEntries',
      );
  final path = args[1].toNativeUtf16();
  final size = calloc<Int32>();
  final buffer = getEntries(path, size);
  try {
    if (buffer == nullptr) {
      print('No Open With entries returned.');
      return;
    }
    var offset = 4;
    final count = buffer.cast<Int32>().value;
    print('count=$count, bytes=${size.value}');
    for (var index = 0; index < count; index++) {
      final kind = _readInt32(buffer, offset);
      offset += 4;
      final id = _readInt32(buffer, offset);
      offset += 4;
      final enabled = _readInt32(buffer, offset);
      offset += 4;
      final length = _readInt32(buffer, offset);
      offset += 4;
      final label = _readUtf16(buffer, offset, length);
      offset += length * 2;
      final iconLength = _readInt32(buffer, offset);
      offset += 4 + iconLength;
      print(
        '[$index] kind=$kind id=$id enabled=$enabled '
        'iconBytes=$iconLength label=$label',
      );
    }
  } finally {
    if (buffer != nullptr) freeEntries(buffer);
    calloc.free(path);
    calloc.free(size);
    uninitialize();
  }
}

int _readInt32(Pointer<Uint8> buffer, int offset) =>
    (buffer + offset).cast<Int32>().value;

String _readUtf16(Pointer<Uint8> buffer, int offset, int length) {
  final units = <int>[];
  for (var index = 0; index < length; index++) {
    final low = (buffer + offset + index * 2).value;
    final high = (buffer + offset + index * 2 + 1).value;
    units.add(low | (high << 8));
  }
  return String.fromCharCodes(units);
}
