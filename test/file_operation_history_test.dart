import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_operation_history.dart';

void main() {
  FileOperationHistory entry(String name) => FileOperationHistory(
    type: HistoryOperationType.rename,
    source: ['C:\\$name-old'],
    destination: ['C:\\$name-new'],
  );

  test('records entries and truncates the redo branch', () {
    final stack = FileOperationHistoryStack();

    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isFalse);

    stack.record(entry('a'));
    stack.record(entry('b'));
    stack.record(entry('c'));
    expect(stack.length, 3);
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);
    expect(stack.current.source.single, 'C:\\c-old');

    stack.moveBack();
    stack.moveBack();
    expect(stack.current.source.single, 'C:\\a-old');
    expect(stack.canRedo, isTrue);

    // 新操作截断 redo 尾巴。
    stack.record(entry('d'));
    expect(stack.length, 2);
    expect(stack.canRedo, isFalse);
    expect(stack.current.source.single, 'C:\\d-old');
  });

  test('undo/redo walk the stack and redoEntry peeks ahead', () {
    final stack = FileOperationHistoryStack();
    stack.record(entry('a'));
    stack.record(entry('b'));

    expect(stack.redoEntry, isNull);
    stack.moveBack();
    expect(stack.current.source.single, 'C:\\a-old');
    expect(stack.redoEntry!.source.single, 'C:\\b-old');

    stack.moveForward();
    expect(stack.current.source.single, 'C:\\b-old');
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);
  });

  test('replaceCurrent swaps the current entry in place', () {
    final stack = FileOperationHistoryStack();
    stack.record(entry('a'));
    stack.record(entry('b'));

    final replacement = entry('b2');
    stack.replaceCurrent(replacement);
    expect(stack.length, 2);
    expect(stack.current.source.single, 'C:\\b2-old');

    stack.moveBack();
    stack.moveForward();
    expect(stack.current.source.single, 'C:\\b2-old');
  });

  test('notifies listeners on every mutation', () {
    final stack = FileOperationHistoryStack();
    var notified = 0;
    stack.addListener(() => notified++);

    stack.record(entry('a'));
    stack.record(entry('b'));
    stack.moveBack();
    stack.replaceCurrent(entry('x'));
    stack.moveForward();

    expect(notified, 5);
  });
}
