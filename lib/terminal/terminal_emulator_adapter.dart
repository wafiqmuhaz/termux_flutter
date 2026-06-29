import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/terminal/color_attribute.dart';
import '../core/terminal/screen_cell.dart';
import '../core/terminal/screen_model.dart';
import '../core/terminal/terminal_emulator.dart';
import '../core/terminal/text_attributes.dart';
import 'terminal_buffer.dart';

final class TerminalEmulatorAdapter implements ScreenModelListener {
  TerminalEmulatorAdapter({int columns = 80, int rows = 24})
    : buffer = TerminalBuffer(maxLines: rows),
      emulator = TerminalEmulator(columns: columns, rows: rows) {
    emulator.primaryScreen.addListener(this);
    emulator.alternateScreen.addListener(this);
    _sync(emulator.screen);
  }

  final TerminalBuffer buffer;
  final TerminalEmulator emulator;

  void accept(String chunk) {
    emulator.processInput(Uint8List.fromList(chunk.codeUnits));
    _sync(emulator.screen);
  }

  @override
  void onScreenUpdated(ScreenModel screen) {
    _sync(screen);
  }

  void _sync(ScreenModel screen) {
    buffer.replaceFromScreen(
      rows: List<List<TerminalCell>>.generate(
        screen.rows,
        (row) => List<TerminalCell>.generate(screen.columns, (col) {
          final cell = screen.cellAt(row, col);
          return TerminalCell(
            cell.width == 0 ? '' : cell.char,
            _styleFor(cell),
          );
        }),
      ),
      cursorRow: screen.cursorRow,
      cursorCol: screen.cursorCol,
    );
  }

  TextStyle _styleFor(ScreenCell cell) {
    return TextStyle(
      color: _color(cell.foreground, const Color(0xffeeeeee)),
      backgroundColor: _color(cell.background, Colors.transparent),
      fontWeight: cell.attributes.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: cell.attributes.italic ? FontStyle.italic : FontStyle.normal,
      decoration: _decoration(cell.attributes),
    );
  }

  TextDecoration? _decoration(TextAttributes attributes) {
    if (attributes.underline && attributes.strikethrough) {
      return TextDecoration.combine(<TextDecoration>[
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    }
    if (attributes.underline) return TextDecoration.underline;
    if (attributes.strikethrough) return TextDecoration.lineThrough;
    return null;
  }

  Color _color(ColorAttribute color, Color fallback) {
    return switch (color) {
      DefaultColor() => fallback,
      Named8Color(:final index) => _palette[index.clamp(0, 7)],
      Named16Color(:final index) => _palette[index.clamp(0, 15)],
      Indexed256Color(:final index) => _indexedColor(index),
      TrueColor(:final red, :final green, :final blue) => Color.fromARGB(
        0xff,
        red,
        green,
        blue,
      ),
    };
  }

  Color _indexedColor(int index) {
    if (index < 16) return _palette[index];
    if (index >= 232) {
      final level = 8 + (index - 232) * 10;
      return Color.fromARGB(0xff, level, level, level);
    }
    final n = index - 16;
    final r = n ~/ 36;
    final g = (n % 36) ~/ 6;
    final b = n % 6;
    int component(int value) => value == 0 ? 0 : 55 + value * 40;
    return Color.fromARGB(0xff, component(r), component(g), component(b));
  }

  static const List<Color> _palette = <Color>[
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
}
