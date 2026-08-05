import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/file_entry.dart';
import '../services/cloud_drive_service.dart';
import '../services/directory_repository.dart';
import '../services/sidebar_service.dart';
import 'layout_state.dart';
import '../utils/path_utils.dart';

/// 每路径的 partial 节点：带 owner request id（§9）。
class PartialNode {
  final int loadId;
  final List<FileEntry> children;
  final bool loading;

  const PartialNode(this.loadId, this.children, this.loading);
}

class _RevealSession {
  final int generation;
  final Set<DirectoryLoadLease> leases = {};
  bool cancelled = false;

  _RevealSession(this.generation);

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final lease in leases.toList()) {
      lease.release();
    }
    leases.clear();
  }
}

/// 侧栏树状态控制器（§8 / §10 / §12）。
///
/// 视图层只读这里的状态并转发点击；请求生命周期、
/// partial children 和展开状态都在这里，不在 Widget 里。
class SidebarSyncController extends ChangeNotifier {
  static const thisPcGuid = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';

  final DirectoryRepository repository;
  final ValueListenable<ActivePaneLocation?>? activeLocation;

  final List<QuickAccessItem> quickAccessItems;
  final List<String> driveRoots;

  /// 云盘同步根（OneDrive 等），作为顶层节点挂在"此电脑"之后。
  final List<CloudDrive> cloudDrives;

  bool thisPcExpanded = true;
  String? _directRevealPath;

  /// 正式运行时从活动 Pane 位置派生；无位置流时仅供单元测试直接驱动。
  String? get selectedPath =>
      activeLocation != null ? activeLocation!.value?.path : _directRevealPath;

  /// Increments for each latest-wins reveal session.
  int get revealGeneration => _revealSession?.generation ?? 0;

  /// 用户手动展开（§10）。
  final Set<String> userExpandedPaths = {};

  /// 路径同步自动展开（§10），取消同步时整体回滚。
  final Set<String> syncExpandedPaths = {};

  /// pathKey → partial 节点（owner + children + loading）。
  final Map<String, PartialNode> partialNodes = {};

  /// 视图消费的一次性滚动请求。
  bool needsScrollToSelected = false;

  /// 用户手动滚动后，本次同步不再自动跟随（可被新 syncTo 重置）。
  bool scrollFollowDismissed = false;

  _RevealSession? _revealSession;
  final Map<String, DirectoryLoadLease> _expandLeases = {};
  int _nextRevealGeneration = 0;

  // 同一轮事件的重复 syncTo 用 microtask 合并，只提交最后一个（§12）。
  String? _pendingSyncPath;
  bool _syncCoalesceScheduled = false;

  bool _disposed = false;

  SidebarSyncController({
    required this.repository,
    this.activeLocation,
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
    activeLocation?.addListener(_onActiveLocationChanged);
    _onActiveLocationChanged();
  }

  void _onActiveLocationChanged() {
    final path = activeLocation?.value?.path;
    if (path != null) {
      syncTo(path);
    } else if (activeLocation != null) {
      _cancelRevealSession(clearSyncExpansion: true);
      _directRevealPath = null;
      _notifySafe();
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

  // ── 路径同步（latest-wins，§6 / §8 / §12）────────────────────

  void syncTo(String path) {
    if (_disposed || path.isEmpty) return;
    _pendingSyncPath = path;
    if (_syncCoalesceScheduled) return;
    _syncCoalesceScheduled = true;
    scheduleMicrotask(() {
      _syncCoalesceScheduled = false;
      if (_disposed) return;
      final target = _pendingSyncPath;
      _pendingSyncPath = null;
      if (target != null) _startSync(target);
    });
  }

  void _startSync(String path) {
    _cancelRevealSession(clearSyncExpansion: true);

    final session = _RevealSession(++_nextRevealGeneration);
    _revealSession = session;
    _directRevealPath = path;
    needsScrollToSelected = true;
    scrollFollowDismissed = false;

    if (path == thisPcGuid) {
      _notifySafe();
      return;
    }

    // 云盘路径优先走云盘分支：展开云盘节点链，不打扰"此电脑"驱动器链。
    final cloud = _findCloudFor(path);
    if (cloud != null) {
      syncExpandedPaths.addAll(pathChain(cloud.path, path).map(normPath));
      _notifySafe();
      _loadChain(session, path, cloud.path);
      return;
    }

    final drive = _findDriveFor(path);
    if (drive == null) {
      _notifySafe();
      return;
    }

    thisPcExpanded = true;
    syncExpandedPaths.addAll(pathChain(drive, path).map(normPath));
    _notifySafe();

    _loadChain(session, path, drive);
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
    _RevealSession session,
    String targetPath,
    String drive,
  ) async {
    for (final p in pathChain(drive, targetPath)) {
      if (session.cancelled || !identical(session, _revealSession)) return;

      if (repository.cachedChildren(p) != null) continue;

      final lease = repository.acquireChildren(p, onPartial: _onPartial);
      session.leases.add(lease);
      final result = await lease.done;
      session.leases.remove(lease);
      lease.release();
      if (session.cancelled || !identical(session, _revealSession)) return;
      if (result == null) return;
      _notifySafe();
    }
  }

  void _onPartial(
    String key,
    List<FileEntry> children,
    bool loading,
    int loadId,
  ) {
    if (_disposed) return;
    final existing = partialNodes[key];
    if (existing != null &&
        existing.loadId != loadId &&
        repository.isLoadActive(key, existing.loadId)) {
      return;
    }

    if (loading) {
      partialNodes[key] = PartialNode(loadId, children, true);
    } else {
      // 完整结束：数据进 complete cache，partial 卸载。
      if (partialNodes[key]?.loadId == loadId) {
        partialNodes.remove(key);
      }
    }
    // 任何 partial 状态变化都可能改变 selected 行之前的行数（loading
    // 指示器出现/消失、行数增减），所以 partial 增长时也重新武装滚动
    // 请求；由 SidebarTree 判定落点稳定后才消费（§18 缺陷修复）。
    if (!scrollFollowDismissed && selectedPath != null) {
      needsScrollToSelected = true;
    }
    _notifySafe();
  }

  void _removeInactivePartials() {
    partialNodes.removeWhere(
      (key, node) => !repository.isLoadActive(key, node.loadId),
    );
  }

  void _cancelRevealSession({required bool clearSyncExpansion}) {
    final old = _revealSession;
    _revealSession = null;
    old?.cancel();
    _removeInactivePartials();
    if (clearSyncExpansion) syncExpandedPaths.clear();
  }

  /// 用户手动滚动：消费滚动请求并停止本次同步的自动跟随。
  void dismissScrollFollow() {
    needsScrollToSelected = false;
    scrollFollowDismissed = true;
  }

  // ── 视图交互 ────────────────────────────────────────────────

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
      _expandLeases.remove(key)?.release();
      _removeInactivePartials();
    } else {
      userExpandedPaths.add(key);
      if (repository.cachedChildren(key) == null &&
          !_expandLeases.containsKey(key)) {
        final lease = repository.acquireChildren(path, onPartial: _onPartial);
        _expandLeases[key] = lease;
        lease.done.whenComplete(() {
          if (identical(_expandLeases[key], lease)) {
            _expandLeases.remove(key);
          }
          lease.release();
        });
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
    activeLocation?.removeListener(_onActiveLocationChanged);
    _cancelRevealSession(clearSyncExpansion: false);
    for (final lease in _expandLeases.values) {
      lease.release();
    }
    _expandLeases.clear();
    super.dispose();
  }
}
