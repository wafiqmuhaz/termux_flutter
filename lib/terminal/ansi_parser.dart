import 'package:flutter/material.dart';

import 'terminal_buffer.dart';

enum _AnsiState { ground, escape, csi }

class AnsiParser {
  AnsiParser(this.buffer);

  final TerminalBuffer buffer;
  _AnsiState _state = _AnsiState.ground;
  final StringBuffer _params = StringBuffer();

  void accept(String chunk) {
    for (final int code in chunk.codeUnits) {
      switch (_state) {
        case _AnsiState.ground:
          if (code == 0x1b) {
            _state = _AnsiState.escape;
          } else {
            buffer.writeText(String.fromCharCode(code));
          }
          break;
        case _AnsiState.escape:
          if (code == 0x5b) {
            _params.clear();
            _state = _AnsiState.csi;
          } else {
            _state = _AnsiState.ground;
          }
          break;
        case _AnsiState.csi:
          final String char = String.fromCharCode(code);
          if ((code >= 0x30 && code <= 0x39) || code == 0x3b) {
            _params.write(char);
          } else {
            _handleCsi(char);
            _state = _AnsiState.ground;
          }
          break;
      }
    }
  }

  void _handleCsi(String command) {
    final List<int> values = _params
        .toString()
        .split(';')
        .where((value) => value.isNotEmpty)
        .map((value) => int.tryParse(value) ?? 0)
        .toList();
    if (command == 'm') {
      _setGraphicRendition(values.isEmpty ? <int>[0] : values);
    } else if (command == 'J' && (values.isEmpty || values.first == 2)) {
      buffer.clear();
    } else if (command == 'H' || command == 'f') {
      final int row = values.isNotEmpty ? values[0] - 1 : 0;
      final int col = values.length > 1 ? values[1] - 1 : 0;
      buffer.moveCursor(row, col);
    } else if (command == 'A') {
      buffer.moveCursor(buffer.cursorRow - _amount(values), buffer.cursorCol);
    } else if (command == 'B') {
      buffer.moveCursor(buffer.cursorRow + _amount(values), buffer.cursorCol);
    } else if (command == 'C') {
      buffer.moveCursor(buffer.cursorRow, buffer.cursorCol + _amount(values));
    } else if (command == 'D') {
      buffer.moveCursor(buffer.cursorRow, buffer.cursorCol - _amount(values));
    }
  }

  int _amount(List<int> values) => values.isEmpty || values.first == 0 ? 1 : values.first;

  void _setGraphicRendition(List<int> values) {
    TextStyle style = buffer.currentStyle;
    for (final int value in values) {
      if (value == 0) {
        style = const TextStyle(color: Color(0xffeeeeee), fontWeight: FontWeight.normal);
      } else if (value == 1) {
        style = style.copyWith(fontWeight: FontWeight.bold);
      } else if (value >= 30 && value <= 37) {
        style = style.copyWith(color: _ansiColor(value - 30));
      }
    }
    buffer.currentStyle = style;
  }

  Color _ansiColor(int index) {
    const List<Color> colors = <Color>[
      Color(0xff111111),
      Color(0xffcc5555),
      Color(0xff55cc55),
      Color(0xffcccc55),
      Color(0xff5555cc),
      Color(0xffcc55cc),
      Color(0xff55cccc),
      Color(0xffeeeeee),
    ];
    return colors[index.clamp(0, colors.length - 1)];
  }
}
