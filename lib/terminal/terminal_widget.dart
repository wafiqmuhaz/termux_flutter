import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'terminal_buffer.dart';
import 'terminal_controller.dart';

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({super.key, required this.controller});

  final TerminalController controller;

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController(text: _inputSentinel);
  Timer? _cursorTimer;
  bool _cursorVisible = true;
  bool _updatingInput = false;
  int _lastCols = 0;
  int _lastRows = 0;

  static const String _inputSentinel = '\u200b';

  @override
  void initState() {
    super.initState();
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      widget.controller.start();
    });
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const double cellWidth = 8.8;
            const double cellHeight = 18.0;
            final int cols = math.max(1, constraints.maxWidth ~/ cellWidth);
            final int rows = math.max(1, constraints.maxHeight ~/ cellHeight);
            if (cols != _lastCols || rows != _lastRows) {
              _lastCols = cols;
              _lastRows = rows;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.controller.resize(cols, rows);
              });
            }
            final double contentHeight =
                math.max(constraints.maxHeight, widget.controller.buffer.lines.length * cellHeight);

            return Stack(
              children: [
                EditableText(
                  controller: _inputController,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  cursorColor: Colors.transparent,
                  backgroundCursorColor: Colors.transparent,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  showCursor: false,
                  onChanged: _handleTextInput,
                  onSubmitted: (_) => widget.controller.write('\n'),
                ),
                GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _focusNode.requestFocus,
                child: Container(
                  color: const Color(0xff111111),
                  child: Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      reverse: true,
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, contentHeight),
                        painter: _TerminalPainter(
                          buffer: widget.controller.buffer,
                          cellWidth: cellWidth,
                          cellHeight: cellHeight,
                          cursorVisible: _cursorVisible && _focusNode.hasFocus,
                        ),
                      ),
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

  void _handleTextInput(String value) {
    if (_updatingInput) return;

    if (value == _inputSentinel) return;

    if (value.isEmpty) {
      widget.controller.write('\x7f');
      _resetInput();
      return;
    }

    final String input = value.startsWith(_inputSentinel) ? value.substring(_inputSentinel.length) : value;
    if (input.isNotEmpty) {
      widget.controller.write(input);
    }
    _resetInput();
  }

  void _resetInput() {
    _updatingInput = true;
    _inputController.value = const TextEditingValue(
      text: _inputSentinel,
      selection: TextSelection.collapsed(offset: _inputSentinel.length),
    );
    _updatingInput = false;
  }

  void _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter) {
      widget.controller.write('\n');
    } else if (key == LogicalKeyboardKey.backspace) {
      widget.controller.write('\x7f');
    } else if (key == LogicalKeyboardKey.tab) {
      widget.controller.write('\t');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.write('\x1b[A');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.write('\x1b[B');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.write('\x1b[C');
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.write('\x1b[D');
    } else {
      final String? character = event.character;
      if (character != null && character.isNotEmpty) {
        widget.controller.write(character);
      }
    }
  }
}

class _TerminalPainter extends CustomPainter {
  _TerminalPainter({
    required this.buffer,
    required this.cellWidth,
    required this.cellHeight,
    required this.cursorVisible,
  });

  final TerminalBuffer buffer;
  final double cellWidth;
  final double cellHeight;
  final bool cursorVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint cursorPaint = Paint()..color = const Color(0xffeeeeee);
    final TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
    final int visibleStart = math.max(0, buffer.lines.length - (size.height / cellHeight).ceil() - 2);

    for (int row = visibleStart; row < buffer.lines.length; row++) {
      final TerminalLine line = buffer.lines[row];
      for (int col = 0; col < line.cells.length; col++) {
        final TerminalCell cell = line.cells[col];
        painter.text = TextSpan(
          text: cell.text,
          style: cell.style.copyWith(
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1,
          ),
        );
        painter.layout(minWidth: cellWidth, maxWidth: cellWidth);
        painter.paint(canvas, Offset(col * cellWidth, row * cellHeight));
      }
    }

    if (cursorVisible) {
      canvas.drawRect(
        Rect.fromLTWH(buffer.cursorCol * cellWidth, buffer.cursorRow * cellHeight, cellWidth, 2),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerminalPainter oldDelegate) {
    return oldDelegate.buffer != buffer || oldDelegate.cursorVisible != cursorVisible;
  }
}
