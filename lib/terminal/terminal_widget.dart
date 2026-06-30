import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/terminal/screen_cell.dart';
import '../core/terminal/screen_model.dart';
import '../core/terminal/terminal_emulator.dart';
import '../core/terminal_style.dart';
import 'terminal_controller.dart';

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({super.key, required this.controller});

  final TerminalController controller;

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget>
    with SingleTickerProviderStateMixin {
  static const String _inputSentinel = '\u200b';
  static const String _fontSizeKey = 'termux_flutter.terminal.font_size';
  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;

  final FocusNode _focusNode = FocusNode();
  final TextEditingController _inputController = TextEditingController(
    text: _inputSentinel,
  );
  late final AnimationController _cursorBlink;
  late final TerminalScrollController _scrollController;
  late final SelectionController _selectionController;
  Ticker? _flingTicker;
  ClampingScrollSimulation? _flingSimulation;
  Timer? _blinkResumeTimer;
  Timer? _scrollbarFadeTimer;
  bool _updatingInput = false;
  bool _showScrollbar = false;
  double _fontSize = 14;
  double _scaleStartFontSize = 14;
  int _lastCols = 0;
  int _lastRows = 0;
  int _lastScrollbackRows = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = TerminalScrollController();
    _selectionController = SelectionController();
    _cursorBlink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 0,
      upperBound: 1,
      value: 1,
    )..repeat(reverse: true);
    _loadFontSize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      widget.controller.start();
    });
  }

  @override
  void dispose() {
    _blinkResumeTimer?.cancel();
    _scrollbarFadeTimer?.cancel();
    _flingTicker?.dispose();
    _cursorBlink.dispose();
    _focusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        _cursorBlink,
      ]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final metrics = TerminalMetrics.measure(_fontSize);
            final cols = math.max(1, constraints.maxWidth ~/ metrics.cellWidth);
            final rows = math.max(
              1,
              constraints.maxHeight ~/ metrics.cellHeight,
            );
            _resizeIfNeeded(cols, rows, metrics);

            final screen = widget.controller.screen;
            _scrollController.maxTopRow = screen.scrollbackBuffer.length;
            if (_lastScrollbackRows != screen.scrollbackBuffer.length) {
              if (_scrollController.isAtBottom) {
                _scrollController.scrollToBottom();
              }
              _lastScrollbackRows = screen.scrollbackBuffer.length;
            }

            final blinkOn = _cursorBlink.value >= 0.5;
            final palette = const ColorPalette();
            final painter = TerminalPainter(
              screen: screen,
              emulator: widget.controller.emulator,
              topRow: _scrollController.topRow,
              metrics: metrics,
              palette: palette,
              selection: _selectionController.range,
              blinkOn: blinkOn,
              focused: _focusNode.hasFocus,
              debugOverlay: kDebugMode,
            );

            return Stack(
              children: [
                EditableText(
                  controller: _inputController,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    color: Colors.transparent,
                    fontSize: 1,
                  ),
                  cursorColor: Colors.transparent,
                  backgroundCursorColor: Colors.transparent,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  showCursor: false,
                  onChanged: _handleTextInput,
                  onSubmitted: (_) => _writeInput('\n'),
                ),
                KeyboardListener(
                  focusNode: _focusNode,
                  onKeyEvent: _handleKey,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _focusNode.requestFocus,
                    onDoubleTapDown: (details) =>
                        _selectWord(details.localPosition, screen, metrics),
                    onScaleStart: (details) {
                      _scaleStartFontSize = _fontSize;
                      _stopFling();
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount > 1) {
                        setState(() {
                          _fontSize = (_scaleStartFontSize * details.scale)
                              .clamp(_minFontSize, _maxFontSize);
                        });
                      } else {
                        _scrollBy(details.focalPointDelta.dy, metrics);
                      }
                    },
                    onScaleEnd: (details) {
                      _saveFontSize();
                      if (details.velocity.pixelsPerSecond.dy.abs() > 80) {
                        _startFling(
                          details.velocity.pixelsPerSecond.dy,
                          metrics,
                        );
                      }
                    },
                    onLongPressStart: (details) =>
                        _selectWord(details.localPosition, screen, metrics),
                    onLongPressMoveUpdate: (details) => _extendSelection(
                      details.localPosition,
                      screen,
                      metrics,
                    ),
                    onTertiaryTapDown: (_) => _paste(),
                    child: ColoredBox(
                      color: palette.background,
                      child: CustomPaint(
                        size: constraints.biggest,
                        painter: painter,
                      ),
                    ),
                  ),
                ),
                if (_selectionController.hasSelection)
                  SelectionHandleOverlay(
                    range: _selectionController.range!,
                    metrics: metrics,
                    topRow: _scrollController.topRow,
                    onCopy: _copySelection,
                    onPaste: _paste,
                    onDragStart: (offset) =>
                        _moveSelectionEdge(true, offset, screen, metrics),
                    onDragEnd: (offset) =>
                        _moveSelectionEdge(false, offset, screen, metrics),
                  ),
                if (!_scrollController.isAtBottom)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: IconButton.filledTonal(
                      tooltip: 'Scroll to bottom',
                      onPressed: () {
                        setState(_scrollController.scrollToBottom);
                      },
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showScrollbar ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: CustomPaint(
                      size: constraints.biggest,
                      painter: TerminalScrollbarPainter(
                        topRow: _scrollController.topRow,
                        maxTopRow: _scrollController.maxTopRow,
                        rows: screen.rows,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _resizeIfNeeded(int cols, int rows, TerminalMetrics metrics) {
    if (cols == _lastCols && rows == _lastRows) return;
    _lastCols = cols;
    _lastRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.resize(cols, rows);
      }
    });
  }

  Future<void> _loadFontSize() async {
    final settings = await TerminalFontSettings.load();
    if (!mounted) return;
    setState(() {
      _fontSize = (settings[_fontSizeKey] ?? _fontSize).clamp(
        _minFontSize,
        _maxFontSize,
      );
    });
  }

  Future<void> _saveFontSize() async {
    final settings = await TerminalFontSettings.load();
    settings[_fontSizeKey] = _fontSize;
    await TerminalFontSettings.save(settings);
  }

  void _handleTextInput(String value) {
    if (_updatingInput) return;
    if (value == _inputSentinel) return;
    if (value.isEmpty) {
      _writeInput('\x7f');
      _resetInput();
      return;
    }
    final input = value.startsWith(_inputSentinel)
        ? value.substring(_inputSentinel.length)
        : value;
    if (input.isNotEmpty) _writeInput(input);
    _resetInput();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    final emulator = widget.controller.emulator;
    if (key == LogicalKeyboardKey.enter) {
      _writeInput('\n');
    } else if (key == LogicalKeyboardKey.backspace) {
      _writeInput('\x7f');
    } else if (key == LogicalKeyboardKey.tab) {
      _writeInput('\t');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _writeInput(emulator.applicationCursorKeys ? '\x1bOA' : '\x1b[A');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _writeInput(emulator.applicationCursorKeys ? '\x1bOB' : '\x1b[B');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _writeInput(emulator.applicationCursorKeys ? '\x1bOC' : '\x1b[C');
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _writeInput(emulator.applicationCursorKeys ? '\x1bOD' : '\x1b[D');
    } else {
      final character = event.character;
      if (character != null && character.isNotEmpty) _writeInput(character);
    }
  }

  void _writeInput(String input) {
    _pauseCursorBlink();
    widget.controller.write(input);
  }

  void _pauseCursorBlink() {
    _cursorBlink.stop();
    _cursorBlink.value = 1;
    _blinkResumeTimer?.cancel();
    _blinkResumeTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _cursorBlink.repeat(reverse: true);
    });
  }

  void _resetInput() {
    _updatingInput = true;
    _inputController.value = const TextEditingValue(
      text: _inputSentinel,
      selection: TextSelection.collapsed(offset: _inputSentinel.length),
    );
    _updatingInput = false;
  }

  void _scrollBy(double pixelDelta, TerminalMetrics metrics) {
    final deltaRows = pixelDelta / metrics.cellHeight;
    setState(() {
      _scrollController.scrollBy(deltaRows);
      _showScrollbarNow();
    });
  }

  void _startFling(double velocityY, TerminalMetrics metrics) {
    _stopFling();
    _flingSimulation = ClampingScrollSimulation(
      position: _scrollController.topRow.toDouble(),
      velocity: -velocityY / metrics.cellHeight,
    );
    final start = SchedulerBinding.instance.currentFrameTimeStamp;
    _flingTicker = createTicker((elapsed) {
      final seconds =
          (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
      final simulation = _flingSimulation;
      if (simulation == null || simulation.isDone(seconds)) {
        _stopFling();
        return;
      }
      setState(() {
        _scrollController.setTopRow(simulation.x(seconds).round());
        _showScrollbarNow();
      });
    })..start();
  }

  void _stopFling() {
    _flingTicker?.dispose();
    _flingTicker = null;
    _flingSimulation = null;
  }

  void _showScrollbarNow() {
    _showScrollbar = true;
    _scrollbarFadeTimer?.cancel();
    _scrollbarFadeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showScrollbar = false);
    });
  }

  void _selectWord(Offset offset, ScreenModel screen, TerminalMetrics metrics) {
    final point = _pointFromOffset(offset, screen, metrics);
    final row = _rowAt(screen, point.row);
    if (row == null || row.isEmpty) return;
    var start = point.col.clamp(0, row.length - 1);
    var end = start;
    bool isWordCell(int col) {
      final text = row[col].char;
      return text.trim().isNotEmpty && RegExp(r'[\w./:@%+-]').hasMatch(text);
    }

    if (!isWordCell(start)) return;
    while (start > 0 && isWordCell(start - 1)) {
      start--;
    }
    while (end + 1 < row.length && isWordCell(end + 1)) {
      end++;
    }
    setState(() {
      _selectionController.range = SelectionRange(
        start: CellPoint(point.row, start),
        end: CellPoint(point.row, end + 1),
      );
    });
  }

  void _extendSelection(
    Offset offset,
    ScreenModel screen,
    TerminalMetrics metrics,
  ) {
    _moveSelectionEdge(false, offset, screen, metrics);
  }

  void _moveSelectionEdge(
    bool start,
    Offset offset,
    ScreenModel screen,
    TerminalMetrics metrics,
  ) {
    final point = _pointFromOffset(offset, screen, metrics);
    setState(() => _selectionController.moveEdge(start: start, point: point));
  }

  CellPoint _pointFromOffset(
    Offset offset,
    ScreenModel screen,
    TerminalMetrics metrics,
  ) {
    final row =
        (offset.dy / metrics.cellHeight).floor() - _scrollController.topRow;
    final col = (offset.dx / metrics.cellWidth).floor().clamp(
      0,
      screen.columns,
    );
    return CellPoint(row, col);
  }

  List<ScreenCell>? _rowAt(ScreenModel screen, int externalRow) {
    if (externalRow < 0) {
      final index = screen.scrollbackBuffer.length + externalRow;
      if (index < 0 || index >= screen.scrollbackBuffer.length) return null;
      return screen.scrollbackBuffer[index];
    }
    if (externalRow >= screen.rows) return null;
    return screen.cells[externalRow];
  }

  Future<void> _copySelection() async {
    final range = _selectionController.normalized;
    if (range == null) return;
    final text = _extractSelectedText(widget.controller.screen, range);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _writeInput(widget.controller.emulator.encodePaste(text));
  }

  String _extractSelectedText(ScreenModel screen, SelectionRange range) {
    final buffer = StringBuffer();
    for (
      var rowIndex = range.start.row;
      rowIndex <= range.end.row;
      rowIndex++
    ) {
      final row = _rowAt(screen, rowIndex);
      if (row == null) continue;
      final startCol = rowIndex == range.start.row ? range.start.col : 0;
      final endCol = rowIndex == range.end.row ? range.end.col : row.length;
      for (
        var col = startCol.clamp(0, row.length);
        col < endCol.clamp(0, row.length);
        col++
      ) {
        final cell = row[col];
        if (cell.width > 0) buffer.write(cell.char);
      }
      if (rowIndex != range.end.row) buffer.writeln();
    }
    return buffer.toString().replaceRight(RegExp(r'[ \n]+$'), '');
  }
}

