import 'dart:convert';
import 'dart:typed_data';

import 'alternate_screen.dart';
import 'color_attribute.dart';
import 'screen_cell.dart';
import 'screen_model.dart';
import 'terminal_keys.dart';
import 'text_attributes.dart';
import 'wc_width.dart';

enum ParserState {
  normal,
  esc,
  csi,
  osc,
  oscEsc,
  dcs,
  dcsEsc,
  apc,
  apcEsc,
  charset,
}

enum CursorStyle { block, underline, bar }

enum ClipboardPolicy { deny, allow }

final class TerminalEmulator {
  TerminalEmulator({
    int columns = 80,
    int rows = 24,
    int maxScrollback = 2000,
    this.clipboardPolicy = ClipboardPolicy.deny,
    this.onTitleChanged,
    this.onBell,
    this.onClipboard,
    this.onScreenUpdated,
  }) : primaryScreen = ScreenModel(
         columns: columns,
         rows: rows,
         maxScrollback: maxScrollback,
       ),
       alternateScreen = ScreenModel(
         columns: columns,
         rows: rows,
         maxScrollback: 0,
       ) {
    _alternate = AlternateScreenManager(
      primary: primaryScreen,
      alternate: alternateScreen,
    );
  }

  final ScreenModel primaryScreen;
  final ScreenModel alternateScreen;
  final ClipboardPolicy clipboardPolicy;
  final void Function(String? oldTitle, String title)? onTitleChanged;
  final void Function()? onBell;
  final void Function(String text)? onClipboard;
  final void Function(ScreenModel screen)? onScreenUpdated;

  late final AlternateScreenManager _alternate;
  final Utf8Decoder _decoder = const Utf8Decoder(allowMalformed: true);
  ParserState parserState = ParserState.normal;
  TextAttributes currentAttributes = TextAttributes.normal;
  CursorStyle cursorStyle = CursorStyle.block;
  String? title;
  bool bracketedPasteMode = false;
  bool applicationCursorKeys = false;
  bool cursorVisible = true;
  bool insertMode = false;
  bool _originMode = false;
  bool _autowrap = true;
  int? _savedRow;
  int? _savedCol;
  TextAttributes? _savedAttributes;
  final StringBuffer _csi = StringBuffer();
  final StringBuffer _stringControl = StringBuffer();
  String _charsetTarget = '(';
  int? _lastPrintable;

  ScreenModel get screen => _alternate.current;

  void processInput(Uint8List bytes) {
    accept(_decoder.convert(bytes));
  }

  void accept(String text) {
    for (final codePoint in text.runes) {
      _acceptCodePoint(codePoint);
    }
    screen.notifyListeners();
    onScreenUpdated?.call(screen);
  }

  String encodePaste(String text) {
    return bracketedPasteMode ? TerminalKeys.bracketedPaste(text) : text;
  }

  void _acceptCodePoint(int codePoint) {
    switch (parserState) {
      case ParserState.normal:
        _normal(codePoint);
      case ParserState.esc:
        _esc(codePoint);
      case ParserState.csi:
        _csiCode(codePoint);
      case ParserState.osc:
        _stringCode(
          codePoint,
          ParserState.normal,
          _dispatchOsc,
          escState: ParserState.oscEsc,
        );
      case ParserState.oscEsc:
        _stringEsc(codePoint, _dispatchOsc, ParserState.osc);
      case ParserState.dcs:
        _stringCode(
          codePoint,
          ParserState.normal,
          (_) {},
          escState: ParserState.dcsEsc,
        );
      case ParserState.dcsEsc:
        _stringEsc(codePoint, (_) {}, ParserState.dcs);
      case ParserState.apc:
        _stringCode(
          codePoint,
          ParserState.normal,
          (_) {},
          escState: ParserState.apcEsc,
        );
      case ParserState.apcEsc:
        _stringEsc(codePoint, (_) {}, ParserState.apc);
      case ParserState.charset:
        parserState = ParserState.normal;
    }
  }

