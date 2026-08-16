import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../features/quick_view/quick_view_service.dart';
import '../models/file_drag_payload.dart';
import '../models/file_entry.dart';
import '../models/file_operation_history.dart';
import '../models/file_operation_task.dart';
import '../models/layout_node.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import '../state/pane_controller.dart';
import '../services/archive_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/directory_service.dart';
import '../services/file_service.dart';
import '../services/file_drop_service.dart';
import '../services/incremental_refresh.dart';
import '../services/shell_context_menu.dart';
import '../services/shell_new_service.dart';
import '../services/open_with_menu_service.dart';
import 'app_theme.dart';
import 'archive_dialogs.dart';
import 'conflict_dialog.dart';
import 'file_list_view.dart';
import 'address_bar.dart';
import 'command_menu.dart';
import 'file_context_menu.dart';
import 'nav_toolbar.dart';
import 'pane_tab_bar.dart';
import 'home_view.dart';
import 'search_dialog.dart';

bool matchesSearchShortcut(KeyEvent event, HardwareKeyboard keyboard) {
  return event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyF &&
      keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isShiftPressed;
}

/// How to resolve a name collision when restoring Recycle Bin items.
enum _CollisionChoice { skip, keepBoth, replace }

class FilePane extends StatelessWidget {
  final String paneId;
  final bool Function(String path)? cloudZoneResolver;

  const FilePane({super.key, required this.paneId, this.cloudZoneResolver});

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutState>();
    final node = layoutState.allPaneNodes.firstWhere(
      (n) => n.paneId == paneId,
      orElse: () => layoutState.allPaneNodes.first,
    );
    final controller = layoutState.controllerFor(node);

    if (controller == null) return const SizedBox.shrink();

    return ChangeNotifierProvider<PaneController>.value(
      value: controller,
      child: _PaneContent(paneNode: node, cloudZoneResolver: cloudZoneResolver),
    );
  }
}

void copyPaneSelection(BuildContext context, PaneController controller) {
  if (controller.selectedPaths.isEmpty) return;
  final paths = controller.selectedPaths.toList();
  context.read<AppState>().copyPaths(paths);
  Clipboard.setData(ClipboardData(text: paths.join('\n')));
}

void cutPaneSelection(BuildContext context, PaneController controller) {
  if (controller.selectedPaths.isEmpty) return;
  context.read<AppState>().cutPaths(controller.selectedPaths.toList());
}

Future<void> pasteIntoPane(
  BuildContext context,
  PaneController controller,
) async {
  final appState = context.read<AppState>();
  if (!appState.hasClipboard) return;

  final sources = appState.clipboardPaths;
  final isCut = appState.clipboardIsCut;
  final transferred = await transferPathsIntoPane(
    context,
    controller,
    sources: sources,
    move: isCut,
  );
  if (transferred && context.mounted && isCut) {
    appState.clearClipboard();
  }
}

Future<bool> transferPathsIntoPane(
  BuildContext context,
  PaneController controller, {
  required List<String> sources,
  required bool move,
  String? destination,
}) async {
  final appState = context.read<AppState>();
  final destDir = destination ?? controller.currentPath;

  // Cannot transfer into the Recycle Bin or another virtual shell location.
  if (FileService.isSpecialPath(destDir) || sources.isEmpty) {
    return false;
  }

  // 目标位置存在同名项目时，先让用户决定冲突策略。
  final conflictNames = FileService.detectConflicts(
    sources,
    destDir,
  ).map((path) => p.basename(path)).toList(growable: false);
  Map<String, ConflictResolution>? resolutions;
  if (conflictNames.isNotEmpty) {
    resolutions = await resolveFileConflicts(
      context,
      conflictNames: conflictNames,
      destination: destDir,
    );
    if (resolutions == null || !context.mounted) return false; // 用户取消
  }

  final replaceSources = <String>[];
  final keepBothSources = <String>[];
  final skipped = <String>[];
  for (final source in sources) {
    final resolution =
        resolutions?[p.basename(source).toLowerCase()] ??
        ConflictResolution.replace;
    switch (resolution) {
      case ConflictResolution.replace:
        replaceSources.add(source);
      case ConflictResolution.keepBoth:
        keepBothSources.add(source);
      case ConflictResolution.skip:
        skipped.add(source);
    }
  }

  final movedPaths = <String>[...replaceSources, ...keepBothSources];
  if (movedPaths.isEmpty) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('已跳过 ${skipped.length} 个冲突项')));
    return false;
  }

  // 一个任务内按策略分组执行：替换组默认覆盖，保留两者组让 Shell 自动
  // 改名；进度按组加权聚合到总任务进度。
  late FileOperationTask completedTask;
  try {
    completedTask = await appState.fileOperations.enqueue(
      type: move ? FileOperationType.move : FileOperationType.copy,
      sources: sources,
      destination: destDir,
      action: (task) async {
        final total = movedPaths.length;
        var done = 0;
        final results = <FileOperationItemResult>[];
        final run = move ? FileService.moveEntries : FileService.copyEntries;
        if (replaceSources.isNotEmpty) {
          results.addAll(
            await run(
              replaceSources,
              destDir,
              cancelRequested: () => task.cancelRequested,
              onProgress: (value) => task.updateProgress(
                (done + replaceSources.length * value) / total,
              ),
            ),
          );
          done += replaceSources.length;
        }
        if (keepBothSources.isNotEmpty) {
          results.addAll(
            await run(
              keepBothSources,
              destDir,
              keepBothOnCollision: true,
              cancelRequested: () => task.cancelRequested,
              onProgress: (value) => task.updateProgress(
                (done + keepBothSources.length * value) / total,
              ),
            ),
          );
          done += keepBothSources.length;
        }
        task.recordItemResults(results);
        task.updateProgress(1);
      },
    );
  } catch (_) {
    controller.refresh();
    return false;
  }
  if (!context.mounted) return false;
  // 录制历史：逐项实际新路径（createdPath 覆盖"保留两者"的自动改名）。
  final itemResults = completedTask.itemResults;
  final historySources = <String>[];
  final historyDestinations = <String>[];
  for (var i = 0; i < movedPaths.length; i++) {
    final result = i < itemResults.length ? itemResults[i] : null;
    if (result != null && !result.isSuccess) continue;
    historySources.add(movedPaths[i]);
    historyDestinations.add(
      result?.createdPath ?? p.join(destDir, p.basename(movedPaths[i])),
    );
  }
  if (historySources.isNotEmpty) {
    appState.history.record(
      FileOperationHistory(
        type: move ? HistoryOperationType.move : HistoryOperationType.copy,
        source: historySources,
        destination: historyDestinations,
      ),
    );
  }
  final addedPaths = [
    for (final source in replaceSources) p.join(destDir, p.basename(source)),
  ];
  if (keepBothSources.isNotEmpty) {
    // 保留两者时 Shell 生成的新名称无法预测：目标面板整目录刷新，
    // 目标目录缓存定点失效（无法打补丁）。
    controller.refresh();
    _applyIncrementalRefresh(
      context,
      addedPaths: addedPaths,
      removedPaths: move ? movedPaths : const [],
      invalidateDirs: [destDir],
    );
  } else {
    _applyIncrementalRefresh(
      context,
      addedPaths: addedPaths,
      removedPaths: move ? movedPaths : const [],
    );
  }
  return true;
}

/// 操作完成后的增量刷新（context 便捷版）：读取 provider 后委托共享助手。
void _applyIncrementalRefresh(
  BuildContext context, {
  Iterable<String> addedPaths = const [],
  Iterable<String> removedPaths = const [],
  Iterable<String> invalidateDirs = const [],
}) {
  applyIncrementalRefresh(
    appState: context.read<AppState>(),
    layoutState: context.read<LayoutState>(),
    addedPaths: addedPaths,
    removedPaths: removedPaths,
    invalidateDirs: invalidateDirs,
  );
}

class _PaneContent extends StatelessWidget {
  final LayoutNode paneNode;
  final bool Function(String path)? cloudZoneResolver;

  const _PaneContent({required this.paneNode, required this.cloudZoneResolver});

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final controller = context.read<PaneController>();
    final layoutState = context.watch<LayoutState>();
    final isActive = layoutState.focusedNodeId == paneNode.id;