final class TerminalMetrics {
  const TerminalMetrics({
    required this.fontSize,
    required this.cellWidth,
    required this.cellHeight,
    required this.baseline,
  });

  final double fontSize;
  final double cellWidth;
  final double cellHeight;
  final double baseline;

  static TerminalMetrics measure(double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'W',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = painter.computeLineMetrics().first;
    return TerminalMetrics(
      fontSize: fontSize,
      cellWidth: painter.width.ceilToDouble(),
      cellHeight: math.max(fontSize + 4, line.height.ceilToDouble()),
      baseline: line.baseline,
    );
  }
}

final class TerminalFontSettings {
  const TerminalFontSettings._();

  static Future<Map<String, double>> load() async {
    final file = await _file();
    if (!await file.exists()) return <String, double>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return <String, double>{};
      return decoded.map((key, value) {
        final numeric = value is num ? value.toDouble() : null;
        return MapEntry(key, numeric ?? 14);
      });
    } on FormatException {
      return <String, double>{};
    } on FileSystemException {
      return <String, double>{};
    }
  }

  static Future<void> save(Map<String, double> values) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values));
  }

  static Future<File> _file() async {
    final root = Directory.systemTemp;
    return File(
      '${root.path}${Platform.pathSeparator}termux_flutter_terminal.json',
    );
  }
}

