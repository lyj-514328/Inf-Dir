import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_shell.dart';
import 'package:inf_dir/widgets/file_pane.dart';

void main() {
  testWidgets('settings matcher recognizes Ctrl+,', (tester) async {
    var matched = false;
    bool handler(KeyEvent event) {
      matched =
          matched || matchesSettingsShortcut(event, HardwareKeyboard.instance);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(matched, isTrue);
  });

  test('delete confirmation can only be skipped for recycle-bin deletion', () {
    expect(
      shouldConfirmFileDelete(permanent: false, confirmRecycleDelete: false),
      isFalse,
    );
    expect(
      shouldConfirmFileDelete(permanent: true, confirmRecycleDelete: false),
      isTrue,
    );
  });

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
      matched =
          matched || matchesUndoShortcut(event, HardwareKeyboard.instance);
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

  testWidgets('tab matchers distinguish Ctrl+T from Ctrl+Shift+T', (
    tester,
  ) async {
    var newTab = 0;
    var restoreTab = 0;
    bool handler(KeyEvent event) {
      final keyboard = HardwareKeyboard.instance;
      if (matchesNewTabShortcut(event, keyboard)) newTab++;
      if (matchesRestoreTabShortcut(event, keyboard)) restoreTab++;
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(newTab, 1);
    expect(restoreTab, 1);
  });

  testWidgets('tab matchers recognize Ctrl+W as close tab', (tester) async {
    var matched = false;
    bool handler(KeyEvent event) {
      matched =
          matched || matchesCloseTabShortcut(event, HardwareKeyboard.instance);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(matched, isTrue);
  });

  testWidgets('tab matchers distinguish Ctrl+Tab from Ctrl+Shift+Tab', (
    tester,
  ) async {
    var nextTab = 0;
    var previousTab = 0;
    bool handler(KeyEvent event) {
      final keyboard = HardwareKeyboard.instance;
      if (matchesNextTabShortcut(event, keyboard)) nextTab++;
      if (matchesPreviousTabShortcut(event, keyboard)) previousTab++;
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(nextTab, 1);
    expect(previousTab, 1);
  });

  testWidgets('tab matchers reject plain Tab and Alt+Tab', (tester) async {
    var matched = false;
    bool handler(KeyEvent event) {
      final keyboard = HardwareKeyboard.instance;
      matched =
          matched ||
          matchesNextTabShortcut(event, keyboard) ||
          matchesPreviousTabShortcut(event, keyboard);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(handler);
    addTearDown(() {
      ServicesBinding.instance.keyboard.removeHandler(handler);
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(matched, isFalse);
  });
}
