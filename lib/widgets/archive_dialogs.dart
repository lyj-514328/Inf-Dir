import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/archive_service.dart';
import '../services/shell_file_operation.dart';
import 'app_theme.dart';

/// 创建压缩包对话框的确认结果。
class CreateArchiveOptions {
  const CreateArchiveOptions({
    required this.archivePath,
    required this.format,
    required this.compressionLevel,
    this.password,
    this.encryptHeaders = false,
  });

  final String archivePath;
  final ArchiveFormat format;
  final int compressionLevel;
  final String? password;
  final bool encryptHeaders;
}

/// 解压对话框的确认结果。
class ExtractArchiveOptions {
  const ExtractArchiveOptions({
    required this.destination,
    this.password,
    this.overwrite = ArchiveOverwriteMode.overwrite,
    this.openWhenDone = false,
    this.codePage,
  });

  final String destination;
  final String? password;
  final ArchiveOverwriteMode overwrite;
  final bool openWhenDone;
  final int? codePage;
}

const List<(String, int)> _compressionLevels = [
  ('无压缩', 0),
  ('最快', 1),
  ('快速', 3),
  ('标准', 5),
  ('最大', 7),
  ('极限', 9),
];

const List<(String, int)> _zipCodePages = [
  ('自动（UTF-8）', 0),
  ('GBK（936）', 936),
  ('Big5（950）', 950),
  ('Shift-JIS（932）', 932),
];

/// 去掉用户可能手输的归档扩展名，最终扩展名由格式决定。
String _stripArchiveExtension(String name) {
  final lower = name.toLowerCase();
  for (final ext in const ['.7z', '.zip']) {
    if (lower.endsWith(ext)) {
      return name.substring(0, name.length - ext.length);
    }
  }
  return name;
}

/// 让扩展名跟随格式下拉框：去掉旧归档扩展名后追加新扩展名。
String _withExtension(String path, ArchiveFormat format) {
  return '${_stripArchiveExtension(path)}.${format.extension}';
}

