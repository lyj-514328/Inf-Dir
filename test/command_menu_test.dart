import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_dir/widgets/app_theme.dart';
import 'package:inf_dir/widgets/command_menu.dart';

void main() {
  testWidgets('command menu wraps long labels without overflowing its row', (
    tester,
  ) async {
    const longLabel =
        r'C:\Program Files\Calibre2\ebook-viewer.exe with a long suffix';
    const nextLabel = 'Typora';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandMenu(
              context,
              position: const Offset(10, 10),
              items: const [
                CommandMenuItem(label: longLabel, enabled: false),
                CommandMenuItem(label: nextLabel, enabled: false),
              ],
            ),
            child: const Text('Open menu'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text(longLabel));
    expect(label.maxLines, 2);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(longLabel)).height, greaterThan(20));
    expect(
      tester.getRect(find.text(longLabel)).bottom,
      lessThan(tester.getRect(find.text(nextLabel)).top),
    );
    expect(tester.takeException(), isNull);
  });

  test('enabled leaf menu items require an action', () {
    expect(() => CommandMenuItem(label: 'No-op'), throwsAssertionError);
    expect(
      () => const CommandMenuItem(label: 'Unavailable', enabled: false),
      returnsNormally,
    );
  });
}
