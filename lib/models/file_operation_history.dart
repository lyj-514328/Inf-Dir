import 'package:flutter/foundation.dart';

/// 可撤销/可重做的文件操作类型。
enum HistoryOperationType { copy, move, rename, createNew, recycle, restore }

/// 一条文件操作历史：正向操作的类型、来源与目标。
///
/// 字段语义按类型：
/// - copy / move：source 原路径，destination 新路径（副本/移动后的实际路径，
///   来自原生回调的 createdPath，含"保留两者"的自动改名结果）
/// - rename：source 旧路径，destination 新路径
/// - createNew：source 创建的路径，destination 为空
/// - recycle：source 原路径，destination 回收站 $R 解析名（recycledPath）
/// - restore：source 回收站 $R 解析名，destination 还原后的路径
class FileOperationHistory {
  FileOperationHistory({
    required this.type,
    required List<String> source,
    List<String> destination = const [],
    List<bool> directories = const [],
  }) : source = List.unmodifiable(source),
       destination = List.unmodifiable(destination),
       directories = List.unmodifiable(directories);

  final HistoryOperationType type;
  final List<String> source;
  final List<String> destination;

  /// createNew 专用：与 [source] 对齐的"是否文件夹"标记（重做新建用）。
  final List<bool> directories;
}

/// 应用级文件操作历史栈：记录新操作会截断 redo 尾巴；撤销/重做沿
/// [index] 移动；[replaceCurrent] 用于刷新当前记录（回收站 ID 变化）。
class FileOperationHistoryStack extends ChangeNotifier {
  final List<FileOperationHistory> _entries = [];
  int _index = -1;

  bool get canUndo => _index >= 0 && _entries.isNotEmpty;
  bool get canRedo => _index + 1 < _entries.length;

  FileOperationHistory get current => _entries[_index];

  /// 重做目标；无可重做项时返回 null。
  FileOperationHistory? get redoEntry =>
      _index + 1 < _entries.length ? _entries[_index + 1] : null;

  int get length => _entries.length;

  void record(FileOperationHistory history) {
    _index++;
    _entries.removeRange(_index, _entries.length);
    _entries.add(history);
    notifyListeners();
  }

  /// 撤销：index 前移；调用前必须检查 [canUndo]。
  FileOperationHistory moveBack() {
    final entry = _entries[_index];
    _index--;
    notifyListeners();
    return entry;
  }

  /// 重做：index 后移；调用前必须检查 [canRedo]。
  FileOperationHistory moveForward() {
    _index++;
    final entry = _entries[_index];
    notifyListeners();
    return entry;
  }

  /// 用新记录替换当前记录（如回收站条目 ID 变化后刷新），保持 index。
  void replaceCurrent(FileOperationHistory history) {
    if (_index < 0 || _index >= _entries.length) return;
    _entries[_index] = history;
    notifyListeners();
  }
}
