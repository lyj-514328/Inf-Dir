import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 通用危险操作确认对话框。返回 true 表示确认。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '删除',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: c.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
            ),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
