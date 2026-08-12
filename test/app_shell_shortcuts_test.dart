import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_shell.dart';

void main() {
  testWidgets('global keyboard events recognize Ctrl+F as search', (
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
}
