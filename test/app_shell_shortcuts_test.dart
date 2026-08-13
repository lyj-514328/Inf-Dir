import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
