import 'dart:async';

import '../models/file_entry.dart';
import '../utils/path_utils.dart';
import 'directory_service.dart';
import 'sidebar_service.dart';

/// 打开目录枚举 cursor 的工厂。默认走 worker isolate FFI，测试注入 fake。
typedef CursorFactory = Future<DirectoryCursor?> Function(String path,
    {bool directoriesOnly});

/// 帧边界让步函数。生产环境用 postFrameCallback，测试用 microtask / 手动 pump。
typedef FrameYield = Future<void> Function();

/// hasChildren 同步 probe。默认走 FFI，测试注入 fake。
typedef HasChildrenProbe = bool Function(String path);

/// partial children 发布回调：
/// [pathKey] 已规范化；[loading] 为 false 表示枚举完整结束（进入 complete cache）。
typedef OnPartialChildren = void Function(String pathKey,
    List<FileEntry> children, bool loading, int ownerRequestId);

/// latest-wins 请求令牌（§6）。
class RequestToken {
  final int id;
  bool cancelled = false;

  RequestToken(this.id);

  void cancel() => cancelled = true;
  bool get isActive => !cancelled;
}

/// 一个进行中的目录加载任务（§7.2）。
class DirectoryLoadTask {
  final int requestId;
  final String pathKey;

  /// 可能为 null：任务先占位注册，cursor 由 factory 填充后再赋值。
  DirectoryCursor? cursor;
  List<FileEntry> partialChildren = const [];
  bool complete = false;
  final Completer<List<FileEntry>?> done = Completer<List<FileEntry>?>();

  DirectoryLoadTask(this.requestId, this.pathKey, this.cursor);
}

/// 目录数据仓库：complete cache、in-flight task ownership、
/// hasChildren 缓存与统一定点失效（§7 / §13）。
///
/// 不依赖 flutter/material，帧边界通过注入的 [FrameYield] 实现。
class DirectoryRepository {
  final CursorFactory _cursorFactory;
  final FrameYield _yieldFrame;
  final HasChildrenProbe _hasChildrenProbe;

  /// 只有枚举完整结束才写入（§7.1）。
  final Map<String, List<FileEntry>> _completeCache = {};

  /// pathKey → 进行中的任务，带明确 owner requestId（§7.2）。
  final Map<String, DirectoryLoadTask> _activeTasks = {};

  final Map<String, bool> _hasChildrenCache = {};
  final Set<String> _probingHasChildren = {};

  int _nextRequestId = 0;

  /// 缓存被就地补丁或定点失效后回调（AppShell 桥接到侧栏控制器，
  /// 让树重读新缓存）。参数为规范化 pathKey。
  void Function(String pathKey)? onCacheChanged;

  DirectoryRepository({
    CursorFactory? cursorFactory,
    FrameYield? yieldFrame,
    HasChildrenProbe? hasChildrenProbe,
  })  : _cursorFactory = cursorFactory ?? DirectoryService.openCursor,
        _yieldFrame = yieldFrame ?? _defaultYieldFrame,
        _hasChildrenProbe = hasChildrenProbe ?? _defaultHasChildrenProbe;

  static Future<void> _defaultYieldFrame() =>
      Future<void>.delayed(Duration.zero);

  static bool _defaultHasChildrenProbe(String path) =>
      SidebarService.directoryHasChildren(path);

  // ── request 生命周期 ─────────────────────────────────────────

  RequestToken startRequest() => RequestToken(++_nextRequestId);

  /// 取消一个 request：停止翻页、幂等关闭它拥有的 cursor、
  /// 从 activeTasks 移除它的任务。complete cache 保留（§3）。
  void cancelRequest(RequestToken token) {
    token.cancel();
    final owned = _activeTasks.entries
        .where((e) => e.value.requestId == token.id)
        .toList();
    for (final e in owned) {
      // owner 校验：只清理仍由该 task 占有的条目
      if (identical(_activeTasks[e.key], e.value)) {
        _activeTasks.remove(e.key);
        e.value.cursor?.close();
      }
    }
  }