final class TerminalScrollController {
  int topRow = 0;
  int maxTopRow = 0;

  bool get isAtBottom => topRow == 0;

  void scrollBy(double rows) => setTopRow(topRow + rows.round());
  void scrollToBottom() => topRow = 0;

  void setTopRow(int value) {
    topRow = value.clamp(0, maxTopRow);
  }
}

final class CellPoint implements Comparable<CellPoint> {
  const CellPoint(this.row, this.col);

  final int row;
  final int col;

  @override
  int compareTo(CellPoint other) {
    if (row != other.row) return row.compareTo(other.row);
    return col.compareTo(other.col);
  }
}

final class SelectionRange {
  const SelectionRange({required this.start, required this.end});

  final CellPoint start;
  final CellPoint end;

  SelectionRange get normalized =>
      start.compareTo(end) <= 0 ? this : SelectionRange(start: end, end: start);

  bool contains(int row, int col) {
    final range = normalized;
    final point = CellPoint(row, col);
    return point.compareTo(range.start) >= 0 && point.compareTo(range.end) < 0;
  }
}

final class SelectionController {
  SelectionRange? range;

  bool get hasSelection => range != null;
  SelectionRange? get normalized => range?.normalized;

  void moveEdge({required bool start, required CellPoint point}) {
    final current = range;
    if (current == null) return;
    range = start
        ? SelectionRange(start: point, end: current.end)
        : SelectionRange(start: current.start, end: point);
  }
}

