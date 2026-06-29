# Migration Agents

This file defines specialized LLM coding-agent roles for migrating `termux_flutter` toward upstream Termux behavior. Each agent must read `ARCHITECTURE.md`, `ROADMAP.md`, and the input files listed for its role before editing code.

## Coordination Protocol

1. `ArchitectureAgent` owns cross-file design decisions and updates architecture docs.
2. `PTYBridgeAgent`, `BootstrapAgent`, and `SessionLifecycleAgent` run first because no terminal parity exists without process correctness.
3. `VTEmulatorAgent`, `UIRenderAgent`, and `KeyboardAgent` run after PTY contracts are stable.
4. `PluginBridgeAgent`, `StorageAgent`, and `ThemeAgent` run after shell sessions and `$PREFIX` are reliable.
5. `TestingAgent`, `SecurityAgent`, and `DocumentationAgent` review every phase before merge.
6. Agents must avoid modifying unrelated files and must record root cause, source reference, and validation command in every handoff.

## Agent Priority Order

1. ArchitectureAgent
2. PTYBridgeAgent
3. BootstrapAgent
4. SessionLifecycleAgent
5. VTEmulatorAgent
6. UIRenderAgent
7. KeyboardAgent
8. StorageAgent
9. PluginBridgeAgent
10. ThemeAgent
11. TestingAgent
12. SecurityAgent
13. DocumentationAgent

## ArchitectureAgent

**Role:** Maintains the migration architecture and keeps Flutter, Android, native C, and Termux upstream concepts aligned.

**Responsibilities:**

- Map current `termux_flutter` components to upstream `termux-app` modules.
- Approve boundary decisions between Dart, platform channels, Android services, and JNI.
- Keep `ARCHITECTURE.md`, `ROADMAP.md`, and `DESC_ROADMAP.md` consistent.
- Reject designs that fake Termux behavior with `/system/bin/sh`.

**Input Sources:**

- `ARCHITECTURE.md`
- `lib/`
- `android/app/src/main/`
- `termux-app/terminal-emulator/`
- `termux-app/terminal-view/`
- `termux-app/app/src/main/java/com/termux/app/`
- `termux-app/termux-shared/`

**Output Artifacts:**

- Architecture decision records in `ARCHITECTURE.md`
- Phase updates in `ROADMAP.md`
- Handoff notes for implementation agents

**Failure Modes:**

- Allows platform logic to leak into Flutter UI.
- Omits upstream Termux service lifecycle constraints.
- Treats package manager support as a PATH-only problem.

## PTYBridgeAgent

**Role:** Owns Android PTY creation, fork/exec, fd cleanup, resize, signal, and byte-stream transport.

**Phase 1 completion note:** Implemented Termux-aligned PTY startup in `android/app/src/main/cpp/pty_bridge.c`, byte-safe Java/Flutter transport in `PtyProcess.java`, `MainActivity.java`, and `lib/platform/shell_bridge.dart`, and removed normal interactive pipe fallback from `ShellEngine.java`. Root cause was partial PTY parity plus string-coerced output and hidden fallback. Source reference: `termux-app/terminal-emulator/src/main/jni/termux.c` and `TerminalSession.java`. Validation command: `cd android && gradlew.bat :app:connectedAndroidTest`.

**Responsibilities:**

- Compare `android/app/src/main/cpp/pty_bridge.c` against `termux-app/terminal-emulator/src/main/jni/termux.c`.
- Preserve `/dev/ptmx`, `grantpt`, `unlockpt`, `TIOCSCTTY`, `TIOCSWINSZ`, `IUTF8`, and flow-control behavior.
- Ensure PTY output is transported as bytes or safely decoded without splitting UTF-8 sequences.
- Remove pipe fallback from production terminal sessions unless explicitly marked degraded.

**Input Sources:**