  void _normal(int codePoint) {
    switch (codePoint) {
      case 0x07:
        onBell?.call();
      case 0x08:
        screen.cursorCol = (screen.cursorCol - 1).clamp(0, screen.columns - 1);
      case 0x09:
        screen.cursorCol = ((screen.cursorCol ~/ 8) + 1) * 8;
        if (screen.cursorCol >= screen.columns) {
          screen.cursorCol = screen.columns - 1;
        }
      case 0x0a:
      case 0x0b:
      case 0x0c:
        _lineFeed();
      case 0x0d:
        screen.cursorCol = 0;
      case 0x0e:
      case 0x0f:
        break;
      case 0x1b:
        parserState = ParserState.esc;
      default:
        if (codePoint >= 0x20) {
          _putCodePoint(codePoint);
        }
    }
  }

  void _esc(int codePoint) {
    parserState = ParserState.normal;
    switch (codePoint) {
      case 0x5b:
        _csi.clear();
        parserState = ParserState.csi;
      case 0x5d:
        _stringControl.clear();
        parserState = ParserState.osc;
      case 0x50:
        _stringControl.clear();
        parserState = ParserState.dcs;
      case 0x5f:
        _stringControl.clear();
        parserState = ParserState.apc;
      case 0x28:
      case 0x29:
      case 0x2a:
      case 0x2b:
        _charsetTarget = String.fromCharCode(codePoint);
        parserState = ParserState.charset;
      case 0x37:
        _saveCursor();
      case 0x38:
        _restoreCursor();
      case 0x44:
        _lineFeed();
      case 0x45:
        screen.cursorCol = 0;
        _lineFeed();
      case 0x4d:
        _reverseIndex();
      case 0x63:
        _reset();
      default:
        _charsetTarget = _charsetTarget;
    }
  }

  void _csiCode(int codePoint) {
    if (codePoint >= 0x40 && codePoint <= 0x7e) {
      final sequence = _csi.toString();
      parserState = ParserState.normal;
      _dispatchCsi(sequence, String.fromCharCode(codePoint));
      return;
    }
    if (_csi.length < 128) {
      _csi.writeCharCode(codePoint);
    }
  }

  void _stringCode(
    int codePoint,
    ParserState endState,
    void Function(String value) dispatch, {
    required ParserState escState,
  }) {
    if (codePoint == 0x07 || codePoint == 0x9c) {
      parserState = endState;
      dispatch(_stringControl.toString());
      _stringControl.clear();
    } else if (codePoint == 0x1b) {
      parserState = escState;
    } else if (_stringControl.length < 8192) {
      _stringControl.writeCharCode(codePoint);
    }
  }

  void _stringEsc(
    int codePoint,
    void Function(String value) dispatch,
    ParserState resume,
  ) {
    if (codePoint == 0x5c) {
      parserState = ParserState.normal;
      dispatch(_stringControl.toString());
      _stringControl.clear();
    } else {
      if (_stringControl.length < 8192) {
        _stringControl
          ..writeCharCode(0x1b)
          ..writeCharCode(codePoint);
      }
      parserState = resume;
    }
  }

