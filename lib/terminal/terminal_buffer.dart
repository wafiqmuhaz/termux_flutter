import 'package:flutter/material.dart';

class TerminalCell {
  TerminalCell(this.text, this.style);

  String text;
  TextStyle style;
}

class TerminalLine {
  TerminalLine([List<TerminalCell>? cells]) : cells = cells ?? <TerminalCell>[];

  final List<TerminalCell> cells;

  String get plainText => cells.map((cell) => cell.text).join();
}

class TerminalBuffer extends ChangeNotifier {
  TerminalBuffer({this.maxLines = 5000}) {
    _lines.add(TerminalLine());
  }

  final int maxLines;
  final List<TerminalLine> _lines = <TerminalLine>[];
  int cursorRow = 0;
  int cursorCol = 0;
  TextStyle currentStyle = const TextStyle(color: Color(0xffeeeeee));

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_lines);

  void replaceFromScreen({
    required List<List<TerminalCell>> rows,
    required int cursorRow,
    required int cursorCol,
  }) {
    _lines
      ..clear()
      ..addAll(rows.map((row) => TerminalLine(List<TerminalCell>.of(row))));
    this.cursorRow = cursorRow;
    this.cursorCol = cursorCol;
    notifyListeners();
  }

  void writeText(String text) {
    for (final int rune in text.runes) {
      if (rune == 10) {
        newline();
      } else if (rune == 13) {
        cursorCol = 0;
      } else if (rune == 8 || rune == 127) {
        if (cursorCol > 0) cursorCol--;
      } else {
        _put(String.fromCharCode(rune));
      }
    }
    notifyListeners();
  }

  void newline() {
    cursorRow++;
    cursorCol = 0;
    while (_lines.length <= cursorRow) {
      _lines.add(TerminalLine());
    }
    _trim();
  }

  void clear() {
    _lines
      ..clear()
      ..add(TerminalLine());
    cursorRow = 0;
    cursorCol = 0;
    notifyListeners();
  }

  void moveCursor(int row, int col) {
    cursorRow = row.clamp(0, maxLines - 1);
    cursorCol = col.clamp(0, 500);
    while (_lines.length <= cursorRow) {
      _lines.add(TerminalLine());
    }
    notifyListeners();
  }

  void _put(String char) {
    while (_lines.length <= cursorRow) {
      _lines.add(TerminalLine());
    }
    final TerminalLine line = _lines[cursorRow];
    while (line.cells.length < cursorCol) {
      line.cells.add(TerminalCell(' ', currentStyle));
    }
    final TerminalCell cell = TerminalCell(char, currentStyle);
    if (cursorCol == line.cells.length) {
      line.cells.add(cell);
    } else {
      line.cells[cursorCol] = cell;
    }
    cursorCol++;
  }

  void _trim() {
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
      cursorRow--;
    }
    if (cursorRow < 0) cursorRow = 0;
  }
}
