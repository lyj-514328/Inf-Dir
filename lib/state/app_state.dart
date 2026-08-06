import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../services/directory_repository.dart';
import '../services/directory_service.dart';
import '../services/file_service.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  final DirectoryRepository repository;
  int _activePaneIndex = 0;
  bool _showHiddenFiles = false;

  AppState({DirectoryRepository? repository})
    : repository = repository ?? DirectoryRepository() {
    final repo = this.repository;
    panes = [PaneController(FileService.homeViewPath, repository: repo)];
  }

  int get activePaneIndex => _activePaneIndex;
  PaneController get activePane => panes[_activePaneIndex];

  List<String> _clipboardPaths = [];
  bool _clipboardIsCut = false;

  List<String> get clipboardPaths => _clipboardPaths;
  bool get clipboardIsCut => _clipboardIsCut;
  bool get hasClipboard => _clipboardPaths.isNotEmpty;

  void copyPaths(List<String> paths) {
    _clipboardPaths = List.from(paths);
    _clipboardIsCut = false;
    notifyListeners();
  }

  void cutPaths(List<String> paths) {
    _clipboardPaths = List.from(paths);
    _clipboardIsCut = true;
    notifyListeners();
  }

  void clearClipboard() {
    if (_clipboardPaths.isNotEmpty) {
      _clipboardPaths = [];
      _clipboardIsCut = false;
      notifyListeners();
    }
  }

  void setActivePane(int index) {
    if (index >= 0 && index < panes.length && _activePaneIndex != index) {
      _activePaneIndex = index;
      notifyListeners();
    }
  }

  // ── 显示隐藏文件（会话级设置）─────────────────────────────────

  bool get showHiddenFiles => _showHiddenFiles;

  /// 切换显示隐藏/系统文件：同步原生层过滤标志，清空目录缓存，
  /// 并刷新所有 pane。侧边栏由 AppShell 在切换后重新 sync。
  void setShowHiddenFiles(bool value) {
    if (_showHiddenFiles == value) return;
    _showHiddenFiles = value;
    DirectoryService.setShowHiddenFiles(value);
    repository.invalidateAll();
    for (final pane in panes) {
      pane.refresh();
    }
    notifyListeners();
  }
}
