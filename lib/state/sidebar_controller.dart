import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/file_entry.dart';
import '../services/cloud_drive_service.dart';
import '../services/directory_repository.dart';
import '../services/file_service.dart';
import '../services/sidebar_service.dart';
import '../utils/path_utils.dart';

/// 每路径的 partial 节点：带 owner request id（§9）。
class PartialNode {
  final int ownerRequestId;
  final List<FileEntry> children;
  final bool loading;

  const PartialNode(this.ownerRequestId, this.children, this.loading);
}

/// 侧栏树状态控制器（§8 / §10 / §12）。
///
/// 视图层只读这里的状态并转发点击；请求生命周期、
/// partial children 和展开状态都在这里，不在 Widget 里。
class SidebarSyncController extends ChangeNotifier {
  static const thisPcGuid = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';

  final DirectoryRepository repository;

  final List<QuickAccessItem> quickAccessItems;
  final List<String> driveRoots;

  /// 云盘同步根（OneDrive 等），作为顶层节点挂在"此电脑"之后。
  final List<CloudDrive> cloudDrives;

  bool thisPcExpanded = true;
  String? selectedPath;

  /// 用户手动展开（§10）。
  final Set<String> userExpandedPaths = {};

  /// 路径同步自动展开（§10），取消同步时只回滚未加载完成的分支；
  /// 已完整加载的分支保留展开（避免路径切换把树收起）。
  final Set<String> syncExpandedPaths = {};

  /// pathKey → partial 节点（owner + children + loading）。
  final Map<String, PartialNode> partialNodes = {};

  /// 视图消费的一次性滚动请求。
  bool needsScrollToSelected = false;

  /// 用户手动滚动后，本次同步不再自动跟随（可被新 syncTo 重置）。
  bool scrollFollowDismissed = false;

  RequestToken? _syncToken;
  final Map<String, RequestToken> _expandTokens = {};

  // 同一轮事件的重复 syncTo 用 microtask 合并，只提交最后一个（§12）。
  String? _pendingSyncPath;
  bool _pendingScrollToSelected = true;
  bool _syncCoalesceScheduled = false;

  bool _disposed = false;

  SidebarSyncController({
    required this.repository,
    List<QuickAccessItem>? quickAccessItems,
    List<String>? driveRoots,
    List<CloudDrive>? cloudDrives,
    bool probeDriveChildren = true,
  }) : quickAccessItems =
           quickAccessItems ?? SidebarService.getQuickAccessItems(),
       driveRoots = driveRoots ?? SidebarService.getDriveRoots(),
       cloudDrives = cloudDrives ?? CloudDriveService.getCloudDrives() {
    if (probeDriveChildren) {
      // 驱动器 hasChildren 一次性 probe（初始化阶段，不在 build 里）。
      for (final drive in this.driveRoots) {
        repository.seedHasChildren(
          drive,
          SidebarService.directoryHasChildren(drive),
        );
      }
      for (final cloud in this.cloudDrives) {
        repository.seedHasChildren(
          cloud.path,
          SidebarService.directoryHasChildren(cloud.path),
        );
      }
    }
  }

  /// 渲染用展开集合：手动 ∪ 自动（§10）。
  Set<String> get expandedPaths => {...userExpandedPaths, ...syncExpandedPaths};

  bool isExpanded(String path) => expandedPaths.contains(normPath(path));

  bool isLoading(String path) => partialNodes[normPath(path)]?.loading ?? false;

  /// 视图读取 children：complete cache 优先，其次 partial。
  List<FileEntry> childrenFor(String path) {
    final key = normPath(path);
    return repository.cachedChildren(key) ??
        partialNodes[key]?.children ??
        const [];
  }

  /// build 只读内存；未知节点调度一次性 probe，乐观返回 true（§13）。
  bool hasChildrenFor(String path) {
    final known = repository.hasChildrenIfKnown(path);
    if (known != null) return known;
    repository.probeHasChildren(path, onResolved: _notifySafe);
    return true;
  }

  void consumeScrollRequest() => needsScrollToSelected = false;

  /// complete cache 被就地补丁 / 定点失效后回调：清掉该路径的残留
  /// partial 视图并通知重绘，树直接读到新缓存（增量刷新）。
  void onCachePatched(String path) {
    if (_disposed) return;
    final key = normPath(path);
    // 有 in-flight 任务时 partial 属于活动加载，不能清。
    if (partialNodes.containsKey(key) && !repository.isTaskActive(key)) {
      partialNodes.remove(key);
    }
    _notifySafe();
  }

  // ── 路径同步（latest-wins，§6 / §8 / §12）────────────────────

  /// [scrollToSelected] 为 false 时表示本次同步由用户点击侧栏触发：
  /// 展开/选中照常，但不自动滚动到选中节点（用户刚点过，位置已知）。
  void syncTo(String path, {bool scrollToSelected = true}) {
    if (_disposed || path.isEmpty) return;
    _pendingSyncPath = path;
    _pendingScrollToSelected = scrollToSelected;
    if (_syncCoalesceScheduled) return;
    _syncCoalesceScheduled = true;
    scheduleMicrotask(() {
      _syncCoalesceScheduled = false;
      if (_disposed) return;
      final target = _pendingSyncPath;
      final scroll = _pendingScrollToSelected;
      _pendingSyncPath = null;
      _pendingScrollToSelected = true;
      if (target != null) _startSync(target, scrollToSelected: scroll);
    });
  }

