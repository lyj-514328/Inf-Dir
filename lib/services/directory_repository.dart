import 'dart:async';

import '../models/file_entry.dart';
import '../utils/path_utils.dart';
import 'directory_service.dart';
import 'sidebar_service.dart';

/// 打开目录枚举 cursor 的工厂。默认走 FFI，测试注入 fake。
typedef CursorFactory =
    DirectoryCursor? Function(String path, {bool directoriesOnly});

/// 帧边界让步函数。生产环境用 postFrameCallback，测试用 microtask / 手动 pump。
typedef FrameYield = Future<void> Function();

/// hasChildren 同步 probe。默认走 FFI，测试注入 fake。
typedef HasChildrenProbe = bool Function(String path);

/// partial children 发布回调：
/// [pathKey] 已规范化；[loading] 为 false 表示枚举完整结束（进入 complete cache）。
typedef OnPartialChildren =
    void Function(
      String pathKey,
      List<FileEntry> children,
      bool loading,
      int loadId,
    );

/// 调用方持有的目录加载租约。释放一个租约不会影响同路径的其它消费者。
class DirectoryLoadLease {
  final DirectoryRepository _repository;
  final int _subscriberId;
  final String pathKey;
  final int loadId;
  final Future<List<FileEntry>?> done;
  bool _released = false;

  DirectoryLoadLease._(
    this._repository,
    this._subscriberId,
    this.pathKey,
    this.loadId,
    this.done,
  );

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _repository._release(this);
  }
}

class _LoadSubscriber {
  final int id;
  final OnPartialChildren? onPartial;
  final Completer<List<FileEntry>?> done = Completer<List<FileEntry>?>();

  _LoadSubscriber(this.id, this.onPartial);
}

/// 一个路径只有一个加载任务；任务拥有 cursor，消费者通过 lease 订阅。
class _DirectoryLoad {
  final int id;
  final String pathKey;
  final DirectoryCursor cursor;
  final int pageSize;
  final Map<int, _LoadSubscriber> subscribers = {};
  List<FileEntry> partialChildren = const [];
  bool complete = false;
  bool cancelRequested = false;

  _DirectoryLoad(this.id, this.pathKey, this.cursor, this.pageSize);
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

  /// pathKey → 进行中的共享加载任务。
  final Map<String, _DirectoryLoad> _activeLoads = {};

  final Map<String, bool> _hasChildrenCache = {};
  final Set<String> _probingHasChildren = {};

  int _nextLoadId = 0;
  int _nextSubscriberId = 0;

  DirectoryRepository({
    CursorFactory? cursorFactory,
    FrameYield? yieldFrame,
    HasChildrenProbe? hasChildrenProbe,
  }) : _cursorFactory = cursorFactory ?? DirectoryService.openCursor,
       _yieldFrame = yieldFrame ?? _defaultYieldFrame,
       _hasChildrenProbe = hasChildrenProbe ?? _defaultHasChildrenProbe;

  static Future<void> _defaultYieldFrame() =>
      Future<void>.delayed(Duration.zero);

  static bool _defaultHasChildrenProbe(String path) =>
      SidebarService.directoryHasChildren(path);

  // ── cursor ─────────────────────────────────────────────────

  /// 给 FilePane 列表加载使用：与 sidebar 共用同一 cursor 生命周期（§2.7）。
  DirectoryCursor? openCursor(String path, {bool directoriesOnly = false}) =>
      _cursorFactory(path, directoriesOnly: directoriesOnly);

  // ── complete cache ─────────────────────────────────────────

  /// 已完整加载的 children（仅目录），key 内部规范化。
  List<FileEntry>? cachedChildren(String path) =>
      _completeCache[normPath(path)];

  bool isTaskActive(String path) => _activeLoads.containsKey(normPath(path));

  bool isLoadActive(String path, int loadId) {
    final load = _activeLoads[normPath(path)];
    return load != null && load.id == loadId;
  }