Future<CreateArchiveOptions?> showCreateArchiveDialog(
  BuildContext context, {
  required String initialName,
  required String directory,
}) {
  final initialPath = _withExtension(
    p.join(directory, _stripArchiveExtension(initialName)),
    ArchiveFormat.zip,
  );
  final pathController = TextEditingController(text: initialPath);
  final passwordController = TextEditingController();
  var format = ArchiveFormat.zip;
  var compressionLevel = 5;
  var encryptHeaders = false;

  return showDialog<CreateArchiveOptions>(
    context: context,
    builder: (ctx) {
      final c = context.colors;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('创建压缩包'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pathController,
                          autofocus: true,
                          decoration: _decoration(c, label: '路径'),
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: () {
                          try {
                            final picked = ShellFileOperation.pickFolder(
                              initialPath: p.dirname(pathController.text),
                            );
                            if (picked != null) {
                              pathController.text = p.join(
                                picked,
                                p.basename(pathController.text),
                              );
                            }
                          } on Object {
                            // 原生目录选择器不可用时静默忽略，用户仍可手输路径。
                          }
                        },
                        child: const Text('浏览…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ArchiveFormat>(
                    initialValue: format,
                    decoration: _decoration(c, label: '格式'),
                    items: const [
                      DropdownMenuItem(
                        value: ArchiveFormat.zip,
                        child: Text('Zip'),
                      ),
                      DropdownMenuItem(
                        value: ArchiveFormat.sevenZip,
                        child: Text('7z'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        format = value ?? ArchiveFormat.zip;
                        pathController.text = _withExtension(
                          pathController.text,
                          format,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: compressionLevel,
                    decoration: _decoration(c, label: '压缩级别'),
                    items: [
                      for (final (label, value) in _compressionLevels)
                        DropdownMenuItem(value: value, child: Text(label)),
                    ],
                    onChanged: (value) {
                      setState(() => compressionLevel = value ?? 5);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: _decoration(c, label: '密码（可选）'),
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textPrimary,
                    ),
                  ),
                  if (format == ArchiveFormat.sevenZip) ...[
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: encryptHeaders,
                      onChanged: (value) {
                        setState(() => encryptHeaders = value ?? false);
                      },
                      title: Text(
                        '加密文件名',
                        style: TextStyle(
                          fontSize: AppMetrics.fontSmall,
                          color: c.textPrimary,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  var archivePath = pathController.text.trim();
                  if (archivePath.isEmpty) archivePath = initialPath;
                  archivePath = _withExtension(archivePath, format);
                  Navigator.pop(
                    ctx,
                    CreateArchiveOptions(
                      archivePath: archivePath,
                      format: format,
                      compressionLevel: compressionLevel,
                      password: passwordController.text.trim(),
                      encryptHeaders: encryptHeaders,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppMetrics.controlRadius,
                    ),
                  ),
                ),
                child: const Text('创建'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<ExtractArchiveOptions?> showExtractArchiveDialog(
  BuildContext context, {
  required String archivePath,
  required String defaultDestination,
}) {
  final destinationController = TextEditingController(text: defaultDestination);
  final passwordController = TextEditingController();
  var overwrite = ArchiveOverwriteMode.overwrite;
  var openWhenDone = false;
  var codePage = 0;
  final isZip = archivePath.toLowerCase().endsWith('.zip');

  return showDialog<ExtractArchiveOptions>(
    context: context,
    builder: (ctx) {
      final c = context.colors;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('解压文件'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: destinationController,
                          decoration: _decoration(c, label: '目标文件夹'),
                          style: TextStyle(
                            fontSize: AppMetrics.fontBody,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: () {
                          try {
                            final picked = ShellFileOperation.pickFolder(
                              initialPath: destinationController.text.trim(),
                            );
                            if (picked != null) {
                              destinationController.text = picked;
                            }
                          } on Object {
                            // 原生目录选择器不可用时静默忽略，用户仍可手输路径。
                          }
                        },
                        child: const Text('浏览…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ArchiveOverwriteMode>(
                    initialValue: overwrite,
                    decoration: _decoration(c, label: '已存在同名文件'),
                    items: const [
                      DropdownMenuItem(
                        value: ArchiveOverwriteMode.overwrite,
                        child: Text('覆盖'),
                      ),
                      DropdownMenuItem(
                        value: ArchiveOverwriteMode.skip,
                        child: Text('跳过'),
                      ),
                      DropdownMenuItem(
                        value: ArchiveOverwriteMode.keepBoth,
                        child: Text('保留两者'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(
                        () =>
                            overwrite = value ?? ArchiveOverwriteMode.overwrite,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: _decoration(c, label: '密码（可选）'),
                    style: TextStyle(
                      fontSize: AppMetrics.fontBody,
                      color: c.textPrimary,
                    ),
                  ),
                  if (isZip) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: codePage,
                      decoration: _decoration(c, label: 'ZIP 名称编码'),
                      items: [
                        for (final (label, value) in _zipCodePages)
                          DropdownMenuItem(value: value, child: Text(label)),
                      ],
                      onChanged: (value) {
                        setState(() => codePage = value ?? 0);
                      },
                    ),
                  ],
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: openWhenDone,
                    onChanged: (value) {
                      setState(() => openWhenDone = value ?? false);
                    },
                    title: Text(
                      '解压完成后打开目标文件夹',
                      style: TextStyle(
                        fontSize: AppMetrics.fontSmall,
                        color: c.textPrimary,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  var destination = destinationController.text.trim();
                  if (destination.isEmpty) destination = defaultDestination;
                  Navigator.pop(
                    ctx,
                    ExtractArchiveOptions(
                      destination: destination,
                      password: passwordController.text.trim(),
                      overwrite: overwrite,
                      openWhenDone: openWhenDone,
                      codePage: codePage == 0 ? null : codePage,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppMetrics.controlRadius,
                    ),
                  ),
                ),
                child: const Text('解压'),
              ),
            ],
          );
        },
      );
    },
  );
}

InputDecoration _decoration(AppColors c, {required String label}) {
  return InputDecoration(
    isDense: true,
    labelText: label,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      borderSide: BorderSide(color: c.borderStrong),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      borderSide: BorderSide(color: c.accent),
    ),
  );
}
