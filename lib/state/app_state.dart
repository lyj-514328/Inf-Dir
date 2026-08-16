import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../models/file_operation_history.dart';
import '../services/directory_repository.dart';
import '../services/directory_service.dart';
import '../services/file_service.dart';
import '../services/file_operation_center.dart';
import '../services/icon_service.dart';
import '../services/prefs_store.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  final DirectoryRepository repository;
  final FileOperationCenter fileOperations;
  final FileOperationHistoryStack history;
  int _activePaneIndex = 0;
  bool _showHiddenFiles = false;
  bool _showFileExtensions = true;
  bool _showThumbnails = true;
  final PrefsStore _prefs;

  AppState({
    DirectoryRepository? repository,
    FileOperationCenter? fileOperations,
    FileOperationHistoryStack? history,
    PrefsStore? prefs,
  }) : repository = repository ?? DirectoryRepository(),
       fileOperations = fileOperations ?? FileOperationCenter(),
       history = history ?? FileOperationHistoryStack(),
       _prefs = prefs ?? PrefsStore() {
    final repo = this.repository;
    panes = [
      PaneController(FileService.desktopPath, repository: repo),
      PaneController(FileService.homeDirectory, repository: repo),
      PaneController(FileService.documentsPath, repository: repo),
      PaneController(FileService.downloadsPath, repository: repo),
    ];
    _loadPrefs();
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
  bool get showThumbnails => _showThumbnails;

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

  void setShowThumbnails(bool value) {
    if (_showThumbnails == value) return;
    _showThumbnails = value;
    _savePrefs();
    notifyListeners();
  }

  void clearThumbnailCache() {
    IconService.clearThumbnailCache();
    notifyListeners();
  }

  void _loadPrefs() {
    final values = _prefs.load();
    final showThumbnails = values['showThumbnails'];
    if (showThumbnails is bool) {
      _showThumbnails = showThumbnails;
    }
  }

  void _savePrefs() {
    _prefs.save({'showThumbnails': _showThumbnails});
  }
}
