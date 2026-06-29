sealed class ColorAttribute {
  const ColorAttribute();

  const factory ColorAttribute.defaultColor() = DefaultColor;
  const factory ColorAttribute.named8(int index) = Named8Color;
  const factory ColorAttribute.named16(int index) = Named16Color;
  const factory ColorAttribute.indexed256(int index) = Indexed256Color;
  const factory ColorAttribute.trueColor(int red, int green, int blue) =
      TrueColor;

  int? get paletteIndex => switch (this) {
    DefaultColor() => null,
    Named8Color(:final index) => index,
    Named16Color(:final index) => index,
    Indexed256Color(:final index) => index,
    TrueColor() => null,
  };
}

final class DefaultColor extends ColorAttribute {
  const DefaultColor();

  @override
  bool operator ==(Object other) => other is DefaultColor;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'DefaultColor()';
}

final class Named8Color extends ColorAttribute {
  const Named8Color(this.index) : assert(index >= 0 && index < 8);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is Named8Color && other.index == index;

  @override
  int get hashCode => Object.hash(Named8Color, index);

  @override
  String toString() => 'Named8Color($index)';
}

final class Named16Color extends ColorAttribute {
  const Named16Color(this.index) : assert(index >= 0 && index < 16);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is Named16Color && other.index == index;

  @override
  int get hashCode => Object.hash(Named16Color, index);

  @override
  String toString() => 'Named16Color($index)';
}

final class Indexed256Color extends ColorAttribute {
  const Indexed256Color(this.index) : assert(index >= 0 && index < 256);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is Indexed256Color && other.index == index;

  @override
  int get hashCode => Object.hash(Indexed256Color, index);

  @override
  String toString() => 'Indexed256Color($index)';
}

final class TrueColor extends ColorAttribute {
  const TrueColor(this.red, this.green, this.blue)
    : assert(red >= 0 && red <= 255),
      assert(green >= 0 && green <= 255),
      assert(blue >= 0 && blue <= 255);

  final int red;
  final int green;
  final int blue;

  @override
  bool operator ==(Object other) =>
      other is TrueColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(TrueColor, red, green, blue);

  @override
  String toString() => 'TrueColor($red, $green, $blue)';
}