- `android/app/src/main/cpp/pty_bridge.c`
- `android/app/src/main/java/com/termux/flutter/PtyProcess.java`
- `termux-app/terminal-emulator/src/main/jni/termux.c`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalSession.java`

**Output Artifacts:**

- Native PTY bridge implementation
- Java/Kotlin PTY manager
- PTY instrumentation tests

**Failure Modes:**

- Shell starts without a controlling terminal.
- Ctrl+S freezes output because `IXON` remains enabled.
- Window resize does not propagate to interactive apps.

## BootstrapAgent

**Role:** Owns Termux-compatible bootstrap extraction, `$PREFIX`, `$HOME`, env, package manager availability, and bootstrap asset packaging.

**Responsibilities:**

- Port `TermuxInstaller` staging, `SYMLINKS.txt`, chmod, and atomic move semantics.
- Define ABI-specific bootstrap asset layout for `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64`.
- Ensure `bash`, `pkg`, `apt`, `dpkg`, repo config, and shared libraries exist under `$PREFIX`.
- Keep paths rooted in `context.filesDir` for scoped storage compatibility.

**Input Sources:**

- `android/app/src/main/java/com/termux/flutter/BootstrapInstaller.java`
- `android/app/src/main/assets/bootstrap/README.md`
- `termux-app/app/src/main/java/com/termux/app/TermuxInstaller.java`
- `termux-app/app/src/main/cpp/termux-bootstrap.c`
- `termux-app/termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java`

**Output Artifacts:**

- Bootstrap installer
- Bootstrap artifact manifest
- First-run validation tests

**Failure Modes:**

- Symlinks are extracted as regular files or lost.
- `$PREFIX/bin/bash` exists but dynamic libraries cannot load.
- `pkg update` starts but repository metadata targets an unsupported Android API.

## SessionLifecycleAgent

**Role:** Owns persistent terminal sessions, foreground service binding, notifications, process exit, and Activity reconnection.

**Responsibilities:**

- Design `TerminalForegroundService` equivalent to upstream `TermuxService`.
- Implement session registry, current-session persistence, session close semantics, and process exit reporting.
- Keep shell processes alive when Flutter Activity backgrounds or recreates.
- Expose service state through a stable Flutter channel API.

**Input Sources:**

- `android/app/src/main/java/com/termux/flutter/ShellEngine.java`
- `termux-app/app/src/main/java/com/termux/app/TermuxService.java`
- `termux-app/app/src/main/java/com/termux/app/terminal/TermuxTerminalSessionServiceClient.java`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalSession.java`

**Output Artifacts:**

- Android foreground service
- Session channel protocol
- Notification lifecycle implementation

**Failure Modes:**

- Backgrounding kills active package installation.
- UI reconnect creates duplicate shells.
- Notification actions point to stale session handles.

## VTEmulatorAgent

**Role:** Owns VT100/xterm emulation and screen model parity.

**Phase 2 completion note:** Evaluated `xterm 4.0.0` and selected a Termux-inspired pure Dart emulator because Phase 2 requires project-owned renderer-neutral cells and callbacks. Implemented `lib/core/terminal/terminal_emulator.dart`, `screen_model.dart`, `screen_cell.dart`, `text_attributes.dart`, `color_attribute.dart`, `wc_width.dart`, `terminal_keys.dart`, `alternate_screen.dart`, and the bridge adapter in `lib/terminal/terminal_emulator_adapter.dart`. Root cause was the old `AnsiParser` handling only a small CSI/SGR subset while storing Flutter rendering state. Source reference: `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalEmulator.java`, `TerminalBuffer.java`, `WcWidth.java`, and upstream terminal-emulator tests. Validation command: `flutter test test/terminal/ --reporter=expanded`.

**Responsibilities:**

- Replace or extend `AnsiParser` with a real emulator.
- Use upstream tests to cover CSI, OSC, DCS, APC, alternate screen, scroll regions, title, colors, Unicode, and mouse modes.
- Evaluate `xterm` package versus Dart port of `TerminalEmulator.java`.
- Preserve terminal byte semantics independent of Flutter rendering.

**Input Sources:**

