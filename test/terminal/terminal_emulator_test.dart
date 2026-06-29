import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/terminal_emulator.dart';

void main() {
  test('prints UTF-8 bytes into renderer neutral screen cells', () {
    final terminal = TerminalEmulator(columns: 6, rows: 2);

    terminal.processInput(Uint8List.fromList(utf8.encode('A一B')));

    expect(terminal.screen.cellAt(0, 0).char, 'A');
    expect(terminal.screen.cellAt(0, 1).char, '一');
    expect(terminal.screen.cellAt(0, 1).width, 2);
    expect(terminal.screen.cellAt(0, 2).width, 0);
    expect(terminal.screen.cellAt(0, 3).char, 'B');
  });

  test('CSI cursor movement and erase in line mirror upstream behavior', () {
    final terminal = TerminalEmulator(columns: 8, rows: 2);

    terminal.accept('abcdef\x1b[3D\x1b[KZ');

    expect(terminal.screen.lineText(0), 'abcZ    ');
  });

  test('CSI insert and delete character mutate only the current row', () {
    final terminal = TerminalEmulator(columns: 8, rows: 2);

    terminal.accept('abcdef\x1b[3D\x1b[2@XY');
    expect(terminal.screen.lineText(0), 'abcXYdef');

    terminal.accept('\x1b[1;4H\x1b[2P');
    expect(terminal.screen.lineText(0), 'abcdef  ');
  });

  test('scroll region clips line feed scrolling', () {
    final terminal = TerminalEmulator(columns: 4, rows: 5);

    terminal.accept('0\r\n1\r\n2\r\n3\r\n4');
    terminal.accept('\x1b[2;4r\x1b[4;1H\n');

    expect(terminal.screen.cellAt(0, 0).char, '0');
    expect(terminal.screen.cellAt(1, 0).char, '2');
    expect(terminal.screen.cellAt(2, 0).char, '3');
    expect(terminal.screen.cellAt(3, 0).char, ' ');
    expect(terminal.screen.cellAt(4, 0).char, '4');
  });

  test('alternate screen swaps without corrupting primary content', () {
    final terminal = TerminalEmulator(columns: 5, rows: 2);

    terminal.accept('main\x1b[?1049halt');

    expect(terminal.screen.isAlternate, isTrue);
    expect(terminal.screen.lineText(0), 'alt  ');

    terminal.accept('\x1b[?1049l');

    expect(terminal.screen.isAlternate, isFalse);
    expect(terminal.screen.lineText(0), 'main ');
  });

  test('OSC title and BEL callbacks fire', () {
    final titles = <String>[];
    var bells = 0;
    final terminal = TerminalEmulator(
      onTitleChanged: (_, title) => titles.add(title),
      onBell: () => bells++,
    );

    terminal.accept('\x1b]0;Hello\x07\x07\x1b]2;World\x1b\\');

    expect(titles, <String>['Hello', 'World']);
    expect(bells, 1);
  });

  test('DCS and APC are consumed without rendering payload text', () {
    final terminal = TerminalEmulator(columns: 8, rows: 2);

    terminal.accept('A\x1bPignored\x1b\\B\x1b_ignored\x1b\\C');

    expect(terminal.screen.lineText(0), 'ABC     ');
  });

  test('bracketed paste mode wraps paste payload', () {
    final terminal = TerminalEmulator();

    terminal.accept('\x1b[?2004h');

    expect(terminal.bracketedPasteMode, isTrue);
    expect(terminal.encodePaste('x'), '\x1b[200~x\x1b[201~');
  });
}
