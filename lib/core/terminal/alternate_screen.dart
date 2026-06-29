import 'screen_model.dart';
import 'text_attributes.dart';

final class AlternateScreenManager {
  AlternateScreenManager({
    required ScreenModel primary,
    required ScreenModel alternate,
  }) : _primary = primary,
       _alternate = alternate,
       current = primary;

  final ScreenModel _primary;
  final ScreenModel _alternate;
  ScreenModel current;
  _SavedState? _primaryState;

  bool get isAlternateActive => identical(current, _alternate);

  void enter({required TextAttributes attributes}) {
    if (isAlternateActive) return;
    _primaryState = _SavedState(
      _primary.cursorRow,
      _primary.cursorCol,
      attributes,
    );
    _alternate
      ..isAlternate = true
      ..clear(attributes);
    current = _alternate;
  }

  TextAttributes exit({required TextAttributes attributes}) {
    if (!isAlternateActive) return attributes;
    final saved = _primaryState;
    current = _primary;
    if (saved != null) {
      _primary.moveCursor(saved.cursorRow, saved.cursorCol);
      return saved.attributes;
    }
    return attributes;
  }
}

final class _SavedState {
  const _SavedState(this.cursorRow, this.cursorCol, this.attributes);

  final int cursorRow;
  final int cursorCol;
  final TextAttributes attributes;
}
