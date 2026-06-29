import 'color_attribute.dart';

final class TextAttributes {
  const TextAttributes({
    this.bold = false,
    this.faint = false,
    this.italic = false,
    this.underline = false,
    this.blink = false,
    this.reverse = false,
    this.strikethrough = false,
    this.invisible = false,
    this.foreground = const ColorAttribute.defaultColor(),
    this.background = const ColorAttribute.defaultColor(),
  });

  static const normal = TextAttributes();

  final bool bold;
  final bool faint;
  final bool italic;
  final bool underline;
  final bool blink;
  final bool reverse;
  final bool strikethrough;
  final bool invisible;
  final ColorAttribute foreground;
  final ColorAttribute background;

  TextAttributes copyWith({
    bool? bold,
    bool? faint,
    bool? italic,
    bool? underline,
    bool? blink,
    bool? reverse,
    bool? strikethrough,
    bool? invisible,
    ColorAttribute? foreground,
    ColorAttribute? background,
  }) {
    return TextAttributes(
      bold: bold ?? this.bold,
      faint: faint ?? this.faint,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      blink: blink ?? this.blink,
      reverse: reverse ?? this.reverse,
      strikethrough: strikethrough ?? this.strikethrough,
      invisible: invisible ?? this.invisible,
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TextAttributes &&
        other.bold == bold &&
        other.faint == faint &&
        other.italic == italic &&
        other.underline == underline &&
        other.blink == blink &&
        other.reverse == reverse &&
        other.strikethrough == strikethrough &&
        other.invisible == invisible &&
        other.foreground == foreground &&
        other.background == background;
  }

  @override
  int get hashCode => Object.hash(
    bold,
    faint,
    italic,
    underline,
    blink,
    reverse,
    strikethrough,
    invisible,
    foreground,
    background,
  );
}
