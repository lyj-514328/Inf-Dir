import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/file_operation_task.dart';
import '../services/file_operation_center.dart';
import '../services/shell_file_operation.dart';
import 'app_theme.dart';

/// 顶栏任务中心入口：常驻显示，角标始终展示活动任务数（空闲时为 0），
/// 点击开关任务面板。
class FileTaskCenterButton extends StatelessWidget {
  const FileTaskCenterButton({
    super.key,
    required this.center,
    required this.open,
    required this.onTap,
  });

  final FileOperationCenter center;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.colors;
    final activeCount = center.activeTasks.length;
    final highlighted = open || activeCount > 0;

    return Tooltip(
      message: '文件任务',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.sync,
                  size: AppMetrics.iconMd,
                  color: highlighted ? c.accent : c.textSecondary,
                ),
              ),
              Positioned(
                top: -2,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 14),
                  height: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: highlighted ? c.accent : c.borderStrong,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    activeCount > 9 ? '9+' : '$activeCount',
                    style: TextStyle(
                      fontSize: 8,
                      height: 1,
                      color: highlighted ? c.onAccent : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 文件任务中心面板：排队 / 进行中 / 成功 / 失败 / 已取消的任务列表，
/// 支持取消、移除单条和清除全部已完成任务。
class FileTaskCenterPanel extends StatelessWidget {
  const FileTaskCenterPanel({
    super.key,
    required this.center,
    required this.onClose,
  });

  final FileOperationCenter center;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      width: 360,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppMetrics.paneRadius),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: center,
        builder: (context, _) {
          final tasks = center.tasks;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                hasFinished: center.hasFinishedTasks,
                onClearFinished: center.clearFinished,
                onClose: onClose,
              ),
              Container(height: 1, color: c.border),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                  child: Text(
                    '没有文件任务',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textTertiary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 288),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) =>
                          Container(height: 1, color: c.border),
                      itemBuilder: (context, index) => _TaskRow(
                        task: tasks[index],
                        onCancel: () => center.cancel(tasks[index].id),
                        onDismiss: () => center.dismiss(tasks[index].id),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.hasFinished,
    required this.onClearFinished,
    required this.onClose,
  });

  final bool hasFinished;
  final VoidCallback onClearFinished;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Text(
            '文件任务',
            style: TextStyle(
              fontSize: AppMetrics.fontTitle,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const Spacer(),
          _GhostTextAction(
            label: '清除已完成',
            enabled: hasFinished,
            onTap: onClearFinished,
          ),
          IconButton(
            onPressed: onClose,
            tooltip: '关闭',
            iconSize: AppMetrics.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: c.textSecondary,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _GhostTextAction extends StatelessWidget {
  const _GhostTextAction({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppMetrics.fontSmall,
            color: enabled ? c.textSecondary : c.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onCancel,
    required this.onDismiss,
  });

  final FileOperationTask task;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = task.status;
    final running = status == FileOperationStatus.running;
    final queued = status == FileOperationStatus.queued;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            task.type.icon,
            size: AppMetrics.iconMd,
            color: _statusColor(c, task),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    color: c.textPrimary,
                  ),
                ),
                if (task.destination != null && task.type.showsDestination) ...[
                  const SizedBox(height: 1),
                  Text(
                    '${task.type.destinationLabel} ${task.destination}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _statusText(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    color: _statusColor(c, task),
                  ),
                ),
                for (final failure in task.failures.take(2)) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${failure.path}（${failure.hrLabel}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontCaption,
                      color: c.danger,
                    ),
                  ),
                ],
                if (task.failures.length > 2) ...[
                  const SizedBox(height: 2),
                  Text(
                    '另有 ${task.failures.length - 2} 项失败',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontCaption,
                      color: c.danger,
                    ),
                  ),
                ],
                if (status == FileOperationStatus.failed &&
                    task.failures.isEmpty &&
                    task.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _errorText(task.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppMetrics.fontCaption,
                      color: c.danger,
                    ),
                  ),
                ],
                if (running) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 2,
                      backgroundColor: c.surfaceHover,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: running || queued ? onCancel : onDismiss,
            tooltip: running || queued ? '取消' : '移除',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: c.textTertiary,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  String _title(FileOperationTask task) {
    // Restore sources are Recycle Bin parsing names ($R…); show a count.
    if (task.type != FileOperationType.restore && task.sources.length == 1) {
      final name = _basename(task.sources.first);
      if (name.isNotEmpty) {
        return '${task.type.actionLabel} "$name"';
      }
    }
    return '${task.type.actionLabel} ${task.sources.length} 个项目';
  }

  String _basename(String path) {
    final name = p.basename(path);
    return name.isEmpty ? path : name;
  }

  String _statusText(FileOperationTask task) {
    switch (task.status) {
      case FileOperationStatus.queued:
        return '排队中';
      case FileOperationStatus.running:
        return '进行中 ${(task.progress * 100).round()}%';
      case FileOperationStatus.succeeded:
        return task.hasFailures ? '已完成，${task.failures.length} 项失败' : '已完成';
      case FileOperationStatus.failed:
        return '失败';
      case FileOperationStatus.cancelled:
        return '已取消';
    }
  }

  String _errorText(Object? error) {
    if (error is ShellFileOperationException) return error.message;
    if (error is FileSystemException) return error.message;
    return error.toString();
  }

  Color _statusColor(AppColors c, FileOperationTask task) {
    switch (task.status) {
      case FileOperationStatus.queued:
      case FileOperationStatus.running:
        return c.accent;
      case FileOperationStatus.succeeded:
        return task.hasFailures ? c.danger : c.success;
      case FileOperationStatus.failed:
        return c.danger;
      case FileOperationStatus.cancelled:
        return c.textTertiary;
    }
  }
}

extension on FileOperationType {
  String get actionLabel => switch (this) {
    FileOperationType.copy => '复制',
    FileOperationType.move => '移动',
    FileOperationType.delete => '移到回收站',
    FileOperationType.permanentDelete => '永久删除',
    FileOperationType.restore => '还原',
    FileOperationType.create => '新建',
    FileOperationType.rename => '重命名',
    FileOperationType.compress => '压缩',
    FileOperationType.extract => '解压',
  };

  IconData get icon => switch (this) {
    FileOperationType.copy => Icons.copy,
    FileOperationType.move => Icons.drive_file_move_outline,
    FileOperationType.delete => Icons.delete_outline,
    FileOperationType.permanentDelete => Icons.delete_forever_outlined,
    FileOperationType.restore => Icons.restore_from_trash,
    FileOperationType.create => Icons.create_new_folder_outlined,
    FileOperationType.rename => Icons.drive_file_rename_outline,
    FileOperationType.compress => Icons.folder_zip_outlined,
    FileOperationType.extract => Icons.folder_open_outlined,
  };

  bool get showsDestination => switch (this) {
    FileOperationType.copy ||
    FileOperationType.move ||
    FileOperationType.compress ||
    FileOperationType.extract => true,
    _ => false,
  };

  String get destinationLabel => switch (this) {
    FileOperationType.compress => '保存到',
    FileOperationType.extract => '解压到',
    _ => '到',
  };
}
