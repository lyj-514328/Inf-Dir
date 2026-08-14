import 'package:path/path.dart' as p;

import '../models/file_operation_history.dart';
import '../models/file_operation_task.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import 'file_service.dart';
import 'incremental_refresh.dart';

/// 执行撤销/重做：按历史记录类型执行反向/正向文件操作，全部经
/// FileOperationCenter 串行排队（进度、取消、逐项明细复用任务中心），
/// 完成后增量刷新受影响面板与目录缓存，并用实际操作结果刷新当前历史
/// 记录（回收站 ID / 保留两者改名等）。
///
/// [confirm] 用于撤销会删除文件的场景（撤销复制/新建/还原）：未提供时
/// 默认放行（测试）。
class UndoRedoService {
  UndoRedoService({
    required AppState appState,
    required LayoutState layoutState,
    required FileOperationHistoryStack history,
  }) : _appState = appState,
       _layoutState = layoutState,
       _history = history;

  final AppState _appState;
  final LayoutState _layoutState;
  final FileOperationHistoryStack _history;

  FileOperationHistoryStack get history => _history;

  /// 撤销最近一次记录的操作。返回是否实际执行。
  Future<bool> undo({
    Future<bool> Function(String title, String message)? confirm,
  }) async {
    if (!_history.canUndo) return false;
    final entry = _history.current;
    final executed = await _execute(entry, reverse: true, confirm: confirm);
    if (!executed) return false;
    _history.moveBack();
    return true;
  }

  /// 重做最近撤销的操作。返回是否实际执行。
  Future<bool> redo({
    Future<bool> Function(String title, String message)? confirm,
  }) async {
    if (!_history.canRedo) return false;
    final entry = _redoEntry;
    final executed = await _execute(entry, reverse: false, confirm: confirm);
    if (!executed) return false;
    _history.moveForward();
    return true;
  }

  FileOperationHistory get _redoEntry => _history.redoEntry!;

  Future<bool> _execute(
    FileOperationHistory entry, {
    required bool reverse,
    Future<bool> Function(String title, String message)? confirm,
  }) async {
    switch (entry.type) {
      case HistoryOperationType.copy:
        return reverse ? _undoCopy(entry, confirm) : _redoCopy(entry);
      case HistoryOperationType.move:
        return reverse
            ? _move(entry.destination, entry.source, removed: entry.destination)
            : _move(entry.source, entry.destination, removed: entry.source);
      case HistoryOperationType.rename:
        return reverse
            ? _rename(entry.destination, entry.source)
            : _rename(entry.source, entry.destination);
      case HistoryOperationType.createNew:
        return reverse
            ? _undoCreate(entry, confirm)
            : _redoCreate(entry);
      case HistoryOperationType.recycle:
        return reverse
            ? _undoRecycle(entry)
            : _redoRecycle(entry);
      case HistoryOperationType.restore:
        return reverse
            ? _undoRestore(entry, confirm)
            : _redoRestore(entry);
    }
  }

  // ── copy ──────────────────────────────────────────────────────

