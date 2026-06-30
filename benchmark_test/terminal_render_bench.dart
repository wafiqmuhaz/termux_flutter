import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/terminal_emulator.dart';
import 'package:termux_flutter/core/terminal_style.dart';
import 'package:termux_flutter/terminal/terminal_widget.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('terminal render burst stays inside frame budget', (
    tester,
  ) async {
    assert(kProfileMode, 'Run benchmark in --profile mode.');
    final emulator = TerminalEmulator(
      columns: 80,
      rows: 24,
      maxScrollback: 10000,
    );
    for (var i = 0; i < 1000; i++) {
      emulator.accept('burst line ${i.toString().padLeft(4, '0')} ');
      emulator.accept('\x1b[1;31mred\x1b[0m ');
      emulator.accept('\u754c \u{1f525} \u2500\u253c\n');
    }

    final timings = <FrameTiming>[];
    binding.addTimingsCallback(timings.addAll);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          child: CustomPaint(
            size: const Size(720, 432),
            painter: TerminalPainter(
              screen: emulator.screen,
              emulator: emulator,
              topRow: 0,
              metrics: TerminalMetrics.measure(14),
              palette: const ColorPalette(),
              selection: null,
              blinkOn: true,
              focused: true,
              debugOverlay: false,
            ),
          ),
        ),
      ),
    );

    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    timings.clear();
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final frameTimes =
        timings.map((timing) => timing.totalSpan.inMicroseconds / 1000).toList()
          ..sort();
    final p99 = frameTimes.isEmpty
        ? 0
        : frameTimes[math.min(
            frameTimes.length - 1,
            (frameTimes.length * 0.99).floor(),
          )];
    final dropped = frameTimes.where((time) => time > 16).length;

    debugPrint(
      'terminal_render_bench p99=${p99.toStringAsFixed(2)}ms dropped=$dropped frames=${frameTimes.length}',
    );
    expect(p99, lessThanOrEqualTo(16));
    expect(dropped, 0);
  });
}
