import 'screen_cell.dart';
import 'text_attributes.dart';

abstract interface class ScreenModelListener {
  void onScreenUpdated(ScreenModel screen);
}

final class ScreenModel {
  ScreenModel({
    required this.columns,
    required this.rows,
    this.maxScrollback = 2000,
    List<ScreenModelListener>? listeners,
  }) : scrollBottomMargin = rows - 1,
       _listeners = listeners ?? <ScreenModelListener>[] {
    _cells = List<List<ScreenCell>>.generate(rows, (_) => _blankRow());
  }

  final int columns;
  final int rows;
  final int maxScrollback;
  final List<ScreenModelListener> _listeners;
  late List<List<ScreenCell>> _cells;
  final List<List<ScreenCell>> scrollbackBuffer = <List<ScreenCell>>[];
  int cursorRow = 0;
  int cursorCol = 0;
  int scrollTopMargin = 0;
  int scrollBottomMargin;
  bool isAlternate = false;

  List<List<ScreenCell>> get cells => _cells;

  void addListener(ScreenModelListener listener) => _listeners.add(listener);

  void removeListener(ScreenModelListener listener) =>
      _listeners.remove(listener);

  void notifyListeners() {
    for (final listener in List<ScreenModelListener>.of(_listeners)) {
      listener.onScreenUpdated(this);
    }
  }

  ScreenCell cellAt(int row, int col) => _cells[row][col];

  String lineText(int row, {bool trimRight = false}) {
    final text = _cells[row]
        .map((cell) => cell.width == 0 ? '' : cell.char)
        .join();
    return trimRight ? text.replaceRight(RegExp(r' +$'), '') : text;
  }

  void setCell(int row, int col, ScreenCell cell) {
    if (!_inBounds(row, col)) return;
    _cells[row][col] = cell;
  }

  void moveCursor(int row, int col) {
    cursorRow = row.clamp(0, rows - 1);
    cursorCol = col.clamp(0, columns - 1);
  }

  void resetMargins() {
    scrollTopMargin = 0;
    scrollBottomMargin = rows - 1;
  }

  void setScrollRegion(int top, int bottom) {
    if (top < 0 ||
        bottom < 0 ||
        top >= rows ||
        bottom >= rows ||
        top >= bottom) {
      resetMargins();
      return;
    }
    scrollTopMargin = top;
    scrollBottomMargin = bottom;
    moveCursor(0, 0);
  }

  void clear([TextAttributes attributes = TextAttributes.normal]) {
    _cells = List<List<ScreenCell>>.generate(
      rows,
      (_) => _blankRow(attributes),
    );
    moveCursor(0, 0);
    resetMargins();
  }

  void eraseInDisplay(int mode, TextAttributes attributes) {
    switch (mode) {
      case 0:
        eraseInLine(0, attributes);
        for (var row = cursorRow + 1; row < rows; row++) {
          _cells[row] = _blankRow(attributes);
        }
      case 1:
        for (var row = 0; row < cursorRow; row++) {
          _cells[row] = _blankRow(attributes);
        }
        eraseInLine(1, attributes);
      case 2:
      case 3:
        for (var row = 0; row < rows; row++) {
          _cells[row] = _blankRow(attributes);
        }
        if (mode == 3) clearScrollback();
    }
  }

  void eraseInLine(int mode, TextAttributes attributes) {
    final start = switch (mode) {
      1 => 0,
      _ => cursorCol,
    };
    final end = switch (mode) {
      0 => columns - 1,
      _ => cursorCol,
    };
    for (var col = start; col <= end; col++) {
      setCell(cursorRow, col, ScreenCell.blank(attributes));
    }
  }

  void insertBlankChars(int count, TextAttributes attributes) {
    final n = count.clamp(1, columns - cursorCol);
    final row = _cells[cursorRow];
    for (var col = columns - 1; col >= cursorCol + n; col--) {
      row[col] = row[col - n];
    }
    for (var col = cursorCol; col < cursorCol + n; col++) {
      row[col] = ScreenCell.blank(attributes);
    }
  }

  void deleteChars(int count, TextAttributes attributes) {
    final n = count.clamp(1, columns - cursorCol);
    final row = _cells[cursorRow];
    for (var col = cursorCol; col < columns - n; col++) {
      row[col] = row[col + n];
    }
    for (var col = columns - n; col < columns; col++) {
      row[col] = ScreenCell.blank(attributes);
    }
  }

  void insertLines(int count, TextAttributes attributes) {
    if (cursorRow < scrollTopMargin || cursorRow > scrollBottomMargin) return;
    final n = count.clamp(1, scrollBottomMargin - cursorRow + 1);
    for (var i = 0; i < n; i++) {
      _cells.removeAt(scrollBottomMargin);
      _cells.insert(cursorRow, _blankRow(attributes));
    }
  }

  void deleteLines(int count, TextAttributes attributes) {
    if (cursorRow < scrollTopMargin || cursorRow > scrollBottomMargin) return;
    final n = count.clamp(1, scrollBottomMargin - cursorRow + 1);
    for (var i = 0; i < n; i++) {
      _cells.removeAt(cursorRow);
      _cells.insert(scrollBottomMargin, _blankRow(attributes));
    }
  }

  void scrollUp(int count, TextAttributes attributes) {
    final n = count.clamp(1, scrollBottomMargin - scrollTopMargin + 1);
    for (var i = 0; i < n; i++) {
      final removed = _cells.removeAt(scrollTopMargin);
      if (!isAlternate && scrollTopMargin == 0) {
        scrollbackBuffer.add(List<ScreenCell>.of(removed));
        if (scrollbackBuffer.length > maxScrollback) {
          scrollbackBuffer.removeAt(0);
        }
      }
      _cells.insert(scrollBottomMargin, _blankRow(attributes));
    }
  }

  void scrollDown(int count, TextAttributes attributes) {
    final n = count.clamp(1, scrollBottomMargin - scrollTopMargin + 1);
    for (var i = 0; i < n; i++) {
      _cells.removeAt(scrollBottomMargin);
      _cells.insert(scrollTopMargin, _blankRow(attributes));
    }
  }

  void clearScrollback() => scrollbackBuffer.clear();

  List<ScreenCell> _blankRow([
    TextAttributes attributes = TextAttributes.normal,
  ]) {
    return List<ScreenCell>.filled(
      columns,
      ScreenCell.blank(attributes),
      growable: true,
    );
  }

  bool _inBounds(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < columns;
}

extension on String {
  String replaceRight(RegExp pattern, String replacement) {
    final match = pattern.firstMatch(this);
    if (match == null || match.end != length) return this;
    return replaceRange(match.start, match.end, replacement);
  }
}
