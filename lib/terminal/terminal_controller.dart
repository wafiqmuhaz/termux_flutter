import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/shell_bridge.dart';
import 'ansi_parser.dart';
import 'terminal_buffer.dart';

class TerminalController extends ChangeNotifier {
  TerminalController(this.bridge) : parser = AnsiParser(TerminalBuffer()) {
    buffer.addListener(notifyListeners);
  }

  final ShellBridge bridge;
  final AnsiParser parser;
  StreamSubscription<String>? _subscription;

  TerminalBuffer get buffer => parser.buffer;

  Future<void> start() async {
    _subscription ??= bridge.output.listen(parser.accept);
    await bridge.startShell();
  }

  Future<void> write(String input) => bridge.writeInput(input);

  Future<void> resize(int cols, int rows) => bridge.resizePty(cols, rows);

  Future<void> sendSignal(int signal) => bridge.sendSignal(signal);

  @override
  void dispose() {
    _subscription?.cancel();
    bridge.stopShell();
    super.dispose();
  }
}