  void _dispatchCsi(String raw, String finalByte) {
    final private = raw.startsWith('?');
    final clean = raw
        .replaceAll(RegExp(r'^[?>!]'), '')
        .replaceAll(RegExp(r'''[$ "']'''), '');
    final params = _parseParams(clean);
    final first = _param(params, 0, 1);
    switch (finalByte) {
      case 'A':
        screen.cursorRow = (screen.cursorRow - first).clamp(0, screen.rows - 1);
      case 'B':
        screen.cursorRow = (screen.cursorRow + first).clamp(0, screen.rows - 1);
      case 'C':
        screen.cursorCol = (screen.cursorCol + first).clamp(
          0,
          screen.columns - 1,
        );
      case 'D':
        screen.cursorCol = (screen.cursorCol - first).clamp(
          0,
          screen.columns - 1,
        );
      case 'G':
        screen.cursorCol = (first - 1).clamp(0, screen.columns - 1);
      case 'H':
      case 'f':
        _cursorPosition(params);
      case 'J':
        screen.eraseInDisplay(_param(params, 0, 0), currentAttributes);
      case 'K':
        screen.eraseInLine(_param(params, 0, 0), currentAttributes);
      case 'L':
        screen.insertLines(first, currentAttributes);
      case 'M':
        screen.deleteLines(first, currentAttributes);
      case 'P':
        screen.deleteChars(first, currentAttributes);
      case '@':
        screen.insertBlankChars(first, currentAttributes);
      case 'S':
        screen.scrollUp(first, currentAttributes);
      case 'T':
        screen.scrollDown(first, currentAttributes);
      case 'X':
        _eraseChars(first);
      case 'b':
        if (_lastPrintable != null) {
          for (var i = 0; i < first; i++) {
            _putCodePoint(_lastPrintable!);
          }
        }
      case 'm':
        _sgr(params.isEmpty ? <int>[0] : params);
      case 'r':
        final top = _param(params, 0, 1) - 1;
        final bottom = _param(params, 1, screen.rows) - 1;
        screen.setScrollRegion(top, bottom);
      case 'h':
        _mode(params, private, true);
      case 'l':
        _mode(params, private, false);
      case 's':
        _saveCursor();
      case 'u':
        _restoreCursor();
      case 't':
        _windowOp(params);
      case 'q':
        if (raw.contains(' ')) _cursorStyle(first);
    }
  }

  List<int> _parseParams(String raw) {
    if (raw.isEmpty) return <int>[];
    return raw
        .split(';')
        .map((part) => part.contains(':') ? part.split(':').first : part)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  int _param(List<int> params, int index, int defaultValue) {
    if (index >= params.length || params[index] == 0) return defaultValue;
    return params[index];
  }

  void _cursorPosition(List<int> params) {
    var row = _param(params, 0, 1) - 1;
    final col = _param(params, 1, 1) - 1;
    if (_originMode) row += screen.scrollTopMargin;
    screen.moveCursor(row, col);
  }

  void _sgr(List<int> params) {
    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      switch (p) {
        case 0:
          currentAttributes = TextAttributes.normal;
        case 1:
          currentAttributes = currentAttributes.copyWith(
            bold: true,
            faint: false,
          );
        case 2:
          currentAttributes = currentAttributes.copyWith(
            faint: true,
            bold: false,
          );
        case 3:
          currentAttributes = currentAttributes.copyWith(italic: true);
        case 4:
          currentAttributes = currentAttributes.copyWith(underline: true);
        case 5:
          currentAttributes = currentAttributes.copyWith(blink: true);
        case 7:
          currentAttributes = currentAttributes.copyWith(reverse: true);
        case 8:
          currentAttributes = currentAttributes.copyWith(invisible: true);
        case 9:
          currentAttributes = currentAttributes.copyWith(strikethrough: true);
        case 22:
          currentAttributes = currentAttributes.copyWith(
            bold: false,
            faint: false,
          );
        case 23:
          currentAttributes = currentAttributes.copyWith(italic: false);
        case 24:
          currentAttributes = currentAttributes.copyWith(underline: false);
        case 25:
          currentAttributes = currentAttributes.copyWith(blink: false);
        case 27:
          currentAttributes = currentAttributes.copyWith(reverse: false);
        case 28:
          currentAttributes = currentAttributes.copyWith(invisible: false);
        case 29:
          currentAttributes = currentAttributes.copyWith(strikethrough: false);
        case 38:
          final result = _extendedColor(params, i);
          if (result != null) {
            currentAttributes = currentAttributes.copyWith(
              foreground: result.color,
            );
            i = result.nextIndex;
          }
        case 39:
          currentAttributes = currentAttributes.copyWith(
            foreground: const ColorAttribute.defaultColor(),
          );
        case 48:
          final result = _extendedColor(params, i);
          if (result != null) {
            currentAttributes = currentAttributes.copyWith(
              background: result.color,
            );
            i = result.nextIndex;
          }
        case 49:
          currentAttributes = currentAttributes.copyWith(
            background: const ColorAttribute.defaultColor(),
          );
        default:
          if (p >= 30 && p <= 37) {
            currentAttributes = currentAttributes.copyWith(
              foreground: ColorAttribute.named8(p - 30),
            );
          } else if (p >= 40 && p <= 47) {
            currentAttributes = currentAttributes.copyWith(
              background: ColorAttribute.named8(p - 40),
            );
          } else if (p >= 90 && p <= 97) {
            currentAttributes = currentAttributes.copyWith(
              foreground: ColorAttribute.named16(p - 90 + 8),
            );
          } else if (p >= 100 && p <= 107) {
            currentAttributes = currentAttributes.copyWith(
              background: ColorAttribute.named16(p - 100 + 8),
            );
          }
      }
    }
  }