  /// 定点失效（refresh / rename / delete 后调用，§13.4）。
  void invalidate(String path) {
    final key = normPath(path);
    _completeCache.remove(key);
    _hasChildrenCache.remove(key);
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

  /// 获取 [path] 直接子目录的加载租约。同路径并发调用复用一个 cursor。
  DirectoryLoadLease acquireChildren(
    String path, {
    OnPartialChildren? onPartial,
    int pageSize = 100,
  }) {
    final key = normPath(path);
    final subscriber = _LoadSubscriber(++_nextSubscriberId, onPartial);

    final cached = _completeCache[key];
    if (cached != null) {
      subscriber.done.complete(cached);
      return DirectoryLoadLease._(
        this,
        subscriber.id,
        key,
        0,
        subscriber.done.future,
      );
    }

    final existing = _activeLoads[key];
    if (existing != null) {
      existing.subscribers[subscriber.id] = subscriber;
      final lease = DirectoryLoadLease._(
        this,
        subscriber.id,
        key,
        existing.id,
        subscriber.done.future,
      );
      scheduleMicrotask(() {
        if (!lease.isReleased && identical(_activeLoads[key], existing)) {
          onPartial?.call(key, existing.partialChildren, true, existing.id);
        }
      });
      return lease;
    }

    final cursor = _cursorFactory(path, directoriesOnly: true);
    if (cursor == null) {
      // native begin 失败：按空目录处理并缓存，避免重复 begin。
      const empty = <FileEntry>[];
      _completeCache[key] = empty;
      _hasChildrenCache[key] = false;
      subscriber.done.complete(empty);
      return DirectoryLoadLease._(
        this,
        subscriber.id,
        key,
        0,
        subscriber.done.future,
      );
    }

    final load = _DirectoryLoad(++_nextLoadId, key, cursor, pageSize);
    load.subscribers[subscriber.id] = subscriber;
    _activeLoads[key] = load;
    final lease = DirectoryLoadLease._(
      this,
      subscriber.id,
      key,
      load.id,
      subscriber.done.future,
    );
    scheduleMicrotask(() => _runLoad(load));
    return lease;
  }

  void _release(DirectoryLoadLease lease) {
    if (lease.loadId == 0) return;
    final load = _activeLoads[lease.pathKey];
    if (load == null || load.id != lease.loadId) return;

    final subscriber = load.subscribers.remove(lease._subscriberId);
    if (subscriber != null && !subscriber.done.isCompleted) {
      subscriber.done.complete(null);
    }
    if (load.subscribers.isEmpty) {
      load.cancelRequested = true;
      if (identical(_activeLoads[lease.pathKey], load)) {
        _activeLoads.remove(lease.pathKey);
      }
      load.cursor.close();
    }
  }

  bool _canContinue(_DirectoryLoad load) =>
      !load.cancelRequested &&
      load.subscribers.isNotEmpty &&
      identical(_activeLoads[load.pathKey], load);

  void _publish(_DirectoryLoad load, bool loading) {
    for (final subscriber in List.of(load.subscribers.values)) {
      subscriber.onPartial?.call(
        load.pathKey,
        load.partialChildren,
        loading,
        load.id,
      );
    }
  }

  void _completeSubscribers(_DirectoryLoad load, List<FileEntry>? result) {
    for (final subscriber in load.subscribers.values) {
      if (!subscriber.done.isCompleted) subscriber.done.complete(result);
    }
    load.subscribers.clear();
  }

  Future<void> _runLoad(_DirectoryLoad load) async {
    if (!_canContinue(load)) return;
    _publish(load, true);

    try {
      while (true) {
        await _yieldFrame();
        if (!_canContinue(load)) return;

        final page = load.cursor.nextPage(count: load.pageSize);

        // 同步 FFI 无法中途打断：当前页允许返回，租约已全部释放则丢弃。
        if (!_canContinue(load)) return;
        if (page == null) break;

        final dirs = page.where((e) => e.isDirectory).toList();
        for (final d in dirs) {
          _hasChildrenCache[normPath(d.path)] = d.hasChildren;
        }

        // 不可变 List 替换，不在原地修改 Widget 正在读取的 List。
        final merged = [...load.partialChildren, ...dirs];
        merged.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        load.partialChildren = List.unmodifiable(merged);

        _publish(load, true);
      }

      if (!_canContinue(load)) return;
      load.complete = true;
      _completeCache[load.pathKey] = load.partialChildren;
      _hasChildrenCache[load.pathKey] = load.partialChildren.isNotEmpty;
      if (identical(_activeLoads[load.pathKey], load)) {
        _activeLoads.remove(load.pathKey);
      }
      _publish(load, false);
      _completeSubscribers(load, load.partialChildren);
    } finally {
      load.cursor.close();
      if (identical(_activeLoads[load.pathKey], load)) {
        _activeLoads.remove(load.pathKey);
      }
      if (!load.complete) _completeSubscribers(load, null);
    }
  }
}
