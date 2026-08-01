import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../services/directory_repository.dart';
import '../services/file_service.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  int _activePaneIndex = 0;

  AppState({DirectoryRepository? repository}) {
    final repo = repository ?? DirectoryRepository();
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
}
