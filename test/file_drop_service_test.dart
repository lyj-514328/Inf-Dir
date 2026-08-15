import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/models/file_drag_payload.dart';
import 'package:inf_dir/services/file_drop_service.dart';

void main() {
  FileDragPayload payload({
    String directory = r'C:\source',
    String path = r'C:\source\item.txt',
    bool isDirectory = false,
  }) => FileDragPayload(
    sourceDirectory: directory,
    items: [FileDragItem(path: path, isDirectory: isDirectory)],
  );

  test('same-volume drop moves by default', () {
    final decision = FileDropService.decide(
      payload: payload(),
      targetDirectory: r'C:\target',
    );

    expect(decision.accepted, isTrue);
    expect(decision.operation, FileDropOperation.move);
  });

  test('cross-volume drop copies by default', () {
    final decision = FileDropService.decide(
      payload: payload(),
      targetDirectory: r'D:\target',
    );

    expect(decision.operation, FileDropOperation.copy);
  });

  test('Ctrl copies and Shift moves regardless of volume', () {
    final copy = FileDropService.decide(
      payload: payload(),
      targetDirectory: r'C:\target',
      controlPressed: true,
    );
    final move = FileDropService.decide(
      payload: payload(),
      targetDirectory: r'D:\target',
      shiftPressed: true,
    );

    expect(copy.operation, FileDropOperation.copy);
    expect(move.operation, FileDropOperation.move);
  });

  test('the source directory is rejected', () {
    final sameDirectory = FileDropService.decide(
      payload: payload(),
      targetDirectory: r'c:\SOURCE',
    );

    expect(sameDirectory.accepted, isFalse);
  });

  test('virtual targets and directory descendants are rejected', () {
    final virtualTarget = FileDropService.decide(
      payload: payload(),
      targetDirectory: 'shell:RecycleBinFolder',
    );
    final descendant = FileDropService.decide(
      payload: payload(path: r'C:\source\folder', isDirectory: true),
      targetDirectory: r'C:\source\folder\child',
    );

    expect(virtualTarget.accepted, isFalse);
    expect(descendant.accepted, isFalse);
  });
}
