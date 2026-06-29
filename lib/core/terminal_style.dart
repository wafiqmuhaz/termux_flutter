import 'package:flutter/material.dart';

import 'terminal/color_attribute.dart';
import 'terminal/screen_cell.dart';

final class ColorPalette {
  const ColorPalette({
    this.foreground = const Color(0xffeeeeee),
    this.background = const Color(0xff111111),
    this.cursor = const Color(0xffeeeeee),
    this.selection = const Color(0x663b82f6),
    this.colors = _xterm16,
  });

  final Color foreground;
  final Color background;
  final Color cursor;
  final Color selection;
  final List<Color> colors;

  Color resolve(ColorAttribute attribute, {required bool foregroundColor}) {
    return switch (attribute) {
      DefaultColor() => foregroundColor ? foreground : background,
      Named8Color(:final index) => colors[index.clamp(0, 7)],
      Named16Color(:final index) => colors[index.clamp(0, 15)],
      Indexed256Color(:final index) => _indexed256(index),
      TrueColor(:final red, :final green, :final blue) => Color.fromARGB(
        0xff,
        red,
        green,
        blue,
      ),
    };
  }

  Color _indexed256(int index) {
    final safeIndex = index.clamp(0, 255);
    if (safeIndex < 16) return colors[safeIndex];
    if (safeIndex >= 232) {
      final level = 8 + (safeIndex - 232) * 10;
      return Color.fromARGB(0xff, level, level, level);
    }
    final n = safeIndex - 16;
    final r = n ~/ 36;
    final g = (n % 36) ~/ 6;
    final b = n % 6;
    int component(int value) => value == 0 ? 0 : 55 + value * 40;
    return Color.fromARGB(0xff, component(r), component(g), component(b));
  }
}

final class StyleRun {
  const StyleRun({
    required this.startCol,
    required this.endCol,
    required this.style,
    required this.fg,
    required this.bg,
    required this.blink,
  });

  final int startCol;
  final int endCol;
  final TextStyle style;
  final Color fg;
  final Color bg;
  final bool blink;
}

final class StyleDecoder {
  const StyleDecoder._();

  static StyleRun decode({
    required int startCol,
    required int endCol,
    required ScreenCell cell,
    required ColorPalette palette,
    required double fontSize,
    required bool blinkOn,
  }) {
    final attrs = cell.attributes;
    var fg = palette.resolve(cell.foreground, foregroundColor: true);
    var bg = palette.resolve(cell.background, foregroundColor: false);

    if (attrs.reverse) {
      final oldFg = fg;
      fg = bg;
      bg = oldFg;
    }
    if (attrs.faint) fg = _dim(fg);
    if (attrs.invisible) fg = bg;

    final decorations = <TextDecoration>[];
    if (attrs.underline) decorations.add(TextDecoration.underline);
    if (attrs.strikethrough) decorations.add(TextDecoration.lineThrough);

    return StyleRun(
      startCol: startCol,
      endCol: endCol,
      fg: fg,
      bg: bg,
      blink: attrs.blink,
      style: TextStyle(
        color: attrs.blink && !blinkOn ? fg.withValues(alpha: 0) : fg,
        fontFamily: 'monospace',
        fontSize: fontSize,
        height: 1,
        fontWeight: attrs.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: attrs.italic ? FontStyle.italic : FontStyle.normal,
        decoration: decorations.isEmpty
            ? null
            : TextDecoration.combine(decorations),
        decorationColor: fg,
      ),
    );
  }

  static Color _dim(Color color) {
    return Color.fromARGB(
      (color.a * 255).round(),
      (color.r * 255 * 2 / 3).round(),
      (color.g * 255 * 2 / 3).round(),
      (color.b * 255 * 2 / 3).round(),
    );
  }
}

const List<Color> _xterm16 = <Color>[
  Color(0xff000000),
  Color(0xffcd0000),
  Color(0xff00cd00),
  Color(0xffcdcd00),
  Color(0xff0000ee),
  Color(0xffcd00cd),
  Color(0xff00cdcd),
  Color(0xffe5e5e5),
  Color(0xff7f7f7f),
  Color(0xffff0000),
  Color(0xff00ff00),
  Color(0xffffff00),
  Color(0xff5c5cff),
  Color(0xffff00ff),
  Color(0xff00ffff),
  Color(0xffffffff),
];

extension ScreenCellStyleMatch on ScreenCell {
  bool styleEquals(ScreenCell other) {
    return foreground == other.foreground &&
        background == other.background &&
        attributes == other.attributes;
  }
}
