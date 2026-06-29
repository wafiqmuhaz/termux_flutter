import 'color_attribute.dart';
import 'text_attributes.dart';

final class ScreenCell {
  const ScreenCell({
    this.char = ' ',
    this.width = 1,
    this.foreground = const ColorAttribute.defaultColor(),
    this.background = const ColorAttribute.defaultColor(),
    this.attributes = TextAttributes.normal,
  });

  factory ScreenCell.blank([
    TextAttributes attributes = TextAttributes.normal,
  ]) {
    return ScreenCell(
      foreground: attributes.foreground,
      background: attributes.background,
      attributes: attributes,
    );
  }

  final String char;
  final int width;
  final ColorAttribute foreground;
  final ColorAttribute background;
  final TextAttributes attributes;

  ScreenCell copyWith({
    String? char,
    int? width,
    ColorAttribute? foreground,
    ColorAttribute? background,
    TextAttributes? attributes,
  }) {
    return ScreenCell(
      char: char ?? this.char,
      width: width ?? this.width,
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      attributes: attributes ?? this.attributes,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenCell &&
        other.char == char &&
        other.width == width &&
        other.foreground == foreground &&
        other.background == background &&
        other.attributes == attributes;
  }

  @override
  int get hashCode =>
      Object.hash(char, width, foreground, background, attributes);
}
