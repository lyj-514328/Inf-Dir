import 'package:flutter/foundation.dart';
import 'pane_controller.dart';
import '../services/file_service.dart';

class AppState extends ChangeNotifier {
  late final List<PaneController> panes;
  int _activePaneIndex = 0;

  AppState() {
    panes = [
      PaneController(FileService.desktopPath),
      PaneController(FileService.homeDirectory),
      PaneController(FileService.documentsPath),
      PaneController(FileService.downloadsPath),
    ];
  }

  int get activePaneIndex => _activePaneIndex;
  PaneController get activePane => panes[_activePaneIndex];

  void setActivePane(int index) {
    if (index >= 0 && index < panes.length && _activePaneIndex != index) {
      _activePaneIndex = index;
      notifyListeners();
    }
  }
}
