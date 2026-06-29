import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/alternate_screen.dart';
import 'package:termux_flutter/core/terminal/screen_cell.dart';
import 'package:termux_flutter/core/terminal/screen_model.dart';
import 'package:termux_flutter/core/terminal/text_attributes.dart';

void main() {
  test('writes and reads cells', () {
    final screen = ScreenModel(columns: 3, rows: 2);

    screen.setCell(0, 1, const ScreenCell(char: 'x'));

    expect(screen.cellAt(0, 1).char, 'x');
    expect(screen.lineText(0), ' x ');
  });

  test('scroll up respects scroll region boundaries', () {
    final screen = ScreenModel(columns: 3, rows: 4);
    for (var row = 0; row < 4; row++) {
      screen.setCell(row, 0, ScreenCell(char: '$row'));
    }
    screen.setScrollRegion(1, 2);

    screen.scrollUp(1, TextAttributes.normal);

    expect(screen.cellAt(0, 0).char, '0');
    expect(screen.cellAt(1, 0).char, '2');
    expect(screen.cellAt(2, 0).char, ' ');
    expect(screen.cellAt(3, 0).char, '3');
  });

  test('alternate screen preserves primary cursor and attributes', () {
    final primary = ScreenModel(columns: 3, rows: 2)..moveCursor(1, 2);
    final alternate = ScreenModel(columns: 3, rows: 2);
    final manager = AlternateScreenManager(
      primary: primary,
      alternate: alternate,
    );
    const attrs = TextAttributes(bold: true);

    manager.enter(attributes: attrs);
    expect(manager.isAlternateActive, isTrue);
    manager.current.moveCursor(0, 1);
    final restored = manager.exit(attributes: TextAttributes.normal);

    expect(manager.current, same(primary));
    expect(primary.cursorRow, 1);
    expect(primary.cursorCol, 2);
    expect(restored.bold, isTrue);
  });
}
