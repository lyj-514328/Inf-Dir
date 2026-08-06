import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Search slot in the pane location row.
///
/// Searching is not implemented yet, but keeping the control in the same
/// place as Explorer makes the eventual interaction independent of the rest
/// of the pane toolbar.
class FileSearchField extends StatelessWidget {
  const FileSearchField({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: '搜索当前文件夹',
      child: Container(
        height: AppMetrics.addressBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          border: Border.all(color: c.borderStrong),
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          color: c.surface,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: AppMetrics.iconSm, color: c.textSecondary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '搜索当前文件夹',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppMetrics.fontBody,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
