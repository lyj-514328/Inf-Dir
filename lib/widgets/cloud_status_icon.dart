import 'package:flutter/material.dart';

import '../services/icon_service.dart';
import 'app_theme.dart';

/// 云同步状态小图标（仅对云盘条目渲染，带 tooltip）。
///
/// 语义编码见 [IconService.getCloudStatus]：
/// 0 仅联机 / 1 本地可用 / 2 固定保留 / 3 同步中 / 4 已排除；
/// -1 非云条目不渲染任何内容。
/// `::` / `shell:` 虚拟路径不查询（避免无意义的 Shell 属性查询）。
/// [reserveSpace] 为 true 时，无状态的条目也会保留 [size] 宽度的占位，
/// 使行内文件图标统一左对齐（资源管理器主文件夹的做法）。
class CloudStatusIcon extends StatelessWidget {
  final String path;
  final double size;
  final bool reserveSpace;

  const CloudStatusIcon({
    super.key,
    required this.path,
    this.size = AppMetrics.iconSm,
    this.reserveSpace = false,
  });

  static (IconData, Color) _visual(int status, AppColors c) => switch (status) {
    2 => (Icons.check_circle, c.success), // pinned / always available
    1 => (Icons.cloud_done, c.success), // locally available
    3 => (Icons.sync, c.textTertiary), // syncing
    0 => (Icons.cloud, c.textTertiary), // online only
    4 => (Icons.remove_circle_outline, c.textTertiary), // excluded
    _ => (Icons.cloud, c.textTertiary),
  };

  static String _text(int status) => switch (status) {
    2 => '始终保留在此设备上',
    1 => '本地可用',
    3 => '正在同步',
    0 => '仅联机可用',
    4 => '已排除（不同步）',
    _ => '云文件',
  };

  @override
  Widget build(BuildContext context) {
    final normalized = path.toLowerCase();
    if (path.isEmpty ||
        normalized.startsWith('::') ||
        normalized.startsWith('shell:')) {
      return reserveSpace
          ? SizedBox(width: size, height: size)
          : const SizedBox.shrink();
    }
    final status = IconService.getCloudStatus(path);
    if (status < 0) {
      return reserveSpace
          ? SizedBox(width: size, height: size)
          : const SizedBox.shrink();
    }
    final (icon, color) = _visual(status, context.colors);
    return Tooltip(
      message: _text(status),
      child: Icon(icon, size: size, color: color),
    );
  }
}