    final c = context.colors;
    final result = Column(
      children: [
        Container(
          color: c.surfaceSubtle,
          child: Column(
            children: [
              _PaneTabBarSection(paneId: paneNode.paneId!),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppMetrics.paneGap,
                  1,
                  AppMetrics.paneGap,
                  5,
                ),
                child: const _PaneLocationSection(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PaneDropTarget(
            paneId: paneNode.paneId!,
            controller: controller,
            onDrop: (payload, operation) async {
              layoutState.focusNode(paneNode);
              await transferPathsIntoPane(
                context,
                controller,
                sources: payload.paths,
                move: operation == FileDropOperation.move,
              );
            },
            child: controller.isHome
                ? HomeView(
                    controller: controller,
                    onNavigate: controller.navigateTo,
                    showFileExtensions: context
                        .watch<AppState>()
                        .showFileExtensions,
                  )
                : Focus(
                    autofocus: false,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        final keyboard = HardwareKeyboard.instance;
                        if (event.logicalKey == LogicalKeyboardKey.backspace ||
                            (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                                keyboard.isAltPressed)) {
                          controller.goUp();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                            keyboard.isAltPressed) {
                          controller.goBack();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                            keyboard.isAltPressed) {
                          controller.goForward();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.f5) {
                          controller.refresh();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyA &&
                            keyboard.isControlPressed) {
                          controller.selectAll();
                          return KeyEventResult.handled;
                        }
                        if (matchesSearchShortcut(event, keyboard)) {
                          if (!controller.isHome &&
                              !FileService.isSpecialPath(
                                controller.currentPath,
                              )) {
                            _openSearch(context, controller);
                          }
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter) {
                          _openSelected(context, controller);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.delete) {
                          if (FileService.isRecycleBinPath(
                            controller.currentPath,
                          )) {
                            _deleteRecycleBinSelection(context);
                          } else {
                            _deleteSelected(
                              context,
                              permanent: keyboard.isShiftPressed,
                            );
                          }
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.f2) {
                          if (!FileService.isRecycleBinPath(
                            controller.currentPath,
                          )) {
                            _renameSelected(context);
                          }
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyC &&
                            keyboard.isControlPressed &&
                            keyboard.isShiftPressed) {
                          _copySelectedPaths(context);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyC &&
                            keyboard.isControlPressed &&
                            !keyboard.isShiftPressed) {
                          _copySelected(context);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyX &&
                            keyboard.isControlPressed) {
                          if (FileService.isRecycleBinPath(
                            controller.currentPath,
                          )) {
                            return KeyEventResult.handled;
                          }
                          _cutSelected(context);
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.keyV &&
                            keyboard.isControlPressed) {
                          if (FileService.isRecycleBinPath(
                            controller.currentPath,
                          )) {
                            return KeyEventResult.handled;
                          }
                          _paste(context);
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (focusContext) => Listener(
                        onPointerDown: (_) {
                          Focus.of(focusContext).requestFocus();
                        },
                        child: _FileListSection(
                          isActive: isActive,
                          cloudZoneResolver: cloudZoneResolver,
                          onItemContextMenu: (path, position) =>
                              _openItemContextMenu(context, path, position),
                          onFolderContextMenu: (position) =>
                              _openFolderContextMenu(context, position),
                          onFolderDrop: (payload, directory, operation) async {
                            layoutState.focusNode(paneNode);
                            await transferPathsIntoPane(
                              context,
                              controller,
                              sources: payload.paths,
                              move: operation == FileDropOperation.move,
                              destination: directory.path,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (!controller.isHome) const _StatusBarSection(),
      ],
    );

    sw.stop();
    if (sw.elapsedMilliseconds > 10) {
      debugPrint(
        '[Perf] _PaneContent build: ${sw.elapsedMilliseconds}ms, entries=${controller.entries.length}',
      );
    }
    return result;
  }

  // ── Open / Navigate ────────────────────────────────────────────────

  Future<void> _createFolder(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建文件夹',
      initialValue: '新建文件夹',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final newPath = await FileService.createFolder(
        controller.currentPath,
        name.trim(),
      );
      if (!context.mounted) return;
      _applyIncrementalRefresh(context, addedPaths: [newPath]);
      context.read<AppState>().history.record(
        FileOperationHistory(
          type: HistoryOperationType.createNew,
          source: [newPath],
          directories: [true],
        ),
      );
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件夹失败', e);
    }
  }

  Future<void> _createFile(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建文件',
      initialValue: '新建文件',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final newPath = await FileService.createFile(
        controller.currentPath,
        name.trim(),
      );
      if (!context.mounted) return;
      _applyIncrementalRefresh(context, addedPaths: [newPath]);
      context.read<AppState>().history.record(
        FileOperationHistory(
          type: HistoryOperationType.createNew,
          source: [newPath],
          directories: [false],
        ),
      );
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件失败', e);
    }
  }

  List<ShellNewEntry> _shellNewEntries(BuildContext context) {
    final iconSize = (AppMetrics.iconMd * View.of(context).devicePixelRatio)
        .ceil();
    try {
      return ShellNewService.getEntries(iconSize);
    } on Object {
      return const [];
    }
  }

  Future<void> _createShortcutFromDialog(BuildContext context) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }

    final target = await _showInputDialog(
      context,
      title: '创建快捷方式',
      initialValue: '',
      confirmText: '下一步',
    );
    if (target == null || target.trim().isEmpty || !context.mounted) return;

    final normalizedTarget = target.trim().replaceAll('"', '');
    final targetName = p.basename(normalizedTarget);
    final name = await _showInputDialog(
      context,
      title: '快捷方式名称',
      initialValue: targetName.isEmpty ? '新建快捷方式' : targetName,
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await FileService.createShortcutIn(
        normalizedTarget,
        controller.currentPath,
        name: name,
      );
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建快捷方式失败', e);
    }
  }

  Future<void> _createFromTemplate(
    BuildContext context,
    ShellNewEntry entry,
  ) async {
    final controller = context.read<PaneController>();
    if (controller.isHome ||
        FileService.isSpecialPath(controller.currentPath)) {
      return;
    }
    if (entry.isCommandBased) {
      try {
        await ShellNewService.create(controller.currentPath, entry, '');
        controller.refresh();
      } catch (e) {
        if (context.mounted) _showOperationError(context, '创建文件失败', e);
      }
      return;
    }
    final name = await _showInputDialog(
      context,
      title: '新建${entry.name}',
      initialValue: '新建 ${entry.name}',
      confirmText: '创建',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ShellNewService.create(controller.currentPath, entry, name.trim());
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件失败', e);
    }
  }

  Future<void> _openItemContextMenu(
    BuildContext context,
    String clickedPath,
    Offset position,
  ) async {
    final controller = context.read<PaneController>();

    // Preserve a multi-selection when right-clicking one of its items.
    if (!controller.selectedPaths.contains(clickedPath)) {
      controller.selectSingle(clickedPath);
    }

    final paths = controller.selectedPaths.toList();
    final singlePath = paths.length == 1 ? paths.first : null;
    final singleEntry = singlePath == null
        ? null
        : _findEntry(controller, singlePath);
    final isRecycleBin = FileService.isRecycleBinPath(controller.currentPath);
    final canModify =
        paths.isNotEmpty && !FileService.isSpecialPath(controller.currentPath);
    final isDir = singleEntry?.isDirectory ?? false;
    final canOpenDir = singleEntry != null && isDir && !isRecycleBin;
    final canOpenFile = singleEntry != null && !isDir && !isRecycleBin;
    final menuIconSize = (AppMetrics.iconMd * View.of(context).devicePixelRatio)
        .ceil();
    final openWithData = canOpenFile
        ? _buildOpenWithMenu(singlePath!, menuIconSize)
        : null;

    String? compressName;
    if (canModify) {
      compressName = (singleEntry != null && !singleEntry.isDirectory)
          ? p.basenameWithoutExtension(paths.first)
          : p.basename(paths.first);
    }

    final singleArchive =
        canModify &&
        singleEntry != null &&
        !singleEntry.isDirectory &&
        isArchiveName(singleEntry.name);
    final extractName = singleArchive
        ? p.basenameWithoutExtension(singleEntry.name)
        : null;

    if (isRecycleBin) {
      showCommandMenu(
        context,
        position: position,
        items: buildRecycleBinItemContextMenuItems(
          onRestore: () => _restoreRecycleBinSelection(context),
          onDeletePermanently: () => _deleteRecycleBinSelection(context),
          onProperties: () => _showPropertiesVerb(context, paths),
          onShowMoreOptions: () => _showNativeMenu(context, paths, position),
        ),
      );
      return;
    }

    showCommandMenu(
      context,
      position: position,
      items: buildFileItemContextMenuItems(
        onOpen: singleEntry != null && !isRecycleBin
            ? () => _handleDoubleTap(context, controller, singlePath!)
            : null,
        openImage: openWithData?.defaultAppImage,
        onOpenWith: canOpenFile ? () => _openWith(context, singlePath!) : null,
        openWithChildren: openWithData?.items,
        onQuickView: canOpenFile
            ? () => _openQuickView(context, singlePath!)
            : null,
        onOpenInNewTab: canOpenDir
            ? () => controller.addTab(singlePath!)
            : null,
        onOpenInNewPane: canOpenDir
            ? (direction) => _openInNewPane(context, direction, singlePath!)
            : null,
        onCut: canModify ? () => _cutSelected(context) : null,
        onCopy: canModify ? () => _copySelected(context) : null,
        onRename: canModify && paths.length == 1
            ? () => _renameSelected(context)
            : null,
        onDelete: canModify ? () => _deleteSelected(context) : null,
        onPasteShortcut: canModify && context.read<AppState>().hasClipboard
            ? () => _pasteShortcut(context)
            : null,
        onCopyPath: () => _copySelectedPaths(context),
        onCreateFolderWithSelection: canModify
            ? () => _createFolderWithSelection(context)
            : null,
        onCreateShortcut: canModify ? () => _createShortcuts(context) : null,
        compressName: compressName,
        onCompressZip: canModify ? () => _compressZip(context) : null,
        onCompress7z: canModify ? () => _compress7z(context) : null,
        onCompressDialog: canModify ? () => _compressDialog(context) : null,
        onExtractFiles: singleArchive
            ? () => _extractFiles(context, singlePath!)
            : null,
        onExtractHere: singleArchive
            ? () => _extractHere(context, singlePath!)
            : null,
        onExtractToFolder: singleArchive
            ? () => _extractToFolder(context, singlePath!)
            : null,
        extractName: extractName,
        onOpenInTerminal: canOpenDir
            ? () => _openTerminal(context, singlePath!)
            : null,
        onProperties: canModify
            ? () => _showPropertiesVerb(context, paths)
            : null,
        onShowMoreOptions: () => _showNativeMenu(context, paths, position),
      ),
    );
  }

  void _openFolderContextMenu(BuildContext context, Offset position) {
    final controller = context.read<PaneController>();
    final appState = context.read<AppState>();
    controller.clearSelection();

    if (FileService.isRecycleBinPath(controller.currentPath)) {
      showCommandMenu(
        context,
        position: position,
        items: buildRecycleBinFolderContextMenuItems(
          sortColumn: controller.sortColumn,
          sortAscending: controller.sortAscending,
          viewMode: controller.viewMode,
          groupBy: controller.groupBy,
          groupAscending: controller.groupAscending,
          canSelectAll: controller.visibleEntries.isNotEmpty,
          canEmpty: controller.entries.isNotEmpty,
          canRestoreAll: controller.entries.isNotEmpty,
          onSortColumn: controller.setSortColumn,
          onSortAscending: controller.setSortAscending,
          onViewMode: controller.setViewMode,
          onGroupBy: controller.setGroupBy,
          onGroupAscending: controller.setGroupAscending,
          onRefresh: controller.refresh,
          onRestoreAll: () => _restoreAllRecycleBin(context),
          onEmptyRecycleBin: () => _emptyRecycleBin(context),
          onSelectAll: controller.selectAll,
          onShowMoreOptions: () => _showNativeMenu(context, const [], position),
        ),
      );
      return;
    }

    final canWrite = !FileService.isSpecialPath(controller.currentPath);
    showCommandMenu(
      context,
      position: position,
      items: buildFolderContextMenuItems(
        sortColumn: controller.sortColumn,
        sortAscending: controller.sortAscending,
        viewMode: controller.viewMode,
        groupBy: controller.groupBy,
        groupAscending: controller.groupAscending,
        canWrite: canWrite,
        canPaste: canWrite && appState.hasClipboard,
        canSelectAll: controller.visibleEntries.isNotEmpty,
        onSortColumn: controller.setSortColumn,
        onSortAscending: controller.setSortAscending,
        onViewMode: controller.setViewMode,
        onGroupBy: controller.setGroupBy,
        onGroupAscending: controller.setGroupAscending,
        onRefresh: controller.refresh,
        onCreateFolder: () => _createFolder(context),
        onCreateFile: () => _createFile(context),
        onCreateShortcut: () => _createShortcutFromDialog(context),
        shellNewEntries: _shellNewEntries(context),
        onCreateFromTemplate: (entry) => _createFromTemplate(context, entry),
        onPaste: () => _paste(context),
        onSelectAll: controller.selectAll,
        onOpenInTerminal: canWrite
            ? () => _openTerminal(context, controller.currentPath)
            : null,
        onShowMoreOptions: () => _showNativeMenu(context, const [], position),
      ),
    );
  }

  Future<void> _openQuickView(BuildContext context, String path) async {
    final result = await context.read<QuickViewService>().open(path);
    if (!context.mounted || result.started) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openSearch(
    BuildContext context,
    PaneController controller,
  ) async {
    final result = await showDialog<SearchDialogResult>(
      context: context,
      builder: (_) => SearchDialog(rootPath: controller.currentPath),
    );
    if (!context.mounted || result == null) return;

    if (result.isDirectory) {
      await controller.navigateTo(result.path);
    } else {
      await FileService.openFile(result.path);
    }
  }

  Future<void> _openWith(BuildContext context, String path) async {
    try {
      await FileService.openWithDialog(path);
    } catch (e) {
      if (context.mounted) _showOperationError(context, '打开方式失败', e);
    }
  }

  _OpenWithMenu? _buildOpenWithMenu(String path, int iconSize) {
    try {
      final data = OpenWithMenuService.getData(path, iconSize: iconSize);
      final items = data.entries.isEmpty
          ? null
          : <CommandMenuItem>[
              for (final entry in data.entries)
                if (entry.isDivider)
                  const CommandMenuItem.divider()
                else
                  CommandMenuItem(
                    image: entry.iconPng == null
                        ? null
                        : MemoryImage(entry.iconPng!),
                    label: entry.label,
                    enabled: entry.enabled,
                    onAction: () => OpenWithMenuService.invoke(entry.commandId),
                  ),
              const CommandMenuItem.divider(),
              CommandMenuItem(
                icon: Icons.add_circle_outline,
                label: '选择其他应用',
                onAction: () => FileService.openWithDialog(path),
              ),
            ];
      return _OpenWithMenu(
        defaultAppImage: data.defaultAppIconPng == null
            ? null
            : MemoryImage(data.defaultAppIconPng!),
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInNewPane(
    BuildContext context,
    SplitDirection direction,
    String path,
  ) async {
    final newController = context.read<LayoutState>().splitPane(
      paneNode,
      direction,
    );
    if (newController != null) await newController.navigateTo(path);
  }

  Future<void> _pasteShortcut(BuildContext context) async {
    final appState = context.read<AppState>();
    final controller = context.read<PaneController>();
    try {
      for (final path in appState.clipboardPaths) {
        await FileService.createShortcutIn(path, controller.currentPath);
      }
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '粘贴快捷方式失败', e);
    }
  }

  Future<void> _createFolderWithSelection(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    try {
      await FileService.createFolderWithSelection(
        paths,
        controller.currentPath,
      );
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建文件夹失败', e);
    }
  }

  Future<void> _createShortcuts(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    try {
      for (final path in paths) {
        await FileService.createShortcutIn(path, controller.currentPath);
      }
      controller.refresh();
    } catch (e) {
      if (context.mounted) _showOperationError(context, '创建快捷方式失败', e);
    }
  }

  Future<void> _compressZip(BuildContext context) async {
    await _compress(context, ArchiveFormat.zip);
  }

  Future<void> _compress7z(BuildContext context) async {
    await _compress(context, ArchiveFormat.sevenZip);
  }

  Future<void> _compressDialog(BuildContext context) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    final first = _findEntry(controller, paths.first);
    final base = (first != null && !first.isDirectory)
        ? p.basenameWithoutExtension(paths.first)
        : p.basename(paths.first);
    final options = await showCreateArchiveDialog(
      context,
      initialName: base,
      directory: controller.currentPath,
    );
    if (options == null || !context.mounted) return;
    await _compressWithOptions(context, paths, options);
  }

  Future<void> _compress(BuildContext context, ArchiveFormat format) async {
    final controller = context.read<PaneController>();
    final paths = controller.selectedPaths.toList();
    if (paths.isEmpty) return;
    final first = _findEntry(controller, paths.first);
    final base = (first != null && !first.isDirectory)
        ? p.basenameWithoutExtension(paths.first)
        : p.basename(paths.first);
    await _compressWithOptions(
      context,
      paths,
      CreateArchiveOptions(
        archivePath: p.join(
          controller.currentPath,
          '$base.${format.extension}',
        ),
        format: format,
        compressionLevel: 5,
      ),
    );
  }

  Future<void> _compressWithOptions(
    BuildContext context,
    List<String> paths,
    CreateArchiveOptions options,
  ) async {
    final controller = context.read<PaneController>();
    final operationCenter = context.read<AppState>().fileOperations;
    // 对齐 Files：目标已存在时追加 " (2)"、" (3)"，绝不覆盖/合并进已有压缩包。
    final target = _uniquePath(options.archivePath);
    try {
      await operationCenter.enqueue(
        type: FileOperationType.compress,
        sources: paths,
        destination: target,
        action: (task) async {
          await ArchiveService().createArchive(
            paths,
            target,
            format: options.format,
            compressionLevel: options.compressionLevel,
            password: options.password,
            encryptHeaders: options.encryptHeaders,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
        },
      );
      controller.refresh();
    } catch (e) {
      // 目标名是唯一的新路径，创建失败时删除残留的部分压缩包。
      try {
        final partial = File(target);
        if (partial.existsSync()) partial.deleteSync();
      } on Object {
        // 删除失败不影响错误提示。
      }
      if (context.mounted) _showOperationError(context, '压缩失败', e);
    }
  }

  /// 返回一个不存在的目标路径：若 [path] 已存在，则在扩展名前追加
  /// " (2)"、" (3)"，直到找到空闲名称（对齐 Files 的 GenerateUniqueName）。
  static String _uniquePath(String path) {
    if (!File(path).existsSync() && !Directory(path).existsSync()) return path;
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    for (var i = 2; ; i++) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!File(candidate).existsSync() && !Directory(candidate).existsSync()) {
        return candidate;
      }
    }
  }

  Future<void> _extractFiles(BuildContext context, String archivePath) async {
    final defaultDestination = _uniquePath(
      p.join(p.dirname(archivePath), p.basenameWithoutExtension(archivePath)),
    );
    final options = await showExtractArchiveDialog(
      context,
      archivePath: archivePath,
      defaultDestination: defaultDestination,
    );
    if (options == null || !context.mounted) return;
    await _extract(context, archivePath, options);
  }

  Future<void> _extractHere(BuildContext context, String archivePath) async {
    final controller = context.read<PaneController>();
    await _extract(
      context,
      archivePath,
      ExtractArchiveOptions(destination: controller.currentPath),
    );
  }

  Future<void> _extractToFolder(
    BuildContext context,
    String archivePath,
  ) async {
    final destination = _uniquePath(
      p.join(p.dirname(archivePath), p.basenameWithoutExtension(archivePath)),
    );
    await _extract(
      context,
      archivePath,
      ExtractArchiveOptions(destination: destination),
    );
  }

  Future<void> _extract(
    BuildContext context,
    String archivePath,
    ExtractArchiveOptions options,
  ) async {
    final controller = context.read<PaneController>();
    final operationCenter = context.read<AppState>().fileOperations;
    try {
      await operationCenter.enqueue(
        type: FileOperationType.extract,
        sources: [archivePath],
        destination: options.destination,
        action: (task) async {
          await ArchiveService().extractArchive(
            archivePath,
            options.destination,
            password: options.password,
            overwrite: options.overwrite,
            codePage: options.codePage,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
        },
      );
      controller.refresh();
      if (options.openWhenDone && context.mounted) {
        await FileService.openFile(options.destination);
      }
    } catch (e) {
      if (context.mounted) _showOperationError(context, '解压失败', e);
    }
  }

  Future<void> _openTerminal(BuildContext context, String dirPath) async {
    try {
      await FileService.openTerminal(dirPath);
    } catch (e) {
      if (context.mounted) _showOperationError(context, '打开终端失败', e);
    }
  }

  void _showPropertiesVerb(BuildContext context, List<String> paths) {
    final controller = context.read<PaneController>();
    ShellOperations.invokeVerb(
      folderPath: controller.currentPath,
      selectedPaths: paths,
      verb: 'properties',
    );
  }

  void _openSelected(BuildContext context, PaneController controller) {
    // In the Recycle Bin, Enter does nothing
    if (FileService.isRecycleBinPath(controller.currentPath)) return;
    if (controller.selectedPaths.isEmpty) return;
    _handleDoubleTap(context, controller, controller.selectedPaths.first);
  }

  // ── Keyboard-triggered operations ──────────────────────────────────

  void _copySelected(BuildContext context) {
    copyPaneSelection(context, context.read<PaneController>());
  }

  void _copySelectedPaths(BuildContext context) {
    final paths = context.read<PaneController>().selectedPaths;
    if (paths.isEmpty) return;
    Clipboard.setData(
      ClipboardData(text: paths.map((path) => '"$path"').join('\n')),
    );
  }

  void _cutSelected(BuildContext context) {
    cutPaneSelection(context, context.read<PaneController>());
  }

  Future<void> _paste(BuildContext context) async {
    await pasteIntoPane(context, context.read<PaneController>());
  }

  Future<void> _deleteSelected(
    BuildContext context, {
    bool permanent = false,
  }) async {
    final controller = context.read<PaneController>();

    // In Recycle Bin, deletion is handled by the shell context menu
    if (FileService.isRecycleBinPath(controller.currentPath)) return;

    final selected = controller.selectedPaths.toList();
    if (selected.isEmpty) return;
    final operationCenter = context.read<AppState>().fileOperations;
    // 在删除前记录哪些是文件夹：删除后 stat 会失败。
    final deletedDirs = [
      for (final path in selected)
        if (_findEntry(controller, path)?.isDirectory ?? false) path,
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanent ? '永久删除' : '确认删除'),
        content: Text(
          selected.length == 1
              ? permanent
                    ? '确定要永久删除 "${_basename(selected.first)}" 吗？此操作无法撤销。'
                    : '确定要将 "${_basename(selected.first)}" 移到回收站吗？'
              : permanent
              ? '确定要永久删除 ${selected.length} 个项目吗？此操作无法撤销。'
              : '确定要将 ${selected.length} 个项目移到回收站吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: context.colors.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    late FileOperationTask completedTask;
    try {
      completedTask = await operationCenter.enqueue(
        type: permanent
            ? FileOperationType.permanentDelete
            : FileOperationType.delete,
        sources: selected,
        action: (task) async {
          final results = await FileService.deleteEntries(
            selected,
            permanent: permanent,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(results);
        },
      );
    } catch (error) {
      if (context.mounted) {
        _showOperationError(context, permanent ? '永久删除失败' : '移到回收站失败', error);
      }
      return;
    }
    if (!context.mounted) return;
    // 移入回收站：录制可撤销历史（recycledPath 来自原生回调）。
    if (!permanent) {
      final itemResults = completedTask.itemResults;
      final historySources = <String>[];
      final historyDestinations = <String>[];
      for (var i = 0; i < selected.length; i++) {
        final result = i < itemResults.length ? itemResults[i] : null;
        final recycled = result?.recycledPath;
        if (recycled == null || recycled.isEmpty) continue;
        historySources.add(selected[i]);
        historyDestinations.add(recycled);
      }
      // 原生回调未返回解析名时，枚举回收站按原目录 + 名称匹配兜底。
      for (var i = 0; i < selected.length; i++) {
        if (historySources.contains(selected[i])) continue;
        final parsed = FileService.findRecycledParsingName(selected[i]);
        if (parsed == null) continue;
        historySources.add(selected[i]);
        historyDestinations.add(parsed);
      }
      if (historySources.isNotEmpty) {
        context.read<AppState>().history.record(
          FileOperationHistory(
            type: HistoryOperationType.recycle,
            source: historySources,
            destination: historyDestinations,
          ),
        );
      }
    }
    // 被删除的文件夹：自身缓存整体作废；父目录缓存就地摘除条目。
    // 移入回收站时新条目名称未知，回收站缓存定点失效。
    _applyIncrementalRefresh(
      context,
      removedPaths: selected,
      invalidateDirs: [
        ...deletedDirs,
        if (!permanent) FileService.recycleBinShellPath,
      ],
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          permanent
              ? '已永久删除 ${selected.length} 个项目'
              : '已将 ${selected.length} 个项目移到回收站',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _restoreRecycleBinSelection(BuildContext context) async {
    final controller = context.read<PaneController>();
    final selected = controller.selectedPaths.toList();
    if (selected.isEmpty) return;

    final entries = selected
        .map((path) => _findEntry(controller, path))
        .whereType<FileEntry>()
        .toList(growable: false);
    await _restoreRecycleBinEntries(context, entries, dialogTitle: '还原项目');
  }

  Future<void> _restoreAllRecycleBin(BuildContext context) async {
    // Re-enumerate the whole bin: the pane may only hold a paged subset.
    final entries = DirectoryService.listDirectory(
      FileService.recycleBinShellPath,
    ).where((entry) => entry.parsingName != null).toList(growable: false);
    if (entries.isEmpty) return;
    await _restoreRecycleBinEntries(context, entries, dialogTitle: '全部还原');
  }

  /// Shared restore pipeline: confirmation (or location fallback when the
  /// original folder is gone), collision handling, then the shell restore.
  Future<void> _restoreRecycleBinEntries(
    BuildContext context,
    List<FileEntry> entries, {
    required String dialogTitle,
  }) async {
    if (entries.isEmpty) return;
    final parsingNames = entries
        .map((entry) => entry.parsingName)
        .whereType<String>()
        .toList(growable: false);
    if (parsingNames.length != entries.length) {
      _showOperationError(context, '还原失败', '无法解析所选回收站项目');
      return;
    }

    final plan = FileService.planRestoreDestinations(entries);
    String? fallback;
    if (plan.missing.isEmpty) {
      final confirm = await _showConfirmationDialog(
        context,
        title: dialogTitle,
        message: dialogTitle == '全部还原'
            ? '要将回收站中的所有项目还原到原始位置吗？'
            : entries.length == 1
            ? '要将“${entries.single.name}”还原到原始位置吗？'
            : '要将选中的 ${entries.length} 个项目还原到原始位置吗？',
        confirmText: '还原',
      );
      if (confirm != true || !context.mounted) return;
    } else {
      fallback = await _showRestoreLocationDialog(
        context,
        missingCount: plan.missing.length,
        sampleName: plan.missing.length == 1 ? plan.missing.single.name : null,
      );
      if (fallback == null || !context.mounted) return;
    }

    var destinations = fallback == null
        ? null
        : FileService.planRestoreDestinations(
            entries,
            fallback: fallback,
          ).destinations;

    // Collision handling: the shell silently replaces by default, so surface
    // the choice instead of overwriting the user's files unnoticed.
    var keepBothOnCollision = false;
    final collisions = FileService.planRestoreCollisions(
      entries,
      destinations: destinations,
    );
    if (collisions.isNotEmpty) {
      final choice = await _showCollisionDialog(
        context,
        collisionCount: collisions.length,
      );
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case _CollisionChoice.skip:
          final skipped = collisions.toSet();
          final keptEntries = <FileEntry>[];
          final keptDestinations = <String?>[];
          for (var i = 0; i < entries.length; i++) {
            if (skipped.contains(entries[i])) continue;
            keptEntries.add(entries[i]);
            keptDestinations.add(destinations?[i]);
          }
          if (keptEntries.isEmpty) return;
          entries
            ..clear()
            ..addAll(keptEntries);
          parsingNames
            ..clear()
            ..addAll(
              keptEntries.map((entry) => entry.parsingName).whereType<String>(),
            );
          destinations = keptDestinations;
          break;
        case _CollisionChoice.keepBoth:
          keepBothOnCollision = true;
          break;
        case _CollisionChoice.replace:
          break;
      }
    }

    try {
      final completedTask = await context
          .read<AppState>()
          .fileOperations
          .enqueue(
            type: FileOperationType.restore,
            sources: parsingNames,
            action: (task) async {
              final results = await FileService.restoreRecycleBinEntriesAsync(
                parsingNames,
                destinations: destinations,
                keepBothOnCollision: keepBothOnCollision,
                cancelRequested: () => task.cancelRequested,
                onProgress: task.updateProgress,
              );
              task.recordItemResults(results);
            },
          );
      if (!context.mounted) return;
      // 录制可撤销历史：实际还原路径来自原生回调 createdPath。
      final itemResults = completedTask.itemResults;
      final historySources = <String>[];
      final historyDestinations = <String>[];
      for (var i = 0; i < parsingNames.length; i++) {
        final result = i < itemResults.length ? itemResults[i] : null;
        if (result != null && !result.isSuccess) continue;
        final directory = destinations?[i] ?? entries[i].originalPath;
        if (directory == null || directory.isEmpty) continue;
        historySources.add(parsingNames[i]);
        historyDestinations.add(
          result?.createdPath ?? p.join(directory, entries[i].name),
        );
      }
      if (historySources.isNotEmpty) {
        context.read<AppState>().history.record(
          FileOperationHistory(
            type: HistoryOperationType.restore,
            source: historySources,
            destination: historyDestinations,
          ),
        );
      }
      final layoutState = context.read<LayoutState>();
      final repository = context.read<AppState>().repository;
      // 回收站面板就地摘除已还原条目 + 回收站目录缓存同步摘除。
      layoutState.applyLocalRemovals(parsingNames);
      repository.patchCompleteCache(
        FileService.recycleBinShellPath,
        removedPaths: parsingNames,
      );
      final originalDirectories = entries
          .map((entry) => entry.originalPath)
          .whereType<String>()
          .toSet();
      if (fallback != null) originalDirectories.add(fallback);
      if (keepBothOnCollision) {
        // 还原名由 Shell 决定：原始目录面板重枚举 + 缓存定点失效。
        layoutState.refreshPanesWhere(
          (path) => originalDirectories.any((d) => p.equals(d, path)),
        );
        for (final directory in originalDirectories) {
          repository.invalidate(directory);
        }
      } else {
        // 名称已知：扇形增量添加 + 就地补丁原始目录缓存。
        final restoredPaths = <String>[];
        for (var i = 0; i < entries.length; i++) {
          final directory = destinations?[i] ?? entries[i].originalPath;
          if (directory == null || directory.isEmpty) continue;
          restoredPaths.add(p.join(directory, entries[i].name));
        }
        _applyIncrementalRefresh(context, addedPaths: restoredPaths);
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('已还原 ${entries.length} 个项目'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (context.mounted) _showOperationError(context, '还原失败', error);
    }
  }

  /// Asks where to restore items whose original directory is gone. Returns
  /// the chosen directory, or null when the user cancels.
  Future<String?> _showRestoreLocationDialog(
    BuildContext context, {
    required int missingCount,
    String? sampleName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('无法还原到原始位置'),
        content: Text(
          sampleName != null
              ? '“$sampleName”的原始文件夹已不存在。请选择新的还原位置。'
              : '有 $missingCount 个项目的原始文件夹已不存在。请选择新的还原位置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final picked = FileService.pickFolder(
                initialPath: FileService.desktopPath,
              );
              if (picked != null && ctx.mounted) Navigator.pop(ctx, picked);
            },
            child: const Text('选择其他位置…'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, FileService.desktopPath),
            child: const Text('还原到桌面'),
          ),
        ],
      ),
    );
  }

  /// Asks how to resolve restore collisions. Returns the chosen policy, or
  /// null when the user cancels the whole restore.
  Future<_CollisionChoice?> _showCollisionDialog(
    BuildContext context, {
    required int collisionCount,
  }) {
    return showDialog<_CollisionChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还原冲突'),
        content: Text('有 $collisionCount 个项目与目标位置中的现有项目同名。如何处理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _CollisionChoice.skip),
            child: const Text('跳过'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _CollisionChoice.replace),
            child: const Text('替换'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _CollisionChoice.keepBoth),
            child: const Text('保留两者'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecycleBinSelection(BuildContext context) async {
    final controller = context.read<PaneController>();
    final operationCenter = context.read<AppState>().fileOperations;
    final selected = controller.selectedPaths.toList();
    if (selected.isEmpty) return;
    final displayName = selected.length == 1
        ? _findEntry(controller, selected.single)?.name
        : null;

    final confirm = await _showConfirmationDialog(
      context,
      title: '永久删除',
      message: selected.length == 1
          ? '要永久删除“${displayName ?? _basename(selected.single)}”吗？此操作无法撤销。'
          : '要永久删除选中的 ${selected.length} 个项目吗？此操作无法撤销。',
      confirmText: '永久删除',
      destructive: true,
    );
    if (confirm != true || !context.mounted) return;

    try {
      await operationCenter.enqueue(
        type: FileOperationType.permanentDelete,
        sources: selected,
        action: (task) async {
          final results = await FileService.deleteEntries(
            selected,
            permanent: true,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(results);
        },
      );
      if (context.mounted) {
        // 回收站缓存就地摘除被永久删除的条目；面板重新枚举。
        context.read<AppState>().repository.patchCompleteCache(
          FileService.recycleBinShellPath,
          removedPaths: selected,
        );
        context.read<LayoutState>().refreshPanesWhere(
          FileService.isRecycleBinPath,
        );
      }
    } catch (error) {
      if (context.mounted) _showOperationError(context, '永久删除失败', error);
    }
  }

  Future<void> _emptyRecycleBin(BuildContext context) async {
    final confirm = await _showConfirmationDialog(
      context,
      title: '清空回收站',
      message: '要永久删除回收站中的所有项目吗？此操作无法撤销。',
      confirmText: '清空',
      destructive: true,
    );
    if (confirm != true || !context.mounted) return;

    try {
      FileService.emptyRecycleBin();
      if (context.mounted) {
        // 清空后回收站目录缓存整体作废，面板重新枚举。
        context.read<AppState>().repository.invalidate(
          FileService.recycleBinShellPath,
        );
        context.read<LayoutState>().refreshPanesWhere(
          FileService.isRecycleBinPath,
        );
      }
    } catch (error) {
      if (context.mounted) _showOperationError(context, '清空回收站失败', error);
    }
  }

  Future<bool?> _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: context.colors.danger,
                    foregroundColor: context.colors.onAccent,
                  )
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showOperationError(
    BuildContext context,
    String operation,
    Object error,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$operation: $error'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _OpenWithMenu {
  final ImageProvider<Object>? defaultAppImage;
  final List<CommandMenuItem>? items;

  const _OpenWithMenu({this.defaultAppImage, this.items});
}

// ── Sections：按需重建，避免选中/加载时整个面板 rebuild ──────────────

class _PaneTabBarSection extends StatelessWidget {
  final String paneId;

  const _PaneTabBarSection({required this.paneId});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maximized = context.watch<LayoutState>().maximizedPaneId == paneId;
    return Row(
      children: [
        Expanded(
          child: Selector<PaneController, (List<TabInfo>, int)>(
            selector: (_, c) => (c.tabs, c.activeTabIndex),
            shouldRebuild: (a, b) => !listEquals(a.$1, b.$1) || a.$2 != b.$2,
            builder: (context, sel, _) {
              final controller = context.read<PaneController>();
              return PaneTabBar(
                tabs: sel.$1,
                activeIndex: sel.$2,
                onSwitchTab: controller.switchTab,
                onCloseTab: controller.closeTab,
                onAddTab: () => controller.addTab(),
              );
            },
          ),
        ),
        Tooltip(
          message: maximized ? '还原面板' : '最大化面板',
          child: InkWell(
            onTap: () => context.read<LayoutState>().toggleMaximize(paneId),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                maximized ? Icons.fullscreen_exit : Icons.fullscreen,
                size: AppMetrics.iconMd,
                color: maximized ? c.accent : c.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _PaneLocationSection extends StatelessWidget {
  const _PaneLocationSection();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.addressBarHeight,
      child: Row(
        children: [
          const _NavToolbarSection(),
          const SizedBox(width: 4),
          const Expanded(child: _AddressBarSection()),
        ],
      ),
    );
  }
}

class _NavToolbarSection extends StatelessWidget {
  const _NavToolbarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (bool, bool, bool)>(
      selector: (_, c) => (c.canGoBack, c.canGoForward, c.canGoUp),
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return NavToolbar(
          canGoBack: sel.$1,
          canGoForward: sel.$2,
          canGoUp: sel.$3,
          onBack: controller.goBack,
          onForward: controller.goForward,
          onUp: controller.goUp,
          onRefresh: controller.refresh,
        );
      },
    );
  }
}

class _AddressBarSection extends StatelessWidget {
  const _AddressBarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<PaneController, (String, String)>(
      selector: (_, c) => (c.displayPath, c.currentPath),
      builder: (context, sel, _) {
        final controller = context.read<PaneController>();
        return AddressBar(
          currentPath: sel.$1,
          iconPath: sel.$2,
          onSubmit: (path) => controller.navigateTo(path),
        );
      },
    );
  }
}

class _PaneDropTarget extends StatefulWidget {
  const _PaneDropTarget({
    required this.paneId,
    required this.controller,
    required this.onDrop,
    required this.child,
  });

  final String paneId;
  final PaneController controller;
  final Future<void> Function(
    FileDragPayload payload,
    FileDropOperation operation,
  )
  onDrop;
  final Widget child;

  @override
  State<_PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<_PaneDropTarget> {
  FileDragPayload? _payload;
  final Map<int, Offset> _pointerStarts = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_payload == null) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      final payload = _payload;
      if (payload != null) {
        _showTargetFeedback(payload, _decision(payload));
      }
      setState(() {});
    }
    return false;
  }

  FileDropDecision _decision(FileDragPayload payload) => FileDropService.decide(
    payload: payload,
    targetDirectory: widget.controller.currentPath,
    controlPressed: HardwareKeyboard.instance.isControlPressed,
    shiftPressed: HardwareKeyboard.instance.isShiftPressed,
  );

  void _showPayload(FileDragPayload payload) {
    if (identical(_payload, payload)) return;
    setState(() => _payload = payload);
  }

  void _clearPayload([FileDragPayload? payload]) {
    if (_payload == null ||
        (payload != null && !identical(_payload, payload))) {
      return;
    }
    (_payload ?? payload)?.clearTargetFeedback(_feedbackOwner);
    setState(() => _payload = null);
  }

  String get _feedbackOwner => 'pane:${widget.paneId}';

  void _showTargetFeedback(FileDragPayload payload, FileDropDecision decision) {
    var destination = p.basename(widget.controller.currentPath);
    if (destination.isEmpty) destination = widget.controller.currentPath;
    payload.showTargetFeedback(
      FileDragTargetFeedback(
        owner: _feedbackOwner,
        accepted: decision.accepted,
        copy: decision.operation == FileDropOperation.copy,
        destination: destination,
        message: decision.message,
      ),
    );
  }

  bool _isScrollbarGutter(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final local = renderObject.globalToLocal(globalPosition);
    return local.dx >= renderObject.size.width - AppMetrics.scrollbarHitWidth;
  }

  Offset? _localPosition(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.globalToLocal(globalPosition);
  }

  void _logPointerDown(PointerDownEvent event) {
    _pointerStarts[event.pointer] = event.position;
    _fileDropLog(
      '[FileDrop] pointer down pane=${widget.paneId} '
      'path=${widget.controller.currentPath} pointer=${event.pointer} '
      'kind=${event.kind.name} buttons=${event.buttons} '
      'global=${_dropDebugOffset(event.position)} '
      'local=${_dropDebugOffset(_localPosition(event.position))} '
      'gutter=${_isScrollbarGutter(event.position)}',
    );
  }

  void _logPointerMove(PointerMoveEvent event) {
    if (event.buttons == 0) return;
    final start = _pointerStarts[event.pointer];
    final distance = start == null ? null : (event.position - start).distance;
    _fileDropLog(
      '[FileDrop] pointer move pane=${widget.paneId} '
      'pointer=${event.pointer} buttons=${event.buttons} '
      'global=${_dropDebugOffset(event.position)} '
      'local=${_dropDebugOffset(_localPosition(event.position))} '
      'delta=${_dropDebugOffset(event.delta)} '
      'distance=${distance?.toStringAsFixed(2) ?? 'unknown'} '
      'gutter=${_isScrollbarGutter(event.position)}',
    );
  }

  void _logPointerEnd(PointerEvent event) {
    final start = _pointerStarts.remove(event.pointer);
    final distance = start == null ? null : (event.position - start).distance;
    _fileDropLog(
      '[FileDrop] pointer ${event is PointerCancelEvent ? 'cancel' : 'up'} '
      'pane=${widget.paneId} pointer=${event.pointer} '
      'global=${_dropDebugOffset(event.position)} '
      'distance=${distance?.toStringAsFixed(2) ?? 'unknown'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final payload = _payload;
    final decision = payload == null ? null : _decision(payload);
    final accepted = decision?.accepted == true;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _logPointerDown,
      onPointerMove: _logPointerMove,
      onPointerUp: _logPointerEnd,
      onPointerCancel: _logPointerEnd,
      child: DragTarget<FileDragPayload>(
        key: ValueKey('pane-drop-target-${widget.paneId}'),
        onWillAcceptWithDetails: (details) {
          final inGutter = _isScrollbarGutter(details.offset);
          final decision = _decision(details.data);
          _fileDropLog(
            '[FileDrop] drag enter pane=${widget.paneId} '
            'path=${widget.controller.currentPath} '
            'global=${_dropDebugOffset(details.offset)} '
            'local=${_dropDebugOffset(_localPosition(details.offset))} '
            'gutter=$inGutter accepted=${decision.accepted} '
            'operation=${decision.operation} reason=${decision.message}',
          );
          if (inGutter) {
            details.data.clearTargetFeedback(_feedbackOwner);
            _clearPayload();
            return false;
          }
          _showPayload(details.data);
          _showTargetFeedback(details.data, decision);
          return decision.accepted;
        },
        onMove: (details) {
          if (_isScrollbarGutter(details.offset)) {
            _clearPayload(details.data);
          } else {
            _showPayload(details.data);
            _showTargetFeedback(details.data, _decision(details.data));
          }
        },
        onLeave: (payload) {
          _fileDropLog(
            '[FileDrop] drag leave pane=${widget.paneId} '
            'path=${widget.controller.currentPath}',
          );
          _clearPayload(payload);
        },
        onAcceptWithDetails: (details) {
          final inGutter = _isScrollbarGutter(details.offset);
          final latest = _decision(details.data);
          _fileDropLog(
            '[FileDrop] drag accept pane=${widget.paneId} '
            'path=${widget.controller.currentPath} '
            'global=${_dropDebugOffset(details.offset)} gutter=$inGutter '
            'accepted=${latest.accepted} operation=${latest.operation} '
            'reason=${latest.message}',
          );
          if (inGutter) {
            _clearPayload(details.data);
            return;
          }
          _clearPayload(details.data);
          final operation = latest.operation;
          if (operation != null) {
            unawaited(widget.onDrop(details.data, operation));
          }
        },
        builder: (context, _, _) => Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (payload != null)
              IgnorePointer(
                child: Container(
                  key: ValueKey('pane-drop-highlight-${widget.paneId}'),
                  decoration: BoxDecoration(
                    color: accepted
                        ? c.accentSubtle.withValues(alpha: 0.2)
                        : c.danger.withValues(alpha: 0.06),
                    border: Border.all(
                      color: accepted ? c.accent : c.danger,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _dropDebugOffset(Offset? offset) => offset == null
    ? 'unavailable'
    : '(${offset.dx.toStringAsFixed(1)},${offset.dy.toStringAsFixed(1)})';

void _fileDropLog(String message) {
  if (kDebugMode) debugPrint(message);
}

class _FileListSection extends StatelessWidget {
  final bool isActive;
  final bool Function(String path)? cloudZoneResolver;
  final void Function(String path, Offset position) onItemContextMenu;
  final ValueChanged<Offset> onFolderContextMenu;
  final Future<void> Function(
    FileDragPayload payload,
    FileEntry directory,
    FileDropOperation operation,
  )
  onFolderDrop;

  const _FileListSection({
    required this.isActive,
    required this.cloudZoneResolver,
    required this.onItemContextMenu,
    required this.onFolderContextMenu,
    required this.onFolderDrop,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PaneController>();
    final appState = context.watch<AppState>();
    final entries = controller.visibleEntries;
    return Row(
      children: [
        Expanded(
          child: FileListView(
            entries: entries,
            selectedPaths: controller.selectedPaths,
            isActive: isActive,
            loading: controller.isLoading,
            sortColumn: controller.sortColumn,
            sortAscending: controller.sortAscending,
            onSort: controller.sortBy,
            viewMode: controller.viewMode,
            groupBy: controller.groupBy,
            groupAscending: controller.groupAscending,
            showFileExtensions: appState.showFileExtensions,
            columnWidths: controller.columnWidths,
            onResizeColumn: controller.resizeColumn,
            onInitWidths: controller.initColumnWidths,
            dragPayloadBuilder: (entry) =>
                _buildFileDragPayload(controller, entry),
            folderDropDecisionBuilder: (payload, directory) =>
                FileDropService.decide(
                  payload: payload,
                  targetDirectory: directory.path,
                  controlPressed: HardwareKeyboard.instance.isControlPressed,
                  shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                ),
            onFolderDrop: onFolderDrop,
            // 当前目录位于云同步区（OneDrive 等）时显示"状态"列，同资源管理器。
            showStatusColumn:
                cloudZoneResolver?.call(controller.currentPath) ??
                CloudDriveService.isCloudZone(controller.currentPath),
            onSingleTap: (path) {
              final ctrl = HardwareKeyboard.instance.isControlPressed;
              final shift = HardwareKeyboard.instance.isShiftPressed;
              if (shift) {
                controller.selectRange(path);
              } else if (ctrl) {
                controller.toggleSelection(path);
              } else if (controller.selectedPaths.length > 1 &&
                  controller.selectedPaths.contains(path)) {
                // Preserve the multi-selection while a pointer drag starts.
              } else {
                controller.selectSingle(path);
              }
            },
            onPrimaryTap: (path) {
              final keyboard = HardwareKeyboard.instance;
              if (!keyboard.isControlPressed &&
                  !keyboard.isShiftPressed &&
                  controller.selectedPaths.length > 1 &&
                  controller.selectedPaths.contains(path)) {
                controller.selectSingle(path);
              }
            },
            onDoubleTap: (path) => _handleDoubleTap(context, controller, path),
            onItemRightClick: onItemContextMenu,
            onEmptyRightClick: onFolderContextMenu,
          ),
        ),
      ],
    );
  }
}

FileDragPayload? _buildFileDragPayload(
  PaneController controller,
  FileEntry entry,
) {
  if (FileService.isSpecialPath(controller.currentPath)) return null;

  final selectedPaths = controller.selectedPaths.contains(entry.path)
      ? controller.selectedPaths
      : {entry.path};
  final items = [
    for (final candidate in controller.visibleEntries)
      if (selectedPaths.contains(candidate.path))
        FileDragItem(path: candidate.path, isDirectory: candidate.isDirectory),
  ];
  if (items.isEmpty) return null;
  return FileDragPayload(sourceDirectory: controller.currentPath, items: items);
}

class _StatusBarSection extends StatelessWidget {
  const _StatusBarSection();

  @override
  Widget build(BuildContext context) {
    return Selector<
      PaneController,
      (int, int, bool, int, String, QueryFilterMode, bool, EntryFilter)
    >(
      selector: (_, c) => (
        c.entryCount,
        c.entries.length,
        c.isLoading,
        c.selectedCount,
        c.filterQuery,
        c.filterMode,
        c.caseSensitive,
        c.entryFilter,
      ),
      builder: (context, sel, _) => _StatusBar(
        visibleCount: sel.$1,
        totalCount: sel.$2,
        isLoading: sel.$3,
        selectedCount: sel.$4,
        filterQuery: sel.$5,
        filterMode: sel.$6,
        caseSensitive: sel.$7,
        entryFilter: sel.$8,
        onFilterChanged: context.read<PaneController>().setFilterQuery,
        onModeSelected: (mode, caseSensitive) => context
            .read<PaneController>()
            .setFilterMode(mode, caseSensitive: caseSensitive),
        onEntryFilterSelected: context.read<PaneController>().setEntryFilter,
      ),
    );
  }
}

// ── 顶层辅助函数 ──────────────────────────────────────────────────────

FileEntry? _findEntry(PaneController controller, String path) {
  for (final e in controller.entries) {
    if (e.path == path) return e;
  }
  return null;
}

String _basename(String path) {
  final idx = path.lastIndexOf(RegExp(r'[\\/]'));
  return idx >= 0 ? path.substring(idx + 1) : path;
}

void _handleDoubleTap(
  BuildContext context,
  PaneController controller,
  String path,
) {
  // In the Recycle Bin, double-click does nothing useful; use right-click
  if (FileService.isRecycleBinPath(controller.currentPath)) return;

  final entry = _findEntry(controller, path);
  if (entry == null) return;
  if (entry.isDirectory) {
    controller.navigateTo(path);
  } else {
    FileService.openFile(path);
  }
}

void _showNativeMenu(
  BuildContext context,
  List<String> selectedPaths,
  Offset position,
) {
  final controller = context.read<PaneController>();

  // If right-clicking an unselected item, select only it
  if (selectedPaths.length == 1 &&
      !controller.selectedPaths.contains(selectedPaths.first)) {
    controller.clearSelection();
    controller.toggleSelection(selectedPaths.first);
  } else if (selectedPaths.isEmpty) {
    controller.clearSelection();
  }

  // Use all currently selected paths for the menu
  final paths = selectedPaths.isEmpty
      ? <String>[]
      : controller.selectedPaths.toList();

  // Convert logical (window-relative) → screen physical coordinates
  final dpr = View.of(context).devicePixelRatio;
  final (screenX, screenY) = ShellContextMenu.toScreenCoords(
    position.dx,
    position.dy,
    dpr,
  );

  final verb = ShellContextMenu.show(
    folderPath: controller.currentPath,
    selectedPaths: paths,
    screenX: screenX,
    screenY: screenY,
  );

  if (!context.mounted) return;
  _handleVerb(context, verb, paths);
}

void _handleVerb(
  BuildContext context,
  String? verb,
  List<String> selectedPaths,
) {
  if (verb == null) return;

  final appState = context.read<AppState>();
  final controller = context.read<PaneController>();

  switch (verb) {
    case 'open':
    case 'explore':
      // Intercepted — navigate for dirs, open for files
      if (selectedPaths.length == 1) {
        _handleDoubleTap(context, controller, selectedPaths.first);
      }
    case 'rename':
      // Intercepted — show our rename dialog
      _renameSelected(context);
    case 'copy':
      // Shell put CF_HDROP on clipboard; sync our app clipboard
      if (selectedPaths.isNotEmpty) {
        appState.copyPaths(selectedPaths);
      }
      controller.refresh();
    case 'cut':
      if (selectedPaths.isNotEmpty) {
        appState.cutPaths(selectedPaths);
      }
      controller.refresh();
    case 'delete':
      controller.refresh();
    case 'paste':
      appState.clearClipboard();
      controller.refresh();
    default:
      // Properties, copy-as-path, shell extensions, etc.
      // No filesystem change — no refresh needed.
      break;
  }
}

Future<void> _renameSelected(BuildContext context) async {
  final controller = context.read<PaneController>();

  // In Recycle Bin, items cannot be renamed
  if (FileService.isRecycleBinPath(controller.currentPath)) return;

  if (controller.selectedPaths.length != 1) return;
  final oldPath = controller.selectedPaths.first;
  final oldName = _basename(oldPath);

  final newName = await _showInputDialog(
    context,
    title: '重命名',
    initialValue: oldName,
    confirmText: '确定',
  );

  if (newName == null || newName.isEmpty || newName == oldName) return;

  try {
    await FileService.renameEntry(oldPath, newName);
    if (!context.mounted) return;
    final newPath = p.join(p.dirname(oldPath), newName);
    _applyIncrementalRefresh(
      context,
      addedPaths: [newPath],
      removedPaths: [oldPath],
    );
    context.read<AppState>().history.record(
      FileOperationHistory(
        type: HistoryOperationType.rename,
        source: [oldPath],
        destination: [newPath],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重命名失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

Future<String?> _showInputDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String confirmText,
}) {
  final textController = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = context.colors;
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(fontSize: AppMetrics.fontBody, color: c.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              borderSide: BorderSide(color: c.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
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
}

class _StatusBar extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final bool isLoading;
  final int selectedCount;
  final String filterQuery;
  final QueryFilterMode filterMode;
  final bool caseSensitive;
  final EntryFilter entryFilter;
  final ValueChanged<String> onFilterChanged;
  final void Function(QueryFilterMode mode, bool caseSensitive) onModeSelected;
  final ValueChanged<EntryFilter> onEntryFilterSelected;

  const _StatusBar({
    required this.visibleCount,
    required this.totalCount,
    required this.isLoading,
    required this.selectedCount,
    required this.filterQuery,
    required this.filterMode,
    required this.caseSensitive,
    required this.entryFilter,
    required this.onFilterChanged,
    required this.onModeSelected,
    required this.onEntryFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasFilter =
        filterQuery.trim().isNotEmpty || entryFilter != EntryFilter.all;
    String text;
    if (isLoading) {
      text = '正在加载...';
    } else if (hasFilter) {
      text = '$visibleCount / $totalCount 个对象';
    } else {
      text = '$visibleCount 个对象';
    }
    if (selectedCount > 0) {
      text = '已选择 $selectedCount 个对象  |  $text';
    }
    return Container(
      height: AppMetrics.statusBarHeight,
      decoration: BoxDecoration(color: c.surfaceSubtle),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppMetrics.fontSmall,
                color: c.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 168,
            child: _StatusFilterField(
              query: filterQuery,
              filterMode: filterMode,
              caseSensitive: caseSensitive,
              entryFilter: entryFilter,
              onChanged: onFilterChanged,
              onModeSelected: onModeSelected,
              onEntryFilterSelected: onEntryFilterSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态栏右侧的过滤输入框：右侧图标打开匹配模式和类型菜单。
class _StatusFilterField extends StatefulWidget {
  final String query;
  final QueryFilterMode filterMode;
  final bool caseSensitive;
  final EntryFilter entryFilter;
  final ValueChanged<String> onChanged;
  final void Function(QueryFilterMode mode, bool caseSensitive) onModeSelected;
  final ValueChanged<EntryFilter> onEntryFilterSelected;

  const _StatusFilterField({
    required this.query,
    required this.filterMode,
    required this.caseSensitive,
    required this.entryFilter,
    required this.onChanged,
    required this.onModeSelected,
    required this.onEntryFilterSelected,
  });

  @override
  State<_StatusFilterField> createState() => _StatusFilterFieldState();
}

class _StatusFilterFieldState extends State<_StatusFilterField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _StatusFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _textController.text != widget.query) {
      _textController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _modeTooltip => switch (widget.filterMode) {
    QueryFilterMode.keyword =>
      widget.caseSensitive ? '关键字匹配（大小写敏感）' : '关键字匹配（忽略大小写）',
    QueryFilterMode.glob => 'glob 通配匹配（* 任意串，? 单字符，整名）',
    QueryFilterMode.regex => '正则匹配（大小写由设置决定）',
  };

  IconData get _modeIcon => switch ((widget.filterMode, widget.caseSensitive)) {
    (QueryFilterMode.keyword, false) => Symbols.match_case_off,
    (QueryFilterMode.keyword, true) => Symbols.match_case,
    (QueryFilterMode.glob, _) => Symbols.g_mobiledata_badge,
    (QueryFilterMode.regex, _) => Symbols.regular_expression,
  };

  bool _isActive(QueryFilterMode mode, bool caseSensitive) {
    if (widget.filterMode != mode) return false;
    if (mode == QueryFilterMode.keyword) {
      return widget.caseSensitive == caseSensitive;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasQuery = widget.query.trim().isNotEmpty;
    final hasFilter = hasQuery || widget.entryFilter != EntryFilter.all;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: '过滤当前文件夹',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          height: 20,
          padding: const EdgeInsets.only(left: 6, right: 2),
          decoration: BoxDecoration(
            color: _hovering || _focusNode.hasFocus
                ? c.surfaceHover
                : c.surface,
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            border: Border.all(
              width: 1,
              color: _focusNode.hasFocus
                  ? c.accent
                  : _hovering
                  ? c.borderStrong
                  : c.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (_) => setState(() {}),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (hasQuery) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: '清除过滤',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppMetrics.controlRadius,
                    ),
                    onTap: () {
                      _textController.clear();
                      widget.onChanged('');
                      _focusNode.requestFocus();
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Tooltip(
                message: '$_modeTooltip，点击选择',
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
                  onTap: _openModeMenu,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Icon(
                        _modeIcon,
                        size: AppMetrics.iconSm,
                        color: hasFilter ? c.accent : c.textSecondary,
                      ),
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

  void _openModeMenu() {
    final box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset(box.size.width, box.size.height));
    showCommandMenu(
      context,
      position: position,
      items: [
        CommandMenuItem(
          icon: Symbols.match_case_off,
          label: '关键字（忽略大小写）',
          checked: _isActive(QueryFilterMode.keyword, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.keyword, false),
        ),
        CommandMenuItem(
          icon: Symbols.match_case,
          label: '关键字（大小写敏感）',
          checked: _isActive(QueryFilterMode.keyword, true),
          onAction: () => widget.onModeSelected(QueryFilterMode.keyword, true),
        ),
        const CommandMenuItem.divider(),
        CommandMenuItem(
          icon: Symbols.g_mobiledata_badge,
          label: 'glob（* ? 通配）',
          checked: _isActive(QueryFilterMode.glob, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.glob, false),
        ),
        CommandMenuItem(
          icon: Symbols.regular_expression,
          label: '正则表达式',
          checked: _isActive(QueryFilterMode.regex, false),
          onAction: () => widget.onModeSelected(QueryFilterMode.regex, false),
        ),
        const CommandMenuItem.divider(),
        buildEntryFilterCommandMenuItem(
          selected: widget.entryFilter,
          onSelected: widget.onEntryFilterSelected,
        ),
      ],
    );
  }
}
