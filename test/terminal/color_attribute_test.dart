import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/color_attribute.dart';
import 'package:termux_flutter/core/terminal/terminal_emulator.dart';

void main() {
  test('SGR parses 8 color foreground and background reset', () {
    final terminal = TerminalEmulator(columns: 4, rows: 2);

    terminal.accept('\x1b[31;42mA\x1b[39;49mB');

    expect(
      terminal.screen.cellAt(0, 0).foreground,
      const ColorAttribute.named8(1),
    );
    expect(
      terminal.screen.cellAt(0, 0).background,
      const ColorAttribute.named8(2),
    );
    expect(
      terminal.screen.cellAt(0, 1).foreground,
      const ColorAttribute.defaultColor(),
    );
    expect(
      terminal.screen.cellAt(0, 1).background,
      const ColorAttribute.defaultColor(),
    );
  });

  test('SGR parses bright, indexed, and truecolor attributes', () {
    final terminal = TerminalEmulator(columns: 6, rows: 2);

    terminal.accept('\x1b[91mA\x1b[38;5;196mB\x1b[48;2;1;2;3mC');

    expect(
      terminal.screen.cellAt(0, 0).foreground,
      const ColorAttribute.named16(9),
    );
    expect(
      terminal.screen.cellAt(0, 1).foreground,
      const ColorAttribute.indexed256(196),
    );
    expect(
      terminal.screen.cellAt(0, 2).background,
      const ColorAttribute.trueColor(1, 2, 3),
    );
  });

  test('OSC 52 clipboard respects allow policy', () {
    String? copied;
    final terminal = TerminalEmulator(
      clipboardPolicy: ClipboardPolicy.allow,
      onClipboard: (text) => copied = text,
    );

    terminal.processInput(
      Uint8List.fromList(
        utf8.encode('\x1b]52;c;${base64.encode(utf8.encode('hello'))}\x07'),
      ),
    );

    expect(copied, 'hello');
  });
}
