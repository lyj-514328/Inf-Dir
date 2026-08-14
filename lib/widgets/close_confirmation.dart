import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 关闭应用前的守卫：存在进行中/排队中的文件操作时询问用户，
/// 避免静默中断。返回 true 表示可以关闭；[activeCount] 为 0 时
/// 不弹窗直接放行。取消（含点击遮罩关闭）视为不放行。
Future<bool> confirmCloseWithActiveTasks(
  BuildContext context,
  int activeCount,
) {
  if (activeCount <= 0) return Future.value(true);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _CloseWithActiveTasksDialog(activeCount: activeCount),
  ).then((confirmed) => confirmed == true);
}

class _CloseWithActiveTasksDialog extends StatelessWidget {
  const _CloseWithActiveTasksDialog({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      title: const Text('文件操作正在进行'),
      content: Text(
        activeCount == 1
            ? '有 1 个文件操作尚未完成。关闭窗口将中断该操作，部分文件可能不完整。'
            : '有 $activeCount 个文件操作尚未完成。关闭窗口将中断这些操作，部分文件可能不完整。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: c.textSecondary),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: c.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            ),
          ),
          child: const Text('仍然关闭'),
        ),
      ],
    );
  }
}