  void _startSync(String path, {required bool scrollToSelected}) {
    // 取消旧 request：回滚它的 partial、loading 和自动展开（§3）。
    final old = _syncToken;
    _syncToken = null;
    if (old != null) _rollback(old, rollbackSyncExpansion: true);

    final token = repository.startRequest();
    _syncToken = token;
    if (scrollToSelected) {
      needsScrollToSelected = true;
      scrollFollowDismissed = false;
    } else {
      // 点击触发：不跟随滚动，同时取消上一轮同步遗留的滚动请求。
      needsScrollToSelected = false;
      scrollFollowDismissed = true;
    }

    // Quick Access：命中则高亮，同时继续展开树。
    for (final item in quickAccessItems) {
      if (pathEquals(item.path, path)) {
        selectedPath = item.path;
        break;
      }
    }

    if (path == thisPcGuid) {
      selectedPath = thisPcGuid;
      _notifySafe();
      return;
    }

    if (FileService.isHomePath(path)) {
      selectedPath = path;
      _notifySafe();
      return;
    }

    // 云盘路径优先走云盘分支：展开云盘节点链，不打扰"此电脑"驱动器链。
    final cloud = _findCloudFor(path);
    if (cloud != null) {
      selectedPath = path;
      syncExpandedPaths.add(normPath(cloud.path));
      _notifySafe();
      _loadChain(token, path, cloud.path);
      return;
    }

    final drive = _findDriveFor(path);
    if (drive == null) {
      _notifySafe();
      return;
    }

    thisPcExpanded = true;
    syncExpandedPaths.add(normPath(drive));
    selectedPath = path;
    _notifySafe();

    _loadChain(token, path, drive);
  }

  String? _findDriveFor(String path) {
    for (final drive in driveRoots) {
      if (isUnder(path, drive)) return drive;
    }
    return null;
  }

  CloudDrive? _findCloudFor(String path) {
    for (final cloud in cloudDrives) {
      if (isUnder(path, cloud.path)) return cloud;
    }
    return null;
  }

  /// 按路径链顺序确保每个 ancestor 的 children 已加载（§8）。
  Future<void> _loadChain(
    RequestToken token,
    String targetPath,
    String drive,
  ) async {
    for (final p in pathChain(drive, targetPath)) {
      if (!token.isActive || !identical(token, _syncToken)) return;
      syncExpandedPaths.add(normPath(p));
      _notifySafe();

      if (repository.cachedChildren(p) != null) continue;

      await repository.loadChildren(p, token: token, onPartial: _onPartial);
      if (!token.isActive || !identical(token, _syncToken)) return;
      _notifySafe();
    }
  }

  void _onPartial(
    String key,
    List<FileEntry> children,
    bool loading,
    int ownerRequestId,
  ) {
    if (_disposed) return;
    final existing = partialNodes[key];
    // 旧 request 不得覆盖新 request 已接管的节点（§9）。
    if (existing != null && existing.ownerRequestId != ownerRequestId) return;

    if (loading) {
      partialNodes[key] = PartialNode(ownerRequestId, children, true);
    } else {
      // 完整结束：数据进 complete cache，partial 卸载。
      partialNodes.remove(key);
    }
    // 任何 partial 状态变化都可能改变 selected 行之前的行数（loading
    // 指示器出现/消失、行数增减），所以 partial 增长时也重新武装滚动
    // 请求；由 SidebarTree 判定落点稳定后才消费（§18 缺陷修复）。
    if (!scrollFollowDismissed && selectedPath != null) {
      needsScrollToSelected = true;
    }
    _notifySafe();
  }

  void _rollback(RequestToken token, {required bool rollbackSyncExpansion}) {
    repository.cancelRequest(token);
    partialNodes.removeWhere((_, node) => node.ownerRequestId == token.id);
    if (rollbackSyncExpansion) {
      // 只回滚尚未加载完成的自动展开（被取消的半载链）；已完整加载的
      // 分支保留展开，否则每次导航切换都会把之前访问过的分支整个收起
      // （§3.6 例外）。
      syncExpandedPaths.removeWhere(
        (p) => repository.cachedChildren(p) == null,
      );
    }
  }

  /// 用户手动滚动：消费滚动请求并停止本次同步的自动跟随。
  void dismissScrollFollow() {
    needsScrollToSelected = false;
    scrollFollowDismissed = true;
  }

  // ── 视图交互 ────────────────────────────────────────────────

  void select(String path) {
    if (_disposed) return;
    selectedPath = path;
    _notifySafe();
  }

  void toggleThisPc() {
    if (_disposed) return;
    thisPcExpanded = !thisPcExpanded;
    _notifySafe();
  }

  /// 用户手动展开/收起（§10）。手动展开进入 userExpandedPaths，
  /// 不会被同步请求的取消回滚。
  void toggleExpand(String path) {
    if (_disposed) return;
    final key = normPath(path);
    if (userExpandedPaths.contains(key) || syncExpandedPaths.contains(key)) {
      // 用户收起优先：两份集合都移除（自动展开的节点用户也可手动收起）。
      userExpandedPaths.remove(key);
      syncExpandedPaths.remove(key);
      final token = _expandTokens.remove(key);
      if (token != null) _rollback(token, rollbackSyncExpansion: false);
    } else {
      userExpandedPaths.add(key);
      if (repository.cachedChildren(key) == null &&
          !repository.isTaskActive(key)) {
        final token = repository.startRequest();
        _expandTokens[key] = token;
        repository
            .loadChildren(path, token: token, onPartial: _onPartial)
            .whenComplete(() => _expandTokens.remove(key));
      }
    }
    _notifySafe();
  }

  // ── 生命周期 ────────────────────────────────────────────────

  void _notifySafe() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final sync = _syncToken;
    _syncToken = null;
    if (sync != null) repository.cancelRequest(sync);
    for (final token in _expandTokens.values) {
      repository.cancelRequest(token);
    }
    _expandTokens.clear();
    super.dispose();
  }
}
