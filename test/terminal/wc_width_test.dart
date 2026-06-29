import 'package:flutter_test/flutter_test.dart';
import 'package:termux_flutter/core/terminal/wc_width.dart';

void main() {
  test('ASCII printable characters are one cell wide', () {
    expect(WcWidth.of('A'.runes.single), 1);
    expect(WcWidth.of('~'.runes.single), 1);
  });

  test('control and combining characters are zero width', () {
    expect(WcWidth.of(0x07), 0);
    expect(WcWidth.of(0x0300), 0);
    expect(WcWidth.of(0xfe0f), 0);
  });

  test('CJK and emoji characters are double width', () {
    expect(WcWidth.of(0x4e00), 2);
    expect(WcWidth.of(0x1f600), 2);
  });
}
