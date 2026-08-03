import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../utils/path_utils.dart';
import 'icon_service.dart';

// ---------------------------------------------------------------------------
//  Native function signatures
// ---------------------------------------------------------------------------

typedef _GetCloudDriveRootsNative = Pointer<Uint8> Function(
    Pointer<Int32> outSize);
typedef _GetCloudDriveRootsDart = Pointer<Uint8> Function(
    Pointer<Int32> outSize);

typedef _FreeSidebarItemsNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeSidebarItemsDart = void Function(Pointer<Uint8> ptr);

// ---------------------------------------------------------------------------
//  Data model
// ---------------------------------------------------------------------------

class CloudDrive {
  final String name;
  final String path;
  const CloudDrive(this.name, this.path);
}

// ---------------------------------------------------------------------------
//  Service
// ---------------------------------------------------------------------------

/// 云盘检测与"云同步区"判定。
///
/// 检测走官方契约：枚举 CfAPI 的同步根花名册（SyncRootManager 注册表，
/// 由 Windows 在云客户端调用 CfRegisterSyncRoot 时写入），任何合规网盘
/// （OneDrive、百度网盘、Dropbox……）都自动被识别，无厂商专用代码。
/// 不碰任何云厂商 API——同步由客户端自己完成，我们只是把本地同步文件夹
/// 找出来。判定则复用 shell 的占位符状态（System.FilePlaceholderStatus）。
class CloudDriveService {
  static final _getCloudDriveRoots =
      DynamicLibrary.process().lookupFunction<_GetCloudDriveRootsNative,
          _GetCloudDriveRootsDart>('GetCloudDriveRoots');

  static final _freeSidebarItems =
      DynamicLibrary.process().lookupFunction<_FreeSidebarItemsNative,
          _FreeSidebarItemsDart>('FreeSidebarItems');

  static List<CloudDrive>? _cache;

  /// 已安装的云盘同步根（name + path）。进程内缓存，只扫一次注册表。
  static List<CloudDrive> getCloudDrives() {
    final cached = _cache;
    if (cached != null) return cached;

    final outSize = calloc<Int32>();
    final ptr = _getCloudDriveRoots(outSize);
    if (ptr == nullptr || outSize.value <= 0) {
      calloc.free(outSize);
      return _cache = const [];
    }

    final drives = _parseBuffer(ptr);
    _freeSidebarItems(ptr);
    calloc.free(outSize);
    return _cache = drives;
  }

  /// [path] 等于某个云盘根或位于其下。
  static bool isCloudPath(String path) {
    for (final drive in getCloudDrives()) {
      if (isUnder(path, drive.path)) return true;
    }
    return false;
  }

  /// [path] 文件夹是否参与云同步：位于已检测的云盘根之下，或 shell 对该
  /// 文件夹本身报告了占位符状态（覆盖未经注册表检测的其它云客户端）。
  /// 用于详情视图"状态"列的显示判定（同 Files 的 IsPageTypeCloudDrive）。
  static bool isCloudZone(String path) {
    if (path.startsWith('::') || path.startsWith('shell:')) return false;
    if (isCloudPath(path)) return true;
    // -1 = 非云条目；其余编码（含"已排除"）都算云同步区。
    return IconService.getCloudStatus(path) >= 0;
  }

  // -------------------------------------------------------------------------
  //  Internal: flat buffer parser（与 SidebarService 同布局）
  // -------------------------------------------------------------------------

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

  static List<CloudDrive> _parseBuffer(Pointer<Uint8> buf) {
    final drives = <CloudDrive>[];
    int offset = 0;

    final count = buf.cast<Int32>().value;
    offset += 4;

    for (int i = 0; i < count; i++) {
      final (name, newOffset1) = _readString(buf, offset);
      offset = newOffset1;
      final (path, newOffset2) = _readString(buf, offset);
      offset = newOffset2;
      drives.add(CloudDrive(name, path));
    }
    return drives;
  }
}
