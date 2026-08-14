import 'package:flutter/material.dart';

import 'app_theme.dart';

/// How the user wants a copy/move name collision resolved.
enum ConflictResolution { replace, skip, keepBoth }

/// Resolves copy/move name collisions with the user.
///
/// Shows one dialog per colliding name; the "应用到全部" checkbox applies the
/// current choice to every remaining conflict. Returns null when the user
/// aborts, otherwise a map from lowercase basename to the chosen resolution.
Future<Map<String, ConflictResolution>?> resolveFileConflicts(
  BuildContext context, {
  required List<String> conflictNames,
  required String destination,
}) async {
  final resolutions = <String, ConflictResolution>{};
  ConflictResolution? applyToAll;
  var index = 0;
  for (final name in conflictNames) {
    if (applyToAll != null) {
      resolutions[name.toLowerCase()] = applyToAll;
      continue;
    }
    final remaining = conflictNames.length - index - 1;
    final choice = await _showConflictDialog(
      context,
      name: name,
      destination: destination,
      remaining: remaining,
    );
    if (choice == null) return null;
    resolutions[name.toLowerCase()] = choice.resolution;
    if (choice.applyToAll) applyToAll = choice.resolution;
    index++;
  }
  return resolutions;
}

Future<({ConflictResolution resolution, bool applyToAll})?>
_showConflictDialog(
  BuildContext context, {
  required String name,
  required String destination,
  required int remaining,
}) {
  return showDialog<({ConflictResolution resolution, bool applyToAll})>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ConflictDialog(
      name: name,
      destination: destination,
      remaining: remaining,
    ),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.name,
    required this.destination,
    required this.remaining,
  });

  final String name;
  final String destination;
  final int remaining;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  bool _applyToAll = false;

  void _resolve(ConflictResolution resolution) {
    Navigator.pop(
      context,
      (resolution: resolution, applyToAll: _applyToAll),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      title: const Text('文件冲突'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目标位置已包含同名项目：',
            style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            '“${widget.name}”',
            style: TextStyle(
              fontSize: AppMetrics.fontBody,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '目标：${widget.destination}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppMetrics.fontSmall,
              color: c.textSecondary,
            ),
          ),
          if (widget.remaining > 0) ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _applyToAll,
              onChanged: (value) => setState(() => _applyToAll = value ?? false),
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '对剩余的 ${widget.remaining} 个冲突应用此选择',
                style: TextStyle(
                  fontSize: AppMetrics.fontSmall,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: c.textSecondary),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _resolve(ConflictResolution.skip),
          style: TextButton.styleFrom(foregroundColor: c.textPrimary),
          child: const Text('跳过'),
        ),
        TextButton(
          onPressed: () => _resolve(ConflictResolution.keepBoth),
          style: TextButton.styleFrom(foregroundColor: c.textPrimary),
          child: const Text('保留两者'),
        ),
        FilledButton(
          onPressed: () => _resolve(ConflictResolution.replace),
          child: const Text('替换'),
        ),
      ],
    );
  }
}
