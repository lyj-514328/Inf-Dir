import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_operation_history.dart';
import 'package:inf_dir/services/directory_repository.dart';
import 'package:inf_dir/services/undo_redo_service.dart';
import 'package:inf_dir/state/app_state.dart';
import 'package:inf_dir/state/layout_state.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory src;
  late Directory dest;
  late AppState appState;
  late LayoutState layoutState;
  late FileOperationHistoryStack history;
  late UndoRedoService service;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('inf_dir_undo_');
    src = Directory(p.join(temp.path, 'src'))..createSync();
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
    final repository = DirectoryRepository(
      cursorFactory: (_, {bool directoriesOnly = false}) async => null,
      hasChildrenProbe: (_) => false,
    );
    appState = AppState(repository: repository);
    layoutState = LayoutState(repository: repository);
    history = appState.history;
    service = UndoRedoService(
      appState: appState,
      layoutState: layoutState,
      history: history,
    );
    addTearDown(appState.dispose);
    addTearDown(layoutState.dispose);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  void write(File file, String content) => file.writeAsStringSync(content);

  String srcPath(String name) => p.join(src.path, name);
  String destPath(String name) => p.join(dest.path, name);

  test('undo on an empty stack is a no-op', () async {
    expect(await service.undo(), isFalse);
    expect(await service.redo(), isFalse);
  });

  test('undo/redo a copy round trip', () async {
    write(File(srcPath('a.txt')), 'hello');

    // 正向操作（与粘贴录制一致的路径）。
    history.record(
      FileOperationHistory(
        type: HistoryOperationType.copy,
        source: [srcPath('a.txt')],
        destination: [destPath('a.txt')],
      ),
    );
    // 实际复制（模拟粘贴已完成）。
    copyToDir(srcPath('a.txt'), dest.path);
    expect(File(destPath('a.txt')).readAsStringSync(), 'hello');

    expect(await service.undo(), isTrue);
    expect(File(destPath('a.txt')).existsSync(), isFalse);
    expect(history.canRedo, isTrue);
    expect(history.canUndo, isFalse);

    expect(await service.redo(), isTrue);
    expect(File(destPath('a.txt')).readAsStringSync(), 'hello');
    expect(history.canUndo, isTrue);

    // 第二轮撤销照常工作（redo 已刷新实际路径）。
    expect(await service.undo(), isTrue);
    expect(File(destPath('a.txt')).existsSync(), isFalse);
  });

  test('undo/redo a move round trip', () async {
    write(File(srcPath('a.txt')), 'hello');

    history.record(
      FileOperationHistory(
        type: HistoryOperationType.move,
        source: [srcPath('a.txt')],
        destination: [destPath('a.txt')],
      ),
    );
    File(srcPath('a.txt')).renameSync(destPath('a.txt'));
    expect(File(srcPath('a.txt')).existsSync(), isFalse);

    expect(await service.undo(), isTrue);
    expect(File(srcPath('a.txt')).readAsStringSync(), 'hello');
    expect(File(destPath('a.txt')).existsSync(), isFalse);

    expect(await service.redo(), isTrue);
    expect(File(destPath('a.txt')).readAsStringSync(), 'hello');
    expect(File(srcPath('a.txt')).existsSync(), isFalse);
  });

  test('undo/redo a rename round trip', () async {
    write(File(srcPath('old.txt')), 'hello');

    history.record(
      FileOperationHistory(
        type: HistoryOperationType.rename,
        source: [srcPath('old.txt')],
        destination: [srcPath('new.txt')],
      ),
    );
    File(srcPath('old.txt')).renameSync(srcPath('new.txt'));

    expect(await service.undo(), isTrue);
    expect(File(srcPath('old.txt')).existsSync(), isTrue);
    expect(File(srcPath('new.txt')).existsSync(), isFalse);

    expect(await service.redo(), isTrue);
    expect(File(srcPath('new.txt')).existsSync(), isTrue);
    expect(File(srcPath('old.txt')).existsSync(), isFalse);
  });

  test('undo/redo a folder creation round trip', () async {
    final created = p.join(src.path, 'sub');
    Directory(created).createSync();

    history.record(
      FileOperationHistory(
        type: HistoryOperationType.createNew,
        source: [created],
        directories: [true],
      ),
    );

    expect(await service.undo(), isTrue);
    expect(Directory(created).existsSync(), isFalse);

    expect(await service.redo(), isTrue);
    expect(Directory(created).existsSync(), isTrue);
  });

  test('a new operation truncates the redo branch', () async {
    write(File(srcPath('a.txt')), 'hello');
    history.record(
      FileOperationHistory(
        type: HistoryOperationType.copy,
        source: [srcPath('a.txt')],
        destination: [destPath('a.txt')],
      ),
    );
    copyToDir(srcPath('a.txt'), dest.path);

    await service.undo();
    expect(history.canRedo, isTrue);

    // 新操作（rename 录制）截断 redo。
    history.record(
      FileOperationHistory(
        type: HistoryOperationType.rename,
        source: [srcPath('a.txt')],
        destination: [srcPath('b.txt')],
      ),
    );
    expect(history.canRedo, isFalse);
    expect(history.length, 1);
    expect(history.current.type, HistoryOperationType.rename);
  });
}

// 与 FileService.copyEntries 的 dart:io 回退路径一致的本地复制。
void copyToDir(String from, String toDir) {
  final name = p.basename(from);
  File(from).copySync(p.join(toDir, name));
}