  _ColorParse? _extendedColor(List<int> params, int index) {
    if (index + 2 >= params.length) return null;
    final mode = params[index + 1];
    if (mode == 5 && index + 2 < params.length) {
      return _ColorParse(
        ColorAttribute.indexed256(params[index + 2].clamp(0, 255)),
        index + 2,
      );
    }
    if (mode == 2 && index + 4 < params.length) {
      return _ColorParse(
        ColorAttribute.trueColor(
          params[index + 2].clamp(0, 255),
          params[index + 3].clamp(0, 255),
          params[index + 4].clamp(0, 255),
        ),
        index + 4,
      );
    }
    return null;
  }

  void _mode(List<int> params, bool private, bool enabled) {
    for (final param in params) {
      if (private) {
        switch (param) {
          case 1:
            applicationCursorKeys = enabled;
          case 6:
            _originMode = enabled;
            screen.moveCursor(enabled ? screen.scrollTopMargin : 0, 0);
          case 7:
            _autowrap = enabled;
          case 25:
            cursorVisible = enabled;
          case 1047:
          case 1049:
            if (enabled) {
              if (param == 1049) _saveCursor();
              _alternate.enter(attributes: currentAttributes);
            } else {
              currentAttributes = _alternate.exit(
                attributes: currentAttributes,
              );
              if (param == 1049) _restoreCursor();
            }
          case 2004:
            bracketedPasteMode = enabled;
        }
      } else if (param == 4) {
        insertMode = enabled;
      }
    }
  }

  void _dispatchOsc(String value) {
    final parts = value.split(';');
    if (parts.isEmpty) return;
    final code = int.tryParse(parts.first);
    switch (code) {
      case 0:
      case 1:
      case 2:
        if (parts.length > 1) _setTitle(parts.sublist(1).join(';'));
      case 52:
        if (clipboardPolicy == ClipboardPolicy.allow && parts.length > 2) {
          try {
            final decoded = utf8.decode(
              base64.decode(parts.sublist(2).join(';')),
              allowMalformed: true,
            );
            onClipboard?.call(decoded);
          } on FormatException {
            return;
          }
        }
      case 4:
      case 10:
      case 11:
      case 12:
        break;
    }
  }

  void _setTitle(String nextTitle) {
    if (nextTitle == title) return;
    final oldTitle = title;
    title = nextTitle;
    onTitleChanged?.call(oldTitle, nextTitle);
  }

  void _cursorStyle(int value) {
    cursorStyle = switch (value) {
      3 || 4 => CursorStyle.underline,
      5 || 6 => CursorStyle.bar,
      _ => CursorStyle.block,
    };
  }

