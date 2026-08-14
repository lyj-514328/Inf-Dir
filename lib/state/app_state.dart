import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../services/directory_repository.dart';
import '../services/directory_service.dart';
import '../services/file_service.dart';
import '../services/file_operation_center.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  final DirectoryRepository repository;
  final FileOperationCenter fileOperations;
  int _activePaneIndex = 0;
  bool _showHiddenFiles = false;
  bool _showFileExtensions = true;

  AppState({
    DirectoryRepository? repository,
    FileOperationCenter? fileOperations,
  }) : repository = repository ?? DirectoryRepository(),
       fileOperations = fileOperations ?? FileOperationCenter() {
    final repo = this.repository;
    panes = [
      PaneController(FileService.desktopPath, repository: repo),
      PaneController(FileService.homeDirectory, repository: repo),
      PaneController(FileService.documentsPath, repository: repo),
      PaneController(FileService.downloadsPath, repository: repo),
    ];
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
  bool get showFileExtensions => _showFileExtensions;

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

  void setShowFileExtensions(bool value) {
    if (_showFileExtensions == value) return;
    _showFileExtensions = value;
    notifyListeners();
  }
}
