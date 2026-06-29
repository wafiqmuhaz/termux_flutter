import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/color_attribute.dart';
import 'package:termux_flutter/core/terminal/screen_cell.dart';
import 'package:termux_flutter/core/terminal/text_attributes.dart';
import 'package:termux_flutter/core/terminal_style.dart';

void main() {
  const palette = ColorPalette();

  StyleRun decode(ScreenCell cell, {bool blinkOn = true}) {
    return StyleDecoder.decode(
      startCol: 0,
      endCol: 1,
      cell: cell,
      palette: palette,
      fontSize: 14,
      blinkOn: blinkOn,
    );
  }

  test('decodes bold italic underline and strike attributes', () {
    final run = decode(
      const ScreenCell(
        attributes: TextAttributes(
          bold: true,
          italic: true,
          underline: true,
          strikethrough: true,
        ),
      ),
    );

    expect(run.style.fontWeight, FontWeight.bold);
    expect(run.style.fontStyle, FontStyle.italic);
    expect(run.style.decoration, isNotNull);
  });

  test('resolves inverse foreground and background', () {
    final run = decode(
      const ScreenCell(
        foreground: ColorAttribute.named8(1),
        background: ColorAttribute.named8(2),
        attributes: TextAttributes(reverse: true),
      ),
    );

    expect(run.fg, palette.colors[2]);
    expect(run.bg, palette.colors[1]);
  });

  test('resolves 256-color and truecolor attributes', () {
    final indexed = decode(
      const ScreenCell(foreground: ColorAttribute.indexed256(196)),
    );
    final trueColor = decode(
      const ScreenCell(background: ColorAttribute.trueColor(1, 2, 3)),
    );

    expect(indexed.fg, const Color(0xffff0000));
    expect(trueColor.bg, const Color(0xff010203));
  });

  test('dims faint foreground and hides blink text while blink is off', () {
    final faint = decode(
      const ScreenCell(
        foreground: ColorAttribute.trueColor(90, 60, 30),
        attributes: TextAttributes(faint: true),
      ),
    );
    final blink = decode(
      const ScreenCell(attributes: TextAttributes(blink: true)),
      blinkOn: false,
    );

    expect(faint.fg, const Color(0xff3c2814));
    expect(blink.style.color?.a, 0);
  });
}
