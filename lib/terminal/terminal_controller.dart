import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/shell_bridge.dart';
import '../core/terminal/screen_model.dart';
import '../core/terminal/terminal_emulator.dart';
import 'terminal_buffer.dart';
import 'terminal_emulator_adapter.dart';

class TerminalController extends ChangeNotifier {
  TerminalController(this.bridge) : parser = TerminalEmulatorAdapter() {
    buffer.addListener(notifyListeners);
  }

  final ShellBridge bridge;
  final TerminalEmulatorAdapter parser;
  StreamSubscription<String>? _subscription;

  TerminalBuffer get buffer => parser.buffer;
  TerminalEmulator get emulator => parser.emulator;
  ScreenModel get screen => parser.emulator.screen;

  Future<void> start() async {
    _subscription ??= bridge.output.listen(parser.accept);
    await bridge.startShell();
  }

  Future<void> write(String input) => bridge.writeInput(input);

  Future<void> resize(int cols, int rows) {
    parser.resize(cols, rows);
    return bridge.resizePty(cols, rows);
  }

  Future<void> sendSignal(int signal) => bridge.sendSignal(signal);

  @override
  void dispose() {
    _subscription?.cancel();
    bridge.stopShell();
    super.dispose();
  }
}