  void _windowOp(List<int> params) {
    final op = _param(params, 0, 0);
    if (op == 22) {
      _savedAttributes = currentAttributes;
    } else if (op == 23 && _savedAttributes != null) {
      currentAttributes = _savedAttributes!;
    }
  }

  void _putCodePoint(int codePoint) {
    final width = WcWidth.of(codePoint);
    if (width == 0) {
      _composeCodePoint(codePoint);
      return;
    }
    if (screen.cursorCol >= screen.columns) {
      if (_autowrap) {
        screen.cursorCol = 0;
        _lineFeed();
      } else {
        screen.cursorCol = screen.columns - 1;
      }
    }
    if (width == 2 && screen.cursorCol == screen.columns - 1) {
      screen.setCell(
        screen.cursorRow,
        screen.cursorCol,
        ScreenCell.blank(currentAttributes),
      );
      screen.cursorCol = 0;
      _lineFeed();
    }
    if (insertMode) screen.insertBlankChars(width, currentAttributes);
    final char = String.fromCharCode(codePoint);
    final cell = ScreenCell(
      char: char,
      width: width,
      foreground: currentAttributes.foreground,
      background: currentAttributes.background,
      attributes: currentAttributes,
    );
    screen.setCell(screen.cursorRow, screen.cursorCol, cell);
    if (width == 2 && screen.cursorCol + 1 < screen.columns) {
      screen.setCell(
        screen.cursorRow,
        screen.cursorCol + 1,
        ScreenCell.blank(currentAttributes).copyWith(width: 0),
      );
    }
    screen.cursorCol += width;
    if (screen.cursorCol >= screen.columns && !_autowrap) {
      screen.cursorCol = screen.columns - 1;
    }
    _lastPrintable = codePoint;
  }

  void _composeCodePoint(int codePoint) {
    var col = screen.cursorCol - 1;
    if (col < 0 && screen.cursorRow > 0) col = screen.columns - 1;
    final row = screen.cursorCol == 0 && screen.cursorRow > 0
        ? screen.cursorRow - 1
        : screen.cursorRow;
    if (row < 0 || col < 0) return;
    final previous = screen.cellAt(row, col);
    screen.setCell(
      row,
      col,
      previous.copyWith(char: previous.char + String.fromCharCode(codePoint)),
    );
  }

  void _lineFeed() {
    if (screen.cursorRow == screen.scrollBottomMargin) {
      screen.scrollUp(1, currentAttributes);
    } else {
      screen.cursorRow = (screen.cursorRow + 1).clamp(0, screen.rows - 1);
    }
  }

  void _reverseIndex() {
    if (screen.cursorRow == screen.scrollTopMargin) {
      screen.scrollDown(1, currentAttributes);
    } else {
      screen.cursorRow = (screen.cursorRow - 1).clamp(0, screen.rows - 1);
    }
  }

  void _eraseChars(int count) {
    final n = count.clamp(1, screen.columns - screen.cursorCol);
    for (var i = 0; i < n; i++) {
      screen.setCell(
        screen.cursorRow,
        screen.cursorCol + i,
        ScreenCell.blank(currentAttributes),
      );
    }
  }

  void _saveCursor() {
    _savedRow = screen.cursorRow;
    _savedCol = screen.cursorCol;
    _savedAttributes = currentAttributes;
  }

  void _restoreCursor() {
    if (_savedRow != null && _savedCol != null) {
      screen.moveCursor(_savedRow!, _savedCol!);
    }
    if (_savedAttributes != null) currentAttributes = _savedAttributes!;
  }

  void _reset() {
    currentAttributes = TextAttributes.normal;
    bracketedPasteMode = false;
    applicationCursorKeys = false;
    cursorVisible = true;
    insertMode = false;
    _originMode = false;
    _autowrap = true;
    primaryScreen.clear();
    alternateScreen.clear();
    _alternate.current = primaryScreen;
  }
}

final class _ColorParse {
  const _ColorParse(this.color, this.nextIndex);

  final ColorAttribute color;
  final int nextIndex;
}
