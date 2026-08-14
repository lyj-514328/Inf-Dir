import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_shell.dart';
import 'package:inf_dir/widgets/file_pane.dart';

void main() {
  testWidgets('pane keyboard matcher recognizes Ctrl+F as search', (
    tester,
  ) async {
    var matched = false;
    bool handler(KeyEvent event) {
      matched =
          matched || matchesSearchShortcut(event, HardwareKeyboard.instance);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(matched, isTrue);
  });

  testWidgets('keyboard matchers recognize Ctrl+Z as undo only', (
    tester,
  ) async {
    var matchedUndo = false;
    var matchedRedo = false;
    bool handler(KeyEvent event) {
      final keyboard = HardwareKeyboard.instance;
      matchedUndo = matchedUndo || matchesUndoShortcut(event, keyboard);
      matchedRedo = matchedRedo || matchesRedoShortcut(event, keyboard);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(matchedUndo, isTrue);
    expect(matchedRedo, isFalse);
  });

  testWidgets('keyboard matchers recognize Ctrl+Y as redo only', (
    tester,
  ) async {
    var matchedUndo = false;
    var matchedRedo = false;
    bool handler(KeyEvent event) {
      final keyboard = HardwareKeyboard.instance;
      matchedUndo = matchedUndo || matchesUndoShortcut(event, keyboard);
      matchedRedo = matchedRedo || matchesRedoShortcut(event, keyboard);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(matchedRedo, isTrue);
    expect(matchedUndo, isFalse);
  });

  testWidgets('undo matcher rejects plain Z without modifiers', (tester) async {
    var matched = false;
    bool handler(KeyEvent event) {
      matched = matched || matchesUndoShortcut(event, HardwareKeyboard.instance);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);

    expect(matched, isFalse);
  });
}
