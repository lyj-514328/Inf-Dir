import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../models/file_operation_history.dart';
import '../services/directory_repository.dart';
import '../services/directory_service.dart';
import '../services/file_service.dart';
import '../services/file_operation_center.dart';
import '../services/icon_service.dart';
import 'settings_controller.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  final DirectoryRepository repository;
  final FileOperationCenter fileOperations;
  final FileOperationHistoryStack history;
  int _activePaneIndex = 0;
  final SettingsController settings;
  final bool _ownsSettings;

  AppState({
    DirectoryRepository? repository,
    FileOperationCenter? fileOperations,
    FileOperationHistoryStack? history,
    SettingsController? settings,
    bool applyInitialNativeSettings = false,
  }) : repository = repository ?? DirectoryRepository(),
       fileOperations = fileOperations ?? FileOperationCenter(),
       history = history ?? FileOperationHistoryStack(),
       settings = settings ?? SettingsController(),
       _ownsSettings = settings == null {
    this.settings.addListener(_onSettingsChanged);
    if (applyInitialNativeSettings) {
      DirectoryService.setShowHiddenFiles(this.settings.showHiddenFiles);
    }
    final repo = this.repository;
    panes = [
      for (final path in [
        FileService.desktopPath,
        FileService.homeDirectory,
        FileService.documentsPath,
        FileService.downloadsPath,
      ])
        PaneController(
          path,
          repository: repo,
          defaultViewMode: this.settings.defaultViewMode,
          newTabPathResolver: this.settings.resolveNewTabPath,
        ),
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

  bool get showHiddenFiles => settings.showHiddenFiles;
  bool get showFileExtensions => settings.showFileExtensions;
  bool get showThumbnails => settings.showThumbnails;
  bool get confirmRecycleDelete => settings.confirmRecycleDelete;

  /// 切换显示隐藏/系统文件：同步原生层过滤标志，清空目录缓存，
  /// 并刷新所有 pane。侧边栏由 AppShell 在切换后重新 sync。
  void setShowHiddenFiles(bool value) {
    if (showHiddenFiles == value) return;
    DirectoryService.setShowHiddenFiles(value);
    repository.invalidateAll();
    for (final pane in panes) {
      pane.refresh();
    }
    settings.setShowHiddenFiles(value);
  }

  void setShowFileExtensions(bool value) {
    settings.setShowFileExtensions(value);
  }

  void setShowThumbnails(bool value) {
    settings.setShowThumbnails(value);
  }

  void clearThumbnailCache() {
    IconService.clearThumbnailCache();
    notifyListeners();
  }

  void _onSettingsChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    if (_ownsSettings) settings.dispose();
    super.dispose();
  }
}