class TerminalPainter extends CustomPainter {
  TerminalPainter({
    required this.screen,
    required this.emulator,
    required this.topRow,
    required this.metrics,
    required this.palette,
    required this.selection,
    required this.blinkOn,
    required this.focused,
    required this.debugOverlay,
  });

  final ScreenModel screen;
  final TerminalEmulator emulator;
  final int topRow;
  final TerminalMetrics metrics;
  final ColorPalette palette;
  final SelectionRange? selection;
  final bool blinkOn;
  final bool focused;
  final bool debugOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    final started = DateTime.now();
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    final visibleRows = math.min(
      screen.rows,
      (size.height / metrics.cellHeight).ceil(),
    );
    for (var visualRow = 0; visualRow < visibleRows; visualRow++) {
      final externalRow = visualRow - topRow;
      final row = _rowForExternal(externalRow);
      if (row == null) continue;
      _paintRow(canvas, row, externalRow, visualRow);
    }
    _paintCursor(canvas);
    if (debugOverlay) _paintDebug(canvas, size, started);
  }

  void _paintRow(
    Canvas canvas,
    List<ScreenCell> row,
    int externalRow,
    int visualRow,
  ) {
    var col = 0;
    while (col < row.length) {
      final cell = row[col];
      final startCol = col;
      var endCol = col + _cellColumns(cell);
      while (endCol < row.length &&
          row[endCol].width > 0 &&
          row[endCol].styleEquals(cell) &&
          selection?.contains(externalRow, endCol) ==
              selection?.contains(externalRow, startCol)) {
        endCol += _cellColumns(row[endCol]);
      }
      final run = StyleDecoder.decode(
        startCol: startCol,
        endCol: endCol,
        cell: cell,
        palette: palette,
        fontSize: metrics.fontSize,
        blinkOn: blinkOn,
      );
      final selected = selection?.contains(externalRow, startCol) ?? false;
      _paintRun(canvas, row, run, visualRow, selected);
      col = endCol;
    }
  }

  int _cellColumns(ScreenCell cell) => cell.width <= 0 ? 1 : cell.width;

  void _paintRun(
    Canvas canvas,
    List<ScreenCell> row,
    StyleRun run,
    int visualRow,
    bool selected,
  ) {
    final rect = Rect.fromLTWH(
      run.startCol * metrics.cellWidth,
      visualRow * metrics.cellHeight,
      (run.endCol - run.startCol) * metrics.cellWidth,
      metrics.cellHeight,
    );
    final bg = selected ? palette.selection : run.bg;
    if (bg.a > 0 && bg != palette.background) {
      canvas.drawRect(rect, Paint()..color = bg);
    }
    final text = StringBuffer();
    for (var col = run.startCol; col < run.endCol && col < row.length; col++) {
      final cell = row[col];
      if (cell.width > 0) text.write(cell.char);
    }
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(text: text.toString(), style: run.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final expectedWidth = (run.endCol - run.startCol) * metrics.cellWidth;
    final origin = Offset(
      run.startCol * metrics.cellWidth,
      visualRow * metrics.cellHeight +
          (metrics.cellHeight - painter.height) / 2,
    );
    if (painter.width > 0 && (painter.width - expectedWidth).abs() > 0.5) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(expectedWidth / painter.width, 1);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      painter.paint(canvas, origin);
    }
  }

  void _paintCursor(Canvas canvas) {
    if (!focused || !blinkOn || !emulator.cursorVisible) return;
    final visualRow = screen.cursorRow + topRow;
    if (visualRow < 0 || visualRow >= screen.rows) return;
    final x = screen.cursorCol * metrics.cellWidth;
    final y = visualRow * metrics.cellHeight;
    final paint = Paint()..color = palette.cursor;
    switch (emulator.cursorStyle) {
      case CursorStyle.block:
        canvas.drawRect(
          Rect.fromLTWH(x, y, metrics.cellWidth, metrics.cellHeight),
          paint,
        );
      case CursorStyle.underline:
        canvas.drawRect(
          Rect.fromLTWH(x, y + metrics.cellHeight - 2, metrics.cellWidth, 2),
          paint,
        );
      case CursorStyle.bar:
        canvas.drawRect(Rect.fromLTWH(x, y, 2, metrics.cellHeight), paint);
    }
  }

  void _paintDebug(Canvas canvas, Size size, DateTime started) {
    final elapsed = DateTime.now().difference(started);
    if (elapsed > const Duration(milliseconds: 16)) {
      debugPrint(
        'Terminal paint exceeded 16ms: ${elapsed.inMicroseconds / 1000}ms',
      );
    }
    final painter = TextPainter(
      text: TextSpan(
        text: 'topRow=$topRow cursor=${screen.cursorRow},${screen.cursorCol}',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(4, size.height - painter.height - 4));
  }

  List<ScreenCell>? _rowForExternal(int externalRow) {
    if (externalRow < 0) {
      final index = screen.scrollbackBuffer.length + externalRow;
      if (index < 0 || index >= screen.scrollbackBuffer.length) return null;
      return screen.scrollbackBuffer[index];
    }
    if (externalRow >= screen.rows) return null;
    return screen.cells[externalRow];
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) => true;
}