  // ── cursor ─────────────────────────────────────────────────

  /// 给 FilePane 列表加载使用：与 sidebar 共用同一 cursor 生命周期（§2.7）。
  Future<DirectoryCursor?> openCursor(String path,
          {bool directoriesOnly = false}) =>
      _cursorFactory(path, directoriesOnly: directoriesOnly);

  // ── complete cache ─────────────────────────────────────────

  /// 已完整加载的 children（仅目录），key 内部规范化。
  List<FileEntry>? cachedChildren(String path) => _completeCache[normPath(path)];

  bool isTaskActive(String path) => _activeTasks.containsKey(normPath(path));

  /// 定点失效（refresh / rename / delete 后调用，§13.4）。
  void invalidate(String path) {
    final key = normPath(path);
    _completeCache.remove(key);
    _hasChildrenCache.remove(key);
    onCacheChanged?.call(key);
  }

  /// 就地打补丁：把已知的文件系统变更应用到已完整缓存的目录，
  /// 不重新枚举。仅更新目录条目（缓存只存子目录，供侧栏使用）；
  /// [added] 由调用方经 FileService.inspectEntry 构造并带排序键。
  ///
  /// 两种退化场景下改为定点失效：该路径存在 in-flight 任务（旧分页
  /// 结果可能覆盖补丁）——调用方此时应让后续访问重新枚举。
  /// [removedPaths] 之外的缓存条目保持不变。
  void patchCompleteCache(
    String path, {
    Iterable<FileEntry> added = const [],
    Iterable<String> removedPaths = const [],
  }) {
    final key = normPath(path);
    final cached = _completeCache[key];
    if (cached == null) return;
    if (_activeTasks.containsKey(key)) {
      invalidate(path);
      return;
    }

    final removed = removedPaths.map(normPath).toSet();
    final next = cached
        .where((entry) => !removed.contains(normPath(entry.path)))
        .toList();
    var changed = next.length != cached.length;
    final existing = next.map((entry) => normPath(entry.path)).toSet();
    for (final entry in added) {
      if (!entry.isDirectory) continue; // 缓存只存目录（§7.1）
      if (!existing.add(normPath(entry.path))) continue;
      next.add(entry);
      changed = true;
    }

    if (!changed) return;
    next.sort((a, b) => a.compareNameTo(b));
    _completeCache[key] = List.unmodifiable(next);
    _hasChildrenCache[key] = next.isNotEmpty;
    onCacheChanged?.call(key);
  }

  /// 全局失效（设置变化后调用）：取消所有活动任务并清空全部缓存，
  /// 之后上层需要重新发起枚举。
  void invalidateAll() {
    final tasks = _activeTasks.values.toList();
    _activeTasks.clear();
    for (final t in tasks) {
      t.cursor?.close();
      if (!t.done.isCompleted) t.done.complete(null);
    }
    _completeCache.clear();
    _hasChildrenCache.clear();
    _probingHasChildren.clear();
  }

  // ── hasChildren（§13）──────────────────────────────────────

  /// 枚举元数据优先：加载 children 时把 FileEntry.hasChildren 种入缓存。
  void seedHasChildren(String path, bool value) {
    _hasChildrenCache[normPath(path)] = value;
  }

  /// 只读内存：已知返回 true/false，未知返回 null（不 probe）。
  bool? hasChildrenIfKnown(String path) {
    final key = normPath(path);
    final cached = _hasChildrenCache[key];
    if (cached != null) return cached;
    final complete = _completeCache[key];
    if (complete != null) return complete.isNotEmpty;
    return null;
  }

