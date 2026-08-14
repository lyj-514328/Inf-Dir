import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import '../state/app_state.dart';
import '../state/layout_state.dart';
import 'file_service.dart';

/// 操作完成后的增量刷新：扇形更新所有正显示受影响目录的面板（不重新
/// 枚举），并就地补丁 repository 的目录缓存（新增条目经 inspectEntry
/// 构造、带排序键）；[invalidateDirs] 中的目录（目标名未知或目录本身
/// 被删除）改为定点失效。侧栏经 repository 回调自动重读。
void applyIncrementalRefresh({
  required AppState appState,
  required LayoutState layoutState,
  Iterable<String> addedPaths = const [],
  Iterable<String> removedPaths = const [],
  Iterable<String> invalidateDirs = const [],
}) {
  // 面板扇形增量更新（每个面板按 currentPath 自行守卫）。
  layoutState.applyLocalChanges(
    addedPaths: addedPaths,
    removedPaths: removedPaths,
  );

  // 目录缓存：新增按目标目录聚合，删除按所在目录聚合，就地打补丁。
  final additionsByDir = <String, List<FileEntry>>{};
  for (final path in addedPaths) {
    final entry = FileService.inspectEntry(path);
    if (entry == null) continue;
    additionsByDir.putIfAbsent(p.dirname(path), () => []).add(entry);
  }
  final removalsByDir = <String, List<String>>{};
  for (final path in removedPaths) {
    removalsByDir.putIfAbsent(p.dirname(path), () => []).add(path);
  }
  for (final dir in {...additionsByDir.keys, ...removalsByDir.keys}) {
    appState.repository.patchCompleteCache(
      dir,
      added: additionsByDir[dir] ?? const [],
      removedPaths: removalsByDir[dir] ?? const [],
    );
  }
  for (final dir in invalidateDirs) {
    appState.repository.invalidate(dir);
  }
}
