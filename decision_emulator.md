# Phase 2 Emulator Decision

## Decision

Port Termux `TerminalEmulator.java` concepts into a pure Dart core instead of adopting `xterm` as the Phase 2 emulator.

## xterm Evaluation

`flutter pub add xterm` resolved `xterm 4.0.0`. Local source inspection found useful support for OSC callbacks, bracketed paste, input handling, and a Flutter terminal view, but its public model is not the renderer-neutral `ScreenModel` required by this migration phase.

| Category | xterm 4.0.0 result | Phase 2 requirement | Decision impact |
| --- | --- | --- | --- |
| CSI cursor/erase/scroll | Supported internally | Must expose through project-owned cells and tests | Adapter would duplicate screen state |
| OSC title | `onTitleChange` exists | Must expose old/new title from core | Usable but adapter-specific |
| OSC clipboard | Private OSC callback exists | Must enforce project clipboard policy | Requires wrapper policy layer |
| Alternate screen | Supported internally | Must preserve primary `ScreenModel` and cursor state | Requires model translation |
| Bracketed paste | Supported | Must be available without Flutter widget dependency | Usable but tied to xterm terminal object |
| Unicode width | Supported internally | Must embed/own Termux-compatible `WcWidth` behavior | Project needs own table/tests |
| Renderer-neutral API | Not the requested API | `ScreenModel`, `ScreenCell`, listener interface | Fails adoption threshold |

Representative upstream-derived Dart tests were implemented under `test/terminal/` for CSI mutation, scroll regions, alternate screen, OSC title, BEL, DCS/APC consume behavior, SGR colors, Unicode width, and screen model behavior. Because adopting `xterm` would require a second project-owned model adapter and would not directly satisfy P8, the selected path is a Dart port-style core.

## Implementation Summary

- `lib/core/terminal/terminal_emulator.dart` owns byte input, parser states, CSI/OSC/DCS/APC dispatch, SGR, DECSET, scroll regions, alternate screen, title, bell, clipboard policy, cursor style, and bracketed paste.
- `lib/core/terminal/screen_model.dart` owns renderer-neutral visible cells, cursor, scroll margins, scrollback, and listener callbacks.
- `lib/core/terminal/wc_width.dart` embeds Unicode-width ranges for zero-width combining characters, CJK, and emoji.
- `lib/terminal/terminal_emulator_adapter.dart` bridges the new core into the current Phase 1/early Phase 3 Flutter painter without changing PTY or Android code.

## Root Cause

The previous live terminal path used `AnsiParser` and `TerminalBuffer`, which parsed only a small CSI subset and stored Flutter `TextStyle` cells. That caused sequence corruption for full-screen programs because terminal byte semantics were mixed with rendering assumptions.

## Source References

- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalEmulator.java`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalBuffer.java`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/WcWidth.java`
- `termux-app/terminal-emulator/src/test/java/com/termux/terminal/`
- Pub cache inspection of `xterm 4.0.0`

## Validation Command

`flutter test test/terminal/ --reporter=expanded`