- `lib/terminal/ansi_parser.dart`
- `lib/terminal/terminal_buffer.dart`
- `lib/core/terminal/`
- `test/terminal/`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalEmulator.java`
- `termux-app/terminal-emulator/src/test/java/com/termux/terminal/`

**Output Artifacts:**

- Dart emulator module or package integration
- Emulator test suite
- Compatibility matrix

**Failure Modes:**

- `vim`, `nano`, `top`, or `less` render incorrectly.
- Alternate screen contents corrupt scrollback.
- Unicode width mismatches cursor position.

## UIRenderAgent

**Role:** Owns Flutter terminal rendering, selection, scrollback, cursor, gestures, and viewport performance.

**Phase 3 completion note:** Implemented the emulator-driven Flutter renderer in `lib/terminal/terminal_widget.dart` with `lib/ui/terminal_view.dart` as the Phase 3 export path, plus `lib/core/terminal_style.dart`, `lib/core/glyph_width.dart`, renderer tests, and `benchmark_test/terminal_render_bench.dart`. Root cause was the old painter flattening emulator state into fixed-metric line cells, losing transcript-aware row math, run-level attributes, cursor mode, and selection coordinates. Source reference: `termux-app/terminal-view/src/main/java/com/termux/view/TerminalRenderer.java`, `TerminalView.java`, and terminal-emulator `TerminalBuffer.java`/`TerminalRow.java`. Validation command: `flutter test test/glyph_width_test.dart test/terminal_style_test.dart`.

**Responsibilities:**

- Replace naive `CustomPainter` row painting with a terminal renderer aligned to emulator state.
- Support color palettes, bold/italic/inverse/underline, cursor styles, selection handles, and scrollbars.
- Implement touch scroll, pinch font scaling, long-press selection, and paste menu.
- Maintain frame stability under high output throughput.

**Input Sources:**

- `lib/terminal/terminal_widget.dart`
- `termux-app/terminal-view/src/main/java/com/termux/view/TerminalView.java`
- `termux-app/terminal-view/src/main/java/com/termux/view/TerminalRenderer.java`
- `termux-app/terminal-view/src/main/java/com/termux/view/textselection/`

**Output Artifacts:**

- Flutter terminal renderer
- Selection and gesture controllers
- Rendering benchmarks

**Failure Modes:**

- Text overlaps, flickers, or mismeasures wide glyphs.
- Scrollback jumps when output arrives.
- Selection copies wrong cells.

## KeyboardAgent

**Role:** Owns IME, extra keys row, hardware keyboard, shortcuts, modifiers, paste, and terminal key encoding.

**Responsibilities:**

- Port `KeyHandler` behavior for arrow, function, Home/End, Page, Ctrl, Alt, Shift, and keypad modes.
- Implement Termux-style extra key row and configurable layout.
- Handle Android soft keyboard quirks through a terminal-specific input model.
- Ensure Ctrl+C, Ctrl+D, Ctrl+Z, Tab, Esc, and bracketed paste work.

**Input Sources:**

- `lib/terminal/terminal_widget.dart`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/KeyHandler.java`
- `termux-app/app/src/main/java/com/termux/app/terminal/io/TermuxTerminalExtraKeys.java`
- `termux-app/termux-shared/src/main/java/com/termux/shared/termux/extrakeys/`

**Output Artifacts:**

- Flutter keyboard manager
- Extra keys row widget
- Key mapping tests

**Failure Modes:**

- Soft keyboard cannot send Enter or Backspace reliably.
- Ctrl-modified keys send printable text instead of control bytes.
- Application cursor mode is ignored.

## StorageAgent

**Role:** Owns `$HOME`, `$PREFIX`, shared storage setup, file sharing, document provider parity, and scoped storage compatibility.

**Responsibilities:**

- Implement `termux-setup-storage` equivalent symlink creation inside app-private home.
- Design scoped storage behavior for Android 11+ while preserving Termux CLI expectations.
- Map file receive/share/open flows to Android intents and content URIs.
- Keep direct Linux paths separate from user-visible storage paths.

**Input Sources:**

- `termux-app/app/src/main/java/com/termux/app/TermuxInstaller.java`
- `termux-app/app/src/main/java/com/termux/filepicker/TermuxDocumentsProvider.java`
- `termux-app/app/src/main/java/com/termux/app/api/file/FileReceiverActivity.java`
- `termux-app/termux-shared/src/main/java/com/termux/shared/file/`

**Output Artifacts:**

- Storage setup service
- File provider and receiver integration
- Storage permission documentation

**Failure Modes:**

- Android scoped storage blocks CLI access.
- Symlink setup points to inaccessible locations.
- Shared files leak outside intended permissions.

## PluginBridgeAgent

**Role:** Owns Termux plugin ecosystem compatibility: RUN_COMMAND, Termux:API, Widget, Tasker, Float, Boot, X11, and CLI bridge helpers.

**Responsibilities:**