  /// 未知节点的一次性 probe：microtask 中执行，完成后回调。
  /// 不阻塞 build，且同一路径在 probe 完成前不会重复发起（§13.3）。
  void probeHasChildren(String path, {void Function()? onResolved}) {
    final key = normPath(path);
    if (_hasChildrenCache.containsKey(key)) {
      onResolved?.call();
      return;
    }
    if (!_probingHasChildren.add(key)) return;
    scheduleMicrotask(() {
      final value = _hasChildrenProbe(path);
      _hasChildrenCache[key] = value;
      _probingHasChildren.remove(key);
      onResolved?.call();
    });
  }

  // ── 分页加载（§7.3）─────────────────────────────────────────

  /// 加载 [path] 的直接子目录（directoriesOnly）。
  ///
  /// 返回完整 children；request 被取消时返回 null。
  /// 每页顺序：await frame → check token → nextPage → check token →
  /// 不可变 List 替换 → check owner → publish partial。
  Future<List<FileEntry>?> loadChildren(
    String path, {
    required RequestToken token,
    OnPartialChildren? onPartial,
    int pageSize = 100,
  }) async {
    final key = normPath(path);

    final cached = _completeCache[key];
    if (cached != null) return cached;

    // 同一路径已有活动任务（含占位）：不再开新 cursor，等待其完成
    //（ownership 不变）。
    final existing = _activeTasks[key];
    if (existing != null) {
      final result = await existing.done.future;
      if (!token.isActive) return null;
      return result;
    }

    // 先注册占位任务再 await factory：factory 的异步等待期间，并发请求
    // 会看到占位任务并等待其 done，不会重复 begin（原同步实现靠同步
    // factory 保证原子性，异步化后必须显式占位）。
    final task = DirectoryLoadTask(token.id, key, null);
    _activeTasks[key] = task;
    onPartial?.call(key, const [], true, token.id);

    try {
      final cursor = await _cursorFactory(path, directoriesOnly: true);
      task.cursor = cursor;

      if (!token.isActive) return null;
      if (cursor == null) {
        // native begin 失败：按空目录处理并缓存，避免重复 begin。
        const empty = <FileEntry>[];
        _completeCache[key] = empty;
        _hasChildrenCache[key] = false;
        if (identical(_activeTasks[key], task)) {
          _activeTasks.remove(key);
          onPartial?.call(key, empty, false, token.id);
        }
        task.done.complete(empty);
        return empty;
      }

      while (true) {
        await _yieldFrame();
        if (!token.isActive) return null;

        final page = await cursor.nextPage(count: pageSize);

        // worker 上的页已经返回：取消后立即丢弃（§3）。
        if (!token.isActive) return null;
        if (page == null) break;

        final dirs = page.where((e) => e.isDirectory).toList();
        for (final d in dirs) {
          _hasChildrenCache[normPath(d.path)] = d.hasChildren;
        }

        // 不可变 List 替换，不在原地修改 Widget 正在读取的 List。
        final merged = [...task.partialChildren, ...dirs];
        merged.sort((a, b) => a.compareNameTo(b));
        task.partialChildren = List.unmodifiable(merged);

        // owner 校验：路径可能已被新 request 接管（§7.2）。
        if (!identical(_activeTasks[key], task)) return null;

        onPartial?.call(key, task.partialChildren, true, token.id);
      }

      // 枚举完整结束 → 进入 complete cache（取消时不会走到这里）。
      task.complete = true;
      _completeCache[key] = task.partialChildren;
      _hasChildrenCache[key] = task.partialChildren.isNotEmpty;
      if (identical(_activeTasks[key], task)) {
        _activeTasks.remove(key);
        onPartial?.call(key, task.partialChildren, false, token.id);
      }
      task.done.complete(task.partialChildren);
      return task.partialChildren;
    } finally {
      // 每个 task 只关闭自己的 cursor（§5）。
      task.cursor?.close();
      if (identical(_activeTasks[key], task) && !task.complete) {
        _activeTasks.remove(key);
      }
      if (!task.done.isCompleted) task.done.complete(null);
    }
  }
}