class TerminalScrollbarPainter extends CustomPainter {
  TerminalScrollbarPainter({
    required this.topRow,
    required this.maxTopRow,
    required this.rows,
  });

  final int topRow;
  final int maxTopRow;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxTopRow <= 0) return;
    final totalRows = maxTopRow + rows;
    final thumbHeight = math.max(24.0, size.height * rows / totalRows);
    final available = size.height - thumbHeight;
    final top = available * (maxTopRow - topRow) / maxTopRow;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 5, top, 3, thumbHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant TerminalScrollbarPainter oldDelegate) {
    return oldDelegate.topRow != topRow ||
        oldDelegate.maxTopRow != maxTopRow ||
        oldDelegate.rows != rows;
  }
}

class SelectionHandleOverlay extends StatelessWidget {
  const SelectionHandleOverlay({
    super.key,
    required this.range,
    required this.metrics,
    required this.topRow,
    required this.onCopy,
    required this.onPaste,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final SelectionRange range;
  final TerminalMetrics metrics;
  final int topRow;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final void Function(Offset offset) onDragStart;
  final void Function(Offset offset) onDragEnd;

  @override
  Widget build(BuildContext context) {
    final normalized = range.normalized;
    return Stack(
      children: [
        _handle(normalized.start, true),
        _handle(normalized.end, false),
        Positioned(
          left: 8,
          top: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Paste',
                  onPressed: onPaste,
                  icon: const Icon(
                    Icons.content_paste,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _handle(CellPoint point, bool start) {
    final left = point.col * metrics.cellWidth - 9;
    final top = (point.row + topRow + 1) * metrics.cellHeight - 9;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: (details) => start
            ? onDragStart(details.localPosition + Offset(left, top))
            : onDragEnd(details.localPosition + Offset(left, top)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xff3b82f6),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 18, height: 18),
        ),
      ),
    );
  }
}

extension on String {
  String replaceRight(RegExp pattern, String replacement) {
    final match = pattern.firstMatch(this);
    if (match == null || match.end != length) return this;
    return replaceRange(match.start, match.end, replacement);
  }
}
