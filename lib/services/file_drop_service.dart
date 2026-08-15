import 'package:path/path.dart' as p;

import '../models/file_drag_payload.dart';
import 'file_service.dart';

enum FileDropOperation { copy, move }

class FileDropDecision {
  const FileDropDecision._({this.operation, required this.message});

  const FileDropDecision.accept(FileDropOperation operation)
    : this._(operation: operation, message: '');

  const FileDropDecision.reject(String message) : this._(message: message);

  final FileDropOperation? operation;
  final String message;

  bool get accepted => operation != null;
}

class FileDropService {
  static final p.Context _windows = p.Context(style: p.Style.windows);

  static FileDropDecision decide({
    required FileDragPayload payload,
    required String targetDirectory,
    bool controlPressed = false,
    bool shiftPressed = false,
  }) {
    if (payload.items.isEmpty) {
      return const FileDropDecision.reject('没有可拖放的项目');
    }
    if (FileService.isSpecialPath(payload.sourceDirectory) ||
        FileService.isSpecialPath(targetDirectory)) {
      return const FileDropDecision.reject('此位置不支持文件拖放');
    }
    if (_equals(payload.sourceDirectory, targetDirectory)) {
      return const FileDropDecision.reject('源和目标文件夹相同');
    }

    for (final item in payload.items) {
      if (item.isDirectory &&
          (_equals(item.path, targetDirectory) ||
              _isWithin(item.path, targetDirectory))) {
        return const FileDropDecision.reject('不能把文件夹移动到自身或其子目录');
      }
    }

    final operation = controlPressed
        ? FileDropOperation.copy
        : shiftPressed
        ? FileDropOperation.move
        : _sameVolume(payload.sourceDirectory, targetDirectory)
        ? FileDropOperation.move
        : FileDropOperation.copy;
    return FileDropDecision.accept(operation);
  }

  static bool _sameVolume(String left, String right) {
    final leftRoot = _windows.rootPrefix(_windows.normalize(left));
    final rightRoot = _windows.rootPrefix(_windows.normalize(right));
    return leftRoot.isNotEmpty &&
        rightRoot.isNotEmpty &&
        leftRoot.toLowerCase() == rightRoot.toLowerCase();
  }

  static bool _equals(String left, String right) =>
      _windows.equals(_windows.normalize(left), _windows.normalize(right));

  static bool _isWithin(String parent, String child) =>
      _windows.isWithin(_windows.normalize(parent), _windows.normalize(child));
}
