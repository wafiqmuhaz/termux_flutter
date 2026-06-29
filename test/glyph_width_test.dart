import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/glyph_width.dart';

void main() {
  group('columnWidth', () {
    test('ASCII printable characters occupy one column', () {
      for (final codepoint in <int>[
        0x20,
        0x21,
        0x30,
        0x39,
        0x41,
        0x5a,
        0x61,
        0x7a,
        0x7e,
      ]) {
        expect(columnWidth(codepoint), 1);
      }
    });

    test('control and combining characters occupy zero columns', () {
      for (final codepoint in <int>[
        0x00,
        0x08,
        0x1b,
        0x7f,
        0x0301,
        0x0308,
        0x200d,
        0xfe0f,
      ]) {
        expect(columnWidth(codepoint), 0);
      }
    });

    test('CJK and Hangul characters occupy two columns', () {
      for (final codepoint in <int>[
        0x1100,
        0x2e80,
        0x3042,
        0x30a2,
        0x3400,
        0x4e00,
        0x754c,
        0xac00,
        0xf900,
        0xff21,
      ]) {
        expect(columnWidth(codepoint), 2);
      }
    });

    test('box drawing characters remain single-column', () {
      for (final codepoint in <int>[
        0x2500,
        0x2502,
        0x250c,
        0x2510,
        0x2514,
        0x2518,
        0x251c,
        0x2524,
        0x253c,
        0x257f,
      ]) {
        expect(columnWidth(codepoint), 1);
      }
    });

    test('emoji occupy two columns', () {
      for (final codepoint in <int>[
        0x1f300,
        0x1f308,
        0x1f31f,
        0x1f525,
        0x1f600,
        0x1f680,
        0x1f9d1,
        0x1fa75,
      ]) {
        expect(columnWidth(codepoint), 2);
      }
    });
  });
}
