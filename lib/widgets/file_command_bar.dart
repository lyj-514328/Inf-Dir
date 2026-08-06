import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The second, command-oriented row of a file pane.
///
/// Commands that the pane does not support yet stay visible and disabled so
/// adding their behavior later does not move the surrounding controls.
class FileCommandBar extends StatelessWidget {
  final bool canCut;
  final bool canCopy;
  final bool canPaste;
  final bool canRename;
  final bool canDelete;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const FileCommandBar({
    super.key,
    required this.canCut,
    required this.canCopy,
    required this.canPaste,
    required this.canRename,
    required this.canDelete,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppMetrics.commandBarHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const _CommandButton(
              icon: Icons.add,
              label: '新建',
              tooltip: '新建（即将支持）',
            ),
            _CommandButton(
              icon: Icons.content_cut,
              label: '剪切',
              enabled: canCut,
              onPressed: onCut,
            ),
            _CommandButton(
              icon: Icons.content_copy,
              label: '复制',
              enabled: canCopy,
              onPressed: onCopy,
            ),
            _CommandButton(
              icon: Icons.content_paste,
              label: '粘贴',
              enabled: canPaste,
              onPressed: onPaste,
            ),
            _CommandButton(
              icon: Icons.drive_file_rename_outline,
              label: '重命名',
              enabled: canRename,
              onPressed: onRename,
            ),
            const _CommandButton(
              icon: Icons.ios_share,
              label: '共享',
              tooltip: '共享（即将支持）',
            ),
            _CommandButton(
              icon: Icons.delete_outline,
              label: '删除',
              enabled: canDelete,
              onPressed: onDelete,
            ),
            const _CommandDivider(),
            const _CommandButton(icon: Icons.sort, label: '排序', tooltip: '排序'),
            const _CommandButton(
              icon: Icons.view_list,
              label: '查看',
              tooltip: '查看',
            ),
            const _CommandButton(
              icon: Icons.filter_alt_outlined,
              label: '筛选器',
              tooltip: '筛选器（即将支持）',
            ),
            const _CommandButton(
              icon: Icons.more_horiz,
              label: '更多',
              tooltip: '更多操作',
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandDivider extends StatelessWidget {
  const _CommandDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: context.colors.border,
    );
  }
}

class _CommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  const _CommandButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.enabled = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      hoverColor: c.surfaceHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: SizedBox(
          height: AppMetrics.commandBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppMetrics.iconMd,
                color: enabled ? c.textSecondary : c.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: enabled ? c.textSecondary : c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
