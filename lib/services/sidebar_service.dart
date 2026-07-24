import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
//  Native function signatures
// ---------------------------------------------------------------------------

typedef _GetQuickAccessItemsNative = Pointer<Uint8> Function(
    Pointer<Int32> outSize);
typedef _GetQuickAccessItemsDart = Pointer<Uint8> Function(
    Pointer<Int32> outSize);

typedef _GetDriveInfoNative = Pointer<Uint8> Function(
    Pointer<Utf16> driveRoot, Pointer<Int32> outSize);
typedef _GetDriveInfoDart = Pointer<Uint8> Function(
    Pointer<Utf16> driveRoot, Pointer<Int32> outSize);

typedef _FreeSidebarItemsNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeSidebarItemsDart = void Function(Pointer<Uint8> ptr);

typedef _ProbeChildrenNative = Int32 Function(Pointer<Utf16> path);
typedef _ProbeChildrenDart = int Function(Pointer<Utf16> path);

// ---------------------------------------------------------------------------
//  Data model
// ---------------------------------------------------------------------------

class QuickAccessItem {
  final String name;
  final String path;
  final bool isPinned;
  QuickAccessItem(this.name, this.path, this.isPinned);
}

class DriveInfo {
  final String friendlyName;
  final String fileSystem;
  DriveInfo(this.friendlyName, this.fileSystem);
}

// ---------------------------------------------------------------------------
//  Service
// ---------------------------------------------------------------------------

class SidebarService {
  static final _getQuickAccessItems =
      DynamicLibrary.process().lookupFunction<_GetQuickAccessItemsNative,
          _GetQuickAccessItemsDart>('GetQuickAccessItems');

  static final _getDriveInfo = DynamicLibrary.process()
      .lookupFunction<_GetDriveInfoNative, _GetDriveInfoDart>('GetDriveInfo');

  static final _freeSidebarItems =
      DynamicLibrary.process().lookupFunction<_FreeSidebarItemsNative,
          _FreeSidebarItemsDart>('FreeSidebarItems');

  static final _probeChildren =
      DynamicLibrary.process().lookupFunction<_ProbeChildrenNative,
          _ProbeChildrenDart>('ProbeDirectoryHasChildren');

  static final Map<String, DriveInfo> _driveInfoCache = {};

  /// Enumerates Quick Access items from Windows Shell (pinned + frequent).
  static List<QuickAccessItem> getQuickAccessItems() {
    final outSize = calloc<Int32>();
    final ptr = _getQuickAccessItems(outSize);
    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return [];
    }

    final items = _parseQuickAccessBuffer(ptr, outSize.value);
    _freeSidebarItems(ptr);
    calloc.free(outSize);
    return items;
  }

  /// Gets friendly name and filesystem type for a drive root (e.g. "C:\").
  static DriveInfo? getDriveInfo(String driveRoot) {
    final cached = _driveInfoCache[driveRoot];
    if (cached != null) return cached;

    final outSize = calloc<Int32>();
    final rootPtr = driveRoot.toNativeUtf16();
    final ptr = _getDriveInfo(rootPtr, outSize);
    calloc.free(rootPtr);

    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return null;
    }

    final info = _parseDriveInfoBuffer(ptr, outSize.value);
    _freeSidebarItems(ptr);
    calloc.free(outSize);

    if (info != null) {
      _driveInfoCache[driveRoot] = info;
    }
    return info;
  }

  /// Returns all available drive roots (e.g. ["C:\", "D:\"]).
  static List<String> getDriveRoots() {
    final drives = <String>[];
    for (int i = 65; i <= 90; i++) {
      final letter = String.fromCharCode(i);
      final root = '$letter:\\';
      if (Directory(root).existsSync()) {
        drives.add(root);
      }
    }
    return drives;
  }

  /// Formats a drive label like "本地磁盘 (C:)" or "Windows (C:)".
  static String formatDriveLabel(String driveRoot) {
    final info = getDriveInfo(driveRoot);
    final letter = driveRoot.replaceAll('\\', '').replaceAll(':', '');
    if (info != null && info.friendlyName.isNotEmpty) {
      return '${info.friendlyName} ($letter:)';
    }
    return '($letter:)';
  }

  /// Lightweight check: returns true if [path] has at least one subdirectory.
  static bool directoryHasChildren(String path) {
    final ptr = path.toNativeUtf16();
    final result = _probeChildren(ptr);
    calloc.free(ptr);
    return result != 0;
  }

  // -----------------------------------------------------------------------
  //  Internal: flat buffer parser helpers
  // -----------------------------------------------------------------------

  /// Reads a counted wchar_t string from the buffer at [offset].
  /// Returns (decoded string, new offset).
  static (String, int) _readString(Pointer<Uint8> buf, int offset) {
    final len = buf.elementAt(offset).cast<Int32>().value;
    offset += 4;
    if (len <= 0) return ('', offset);
    final chars = <int>[];
    for (int i = 0; i < len; i++) {
      final low = buf.elementAt(offset + i * 2).value;
      final high = buf.elementAt(offset + i * 2 + 1).value;
      chars.add((high << 8) | low);
    }
    offset += len * 2;
    return (String.fromCharCodes(chars), offset);
  }

  static List<QuickAccessItem> _parseQuickAccessBuffer(
      Pointer<Uint8> buf, int totalSize) {
    final items = <QuickAccessItem>[];
    int offset = 0;

    final count = buf.cast<Int32>().value;
    offset += 4;

    for (int i = 0; i < count; i++) {
      final (name, newOffset1) = _readString(buf, offset);
      offset = newOffset1;
      final (path, newOffset2) = _readString(buf, offset);
      offset = newOffset2;
      final isPinned = buf.elementAt(offset).cast<Int32>().value != 0;
      offset += 4;
      items.add(QuickAccessItem(name, path, isPinned));
    }
    return items;
  }

  static DriveInfo? _parseDriveInfoBuffer(
      Pointer<Uint8> buf, int totalSize) {
    int offset = 0;
    final (friendlyName, newOffset) = _readString(buf, offset);
    offset = newOffset;
    final (fsType, _) = _readString(buf, offset);
    return DriveInfo(friendlyName, fsType);
  }

}