- Implement `RUN_COMMAND`-compatible Android service semantics.
- Define Flutter-facing plugin bridge APIs for command execution and results.
- Map plugin package constants and permissions from `TermuxConstants`.
- Document which plugin behaviors require separate companion apps.

**Input Sources:**

- `termux-app/app/src/main/java/com/termux/app/RunCommandService.java`
- `termux-app/termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java`
- `termux-app/termux-shared/src/main/java/com/termux/shared/termux/plugins/`
- `termux-app/app/src/main/res/xml/*preferences.xml`

**Output Artifacts:**

- Plugin bridge service
- Intent contract tests
- CLI helper package requirements

**Failure Modes:**

- Plugins cannot find the app due to package or signature mismatch.
- PendingIntent results are dropped.
- Background commands are killed by Activity lifecycle.

## ThemeAgent

**Role:** Owns visual styling, font loading, color schemes, and Termux:Styling parity.

**Responsibilities:**

- Implement font and color config loading from app-private files.
- Support Nerd Fonts, fallback fonts, and glyph width validation.
- Map Termux color scheme semantics to Flutter renderer palettes.
- Coordinate with `UIRenderAgent` for cursor style and text attributes.

**Input Sources:**

- `lib/terminal/terminal_widget.dart`
- `termux-app/app/src/main/java/com/termux/app/terminal/TermuxTerminalSessionActivityClient.java`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TerminalColors.java`
- `termux-app/terminal-emulator/src/main/java/com/termux/terminal/TextStyle.java`

**Output Artifacts:**

- Theme manager
- Font asset loader
- Styling settings documentation

**Failure Modes:**

- Box drawing and Nerd Font glyphs render as missing boxes.
- Bright colors or inverse mode differ from xterm.
- Font scaling breaks row/column geometry.

## TestingAgent

**Role:** Owns unit, integration, golden, and device tests proving parity.

**Responsibilities:**

- Port upstream terminal-emulator tests into Dart or run them against the selected emulator.
- Add Android instrumentation tests for PTY, bootstrap, service lifecycle, and plugin intents.
- Define smoke commands: `echo`, `stty`, `pkg update`, `apt install`, `vim`, `top`, `ssh`.
- Maintain device matrix including Android 5.1 experimental, API 23+, and modern Android.

**Input Sources:**

- `test/`
- `termux-app/terminal-emulator/src/test/java/com/termux/terminal/`
- `termux-app/app/src/test/java/`
- `android/app/src/main/`

**Output Artifacts:**

- Test plan
- Automated test suites
- CI acceptance gates

**Failure Modes:**

- Tests validate only build success, not interactive behavior.
- Package manager tests mutate shared mirrors unpredictably.
- Old Android compatibility hides behind skipped checks.

## SecurityAgent

**Role:** Owns Android permissions, process isolation, bootstrap integrity, plugin permissions, and data safety.

**Responsibilities:**

- Audit requested permissions against upstream manifest and Flutter needs.
- Validate bootstrap archive integrity before extraction.
- Prevent path traversal and unsafe symlink extraction.
- Review plugin command execution and file provider exposure.

**Input Sources:**

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/termux/flutter/BootstrapInstaller.java`
- `termux-app/app/src/main/AndroidManifest.xml`
- `termux-app/termux-shared/src/main/java/com/termux/shared/android/PermissionUtils.java`
- `termux-app/termux-shared/src/main/java/com/termux/shared/file/`

**Output Artifacts:**

- Security review notes
- Permission matrix
- Bootstrap verification implementation

**Failure Modes:**

- Bootstrap archive escapes app files directory.
- RUN_COMMAND-style service is exported without correct permission.
- Shared storage grants expose private files.

## DocumentationAgent

**Role:** Owns governance docs, user-facing docs, migration notes, and release criteria.

**Responsibilities:**

- Keep `README.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DESC_ROADMAP.md`, and `AGENTS.md` synchronized.
- Record feature parity status with file-level evidence.
- Convert engineering decisions into actionable agent tasks.
- Remove stale claims after implementation changes.

**Input Sources:**

- All project docs
- All files listed in `ARCHITECTURE.md`
- Roadmap phase outputs

**Output Artifacts:**

- Updated Markdown docs
- Release notes
- Contributor onboarding material

**Failure Modes:**

- Documentation claims `pkg` works without a bootstrap artifact.
- Roadmap phases diverge from agent responsibilities.
- File references drift after refactors.