  Future<bool> _undoCopy(
    FileOperationHistory entry,
    Future<bool> Function(String title, String message)? confirm,
  ) async {
    final confirmed = await (confirm?.call(
          '撤销复制',
          '将永久删除 ${entry.destination.length} 个副本，此操作无法撤销。',
        ) ??
        Future.value(true));
    if (!confirmed) return false;

    final deletedDirs = _directoriesOf(entry.destination);
    final ok = await _enqueue(
      FileOperationType.permanentDelete,
      entry.destination,
      action: (task) async {
        final results = await FileService.deleteEntries(
          entry.destination,
          permanent: true,
          cancelRequested: () => task.cancelRequested,
          onProgress: task.updateProgress,
        );
        task.recordItemResults(results);
      },
    );
    if (!ok) return false;
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      removedPaths: entry.destination,
      invalidateDirs: deletedDirs,
    );
    return true;
  }

  Future<bool> _redoCopy(FileOperationHistory entry) async {
    final results = await _copyOrMove(
      FileOperationType.copy,
      entry.source,
      entry.destination,
    );
    if (results == null) return false;
    final created = _aligned(results, entry.destination);
    _history.replaceCurrent(
      FileOperationHistory(
        type: HistoryOperationType.copy,
        source: entry.source,
        destination: created,
      ),
    );
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: created,
    );
    return true;
  }

  // ── move ──────────────────────────────────────────────────────

  Future<bool> _move(
    List<String> sources,
    List<String> destinations, {
    required List<String> removed,
  }) async {
    final results = await _copyOrMove(FileOperationType.move, sources, destinations);
    if (results == null) return false;
    final created = _aligned(results, destinations);
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: created,
      removedPaths: removed,
    );
    return true;
  }

  /// 按目标目录分组执行复制/移动，返回逐项结果；失败返回 null。
  Future<List<FileOperationItemResult>?> _copyOrMove(
    FileOperationType type,
    List<String> sources,
    List<String> destinations,
  ) async {
    final byDir = <String, List<int>>{};
    for (var i = 0; i < destinations.length; i++) {
      byDir.putIfAbsent(p.dirname(destinations[i]), () => []).add(i);
    }
    final total = sources.length;
    List<FileOperationItemResult>? results;
    try {
      final task = await _appState.fileOperations.enqueue(
        type: type,
        sources: sources,
        destination: destinations.isEmpty ? null : p.dirname(destinations.first),
        action: (task) async {
          final all = <FileOperationItemResult>[];
          var done = 0;
          for (final group in byDir.values) {
            final groupSources = [for (final i in group) sources[i]];
            final dir = p.dirname(destinations[group.first]);
            final run = type == FileOperationType.copy
                ? FileService.copyEntries
                : FileService.moveEntries;
            all.addAll(
              await run(
                groupSources,
                dir,
                cancelRequested: () => task.cancelRequested,
                onProgress: (value) => task.updateProgress(
                  (done + groupSources.length * value) / total,
                ),
              ),
            );
            done += groupSources.length;
          }
          task.recordItemResults(all);
          task.updateProgress(1);
        },
      );
      results = task.itemResults;
    } catch (_) {
      return null;
    }
    return results;
  }

  /// 把逐项结果按 [fallback]（逐项对应）对齐成实际新路径。
  List<String> _aligned(
    List<FileOperationItemResult> results,
    List<String> fallback,
  ) {
    return [
      for (var i = 0; i < fallback.length; i++)
        results.length > i
            ? results[i].createdPath ?? fallback[i]
            : fallback[i],
    ];
  }

  // ── rename ────────────────────────────────────────────────────

  Future<bool> _rename(List<String> oldPaths, List<String> newPaths) async {
    try {
      await _appState.fileOperations.enqueue(
        type: FileOperationType.rename,
        sources: oldPaths,
        action: (task) async {
          for (var i = 0; i < oldPaths.length; i++) {
            await FileService.renameEntry(oldPaths[i], p.basename(newPaths[i]));
          }
          task.updateProgress(1);
        },
      );
    } catch (_) {
      return false;
    }
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: newPaths,
      removedPaths: oldPaths,
    );
    return true;
  }

  // ── createNew ─────────────────────────────────────────────────

  Future<bool> _undoCreate(
    FileOperationHistory entry,
    Future<bool> Function(String title, String message)? confirm,
  ) async {
    final confirmed = await (confirm?.call(
          '撤销新建',
          '将永久删除 ${entry.source.length} 个新建项目，此操作无法撤销。',
        ) ??
        Future.value(true));
    if (!confirmed) return false;

    final deletedDirs = _directoriesOf(entry.source);
    final ok = await _enqueue(
      FileOperationType.permanentDelete,
      entry.source,
      action: (task) async {
        final results = await FileService.deleteEntries(
          entry.source,
          permanent: true,
          cancelRequested: () => task.cancelRequested,
          onProgress: task.updateProgress,
        );
        task.recordItemResults(results);
      },
    );
    if (!ok) return false;
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      removedPaths: entry.source,
      invalidateDirs: deletedDirs,
    );
    return true;
  }

  Future<bool> _redoCreate(FileOperationHistory entry) async {
    final created = <String>[];
    try {
      await _appState.fileOperations.enqueue(
        type: FileOperationType.create,
        sources: entry.source,
        action: (task) async {
          for (var i = 0; i < entry.source.length; i++) {
            final path = entry.source[i];
            final parent = p.dirname(path);
            final name = p.basename(path);
            if (path == parent) continue;
            final isDirectory =
                entry.directories.length > i && entry.directories[i];
            if (isDirectory) {
              created.add(await FileService.createFolder(parent, name));
            } else {
              created.add(await FileService.createFile(parent, name));
            }
          }
          task.updateProgress(1);
        },
      );
    } catch (_) {
      return false;
    }
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: created,
    );
    return true;
  }

  // ── recycle ───────────────────────────────────────────────────

  Future<bool> _undoRecycle(FileOperationHistory entry) async {
    try {
      await _appState.fileOperations.enqueue(
        type: FileOperationType.restore,
        sources: entry.destination,
        action: (task) async {
          final results = await FileService.restoreRecycleBinEntriesAsync(
            entry.destination,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(results);
        },
      );
    } catch (_) {
      return false;
    }
    _layoutState.applyLocalRemovals(entry.destination);
    _appState.repository.patchCompleteCache(
      FileService.recycleBinShellPath,
      removedPaths: entry.destination,
    );
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: entry.source,
    );
    return true;
  }

  Future<bool> _redoRecycle(FileOperationHistory entry) async {
    final deletedDirs = _directoriesOf(entry.source);
    List<FileOperationItemResult>? results;
    try {
      final task = await _appState.fileOperations.enqueue(
        type: FileOperationType.delete,
        sources: entry.source,
        action: (task) async {
          final items = await FileService.deleteEntries(
            entry.source,
            permanent: false,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(items);
        },
      );
      results = task.itemResults;
    } catch (_) {
      return false;
    }
    // 回收站 ID 已变化：刷新历史记录的 destination，保证下轮 undo 可还原。
    // 原生回调未返回时按原目录 + 名称枚举回收站兜底。
    _history.replaceCurrent(
      FileOperationHistory(
        type: HistoryOperationType.recycle,
        source: entry.source,
        destination: [
          for (var i = 0; i < entry.source.length; i++)
            (results.length > i ? results[i].recycledPath : null) ??
                FileService.findRecycledParsingName(entry.source[i]) ??
                '',
        ].where((path) => path.isNotEmpty).toList(),
      ),
    );
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      removedPaths: entry.source,
      invalidateDirs: [
        ...deletedDirs,
        FileService.recycleBinShellPath,
      ],
    );
    return true;
  }

  // ── restore ───────────────────────────────────────────────────

  Future<bool> _undoRestore(
    FileOperationHistory entry,
    Future<bool> Function(String title, String message)? confirm,
  ) async {
    final confirmed = await (confirm?.call(
          '撤销还原',
          '将 ${entry.destination.length} 个已还原的项目重新移入回收站。',
        ) ??
        Future.value(true));
    if (!confirmed) return false;

    final deletedDirs = _directoriesOf(entry.destination);
    List<FileOperationItemResult>? results;
    try {
      final task = await _appState.fileOperations.enqueue(
        type: FileOperationType.delete,
        sources: entry.destination,
        action: (task) async {
          final items = await FileService.deleteEntries(
            entry.destination,
            permanent: false,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(items);
        },
      );
      results = task.itemResults;
    } catch (_) {
      return false;
    }
    _history.replaceCurrent(
      FileOperationHistory(
        type: HistoryOperationType.restore,
        source: [
          for (var i = 0; i < entry.destination.length; i++)
            (results.length > i ? results[i].recycledPath : null) ??
                FileService.findRecycledParsingName(entry.destination[i]) ??
                '',
        ].where((path) => path.isNotEmpty).toList(),
        destination: entry.destination,
      ),
    );
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      removedPaths: entry.destination,
      invalidateDirs: [
        ...deletedDirs,
        FileService.recycleBinShellPath,
      ],
    );
    return true;
  }

  Future<bool> _redoRestore(FileOperationHistory entry) async {
    List<FileOperationItemResult>? results;
    try {
      final task = await _appState.fileOperations.enqueue(
        type: FileOperationType.restore,
        sources: entry.source,
        action: (task) async {
          final items = await FileService.restoreRecycleBinEntriesAsync(
            entry.source,
            cancelRequested: () => task.cancelRequested,
            onProgress: task.updateProgress,
          );
          task.recordItemResults(items);
        },
      );
      results = task.itemResults;
    } catch (_) {
      return false;
    }
    final restored = _aligned(results, entry.destination);
    _history.replaceCurrent(
      FileOperationHistory(
        type: HistoryOperationType.restore,
        source: entry.source,
        destination: restored,
      ),
    );
    _layoutState.applyLocalRemovals(entry.source);
    _appState.repository.patchCompleteCache(
      FileService.recycleBinShellPath,
      removedPaths: entry.source,
    );
    applyIncrementalRefresh(
      appState: _appState,
      layoutState: _layoutState,
      addedPaths: restored,
    );
    return true;
  }

  // ── helpers ───────────────────────────────────────────────────

  /// 删除前记录哪些路径是文件夹（删除后 stat 会失败）。
  List<String> _directoriesOf(List<String> paths) => [
    for (final path in paths)
      if (_isDirectory(path)) path,
  ];

  bool _isDirectory(String path) =>
      FileService.inspectEntry(path)?.isDirectory ?? false;

  Future<bool> _enqueue(
    FileOperationType type,
    List<String> sources, {
    required Future<void> Function(FileOperationTask task) action,
  }) async {
    try {
      final task = await _appState.fileOperations.enqueue(
        type: type,
        sources: sources,
        action: action,
      );
      return task.status == FileOperationStatus.succeeded;
    } catch (_) {
      return false;
    }
  }
}
