# termux_flutter Roadmap

### PHASE 0 — Project Foundation & Repository Setup

**Goal:** Establish a reproducible Flutter/Android/NDK workspace and source-of-truth migration baseline.

- [ ] P1 — Pin Flutter, Dart, Android Gradle Plugin, Gradle, JDK, CMake, and NDK versions in project docs.
- [ ] P2 — Keep `termux-app/` upstream source available as read-only reference under the workspace or as a documented submodule.
- [ ] P3 — Add a source inventory script that excludes `build/`, `.dart_tool/`, and Gradle caches.
- [ ] P4 — Define package identity policy for `com.termux.flutter` versus upstream `com.termux`.
- [ ] P5 — Document supported Android API levels, including the API 21 experimental path and Flutter SDK risk.
- [ ] P6 — Add a clean build command matrix for debug, release, `android-arm`, `android-arm64`, `x86`, and `x86_64`.
- [ ] P7 — Establish migration acceptance gates tied to upstream Termux features.

**Success Criteria:** A new engineer can clone the workspace, identify upstream references, run the documented build commands, and understand package/API constraints without reading chat history.

### PHASE 1 — PTY & Native Terminal Core

**Goal:** Provide a Termux-grade native PTY subprocess layer that never falls back to `/system/bin/sh`.

- [x] P1 — Compare `pty_bridge.c` line-by-line with upstream `termux.c`.
- [x] P2 — Add `/dev/ptmx` open, `grantpt`, `unlockpt`, `TIOCSCTTY`, and fd cleanup parity.
- [x] P3 — Configure termios with UTF-8 mode and disabled software flow control.
- [x] P4 — Preserve binary-safe PTY reads and writes across the Android/Flutter boundary.
- [x] P5 — Propagate row, column, cell width, and cell height on resize.
- [x] P6 — Implement signal delivery for interrupt, terminate, hangup, and kill.
- [x] P7 — Remove pipe fallback from normal interactive sessions or mark it diagnostic-only.
- [x] P8 — Add instrumentation tests for shell startup, resize, Ctrl+C, EOF, and process exit status.

**Success Criteria:** An interactive shell starts under PTY control, receives terminal signals, resizes correctly, and never starts Android `/system/bin/sh` as a hidden fallback.

**Implementation note:** Phase 1 is implemented in `pty_bridge.c`, `PtyProcess.java`, `ShellEngine.java`, `MainActivity.java`, and `shell_bridge.dart`; see `PTY_GAP_ANALYSIS.md`. Device validation command: `cd android && gradlew.bat :app:connectedAndroidTest`.

### PHASE 2 — VT100/xterm Terminal Emulator (Dart layer)

**Goal:** Replace the minimal ANSI parser with a tested VT100/xterm emulator compatible with Termux workloads.

- [ ] P1 — Evaluate `xterm` Flutter package against upstream `TerminalEmulator` tests.
- [ ] P2 — Decide between adopting `xterm` or porting `TerminalEmulator.java` behavior to Dart.
- [ ] P3 — Support CSI, OSC, DCS, APC, ESC charset selection, SGR, scroll regions, and alternate screen.
- [ ] P4 — Support xterm title changes, clipboard sequences policy, bell, cursor styles, and bracketed paste.
- [ ] P5 — Support 8/16/256 color and truecolor attributes.
- [ ] P6 — Support Unicode width and combining characters using a `WcWidth` equivalent.
- [ ] P7 — Port upstream emulator tests into Dart.
- [ ] P8 — Expose emulator state through a renderer-neutral screen model.

**Success Criteria:** The selected Dart emulator passes a migrated upstream terminal-emulator test suite and renders `vim`, `nano`, `less`, `top`, and shell prompts without sequence corruption.

### PHASE 3 — Terminal View & Rendering Engine

**Goal:** Build a Flutter terminal view that matches Termux rendering, selection, scrolling, gestures, and performance.

- [ ] P1 — Replace line-list `CustomPainter` assumptions with emulator screen rows and transcript rows.
- [ ] P2 — Implement xterm text attributes: bold, faint, italic, underline, inverse, strike, foreground, and background.
- [ ] P3 — Implement cursor shape, blink, visibility, and alternate cursor state.
- [ ] P4 — Implement scrollback viewport, fling, scrollbar, and scroll-to-bottom behavior.
- [ ] P5 — Implement long-press text selection, drag handles, copy, paste, and word selection.
- [ ] P6 — Implement pinch font scaling and persistent font size settings.
- [ ] P7 — Validate glyph metrics for ASCII, CJK, emoji, and box drawing.
- [ ] P8 — Add rendering performance benchmarks under high output throughput.

**Success Criteria:** The Flutter terminal view can render upstream emulator state at interactive frame rates with correct selection, cursor, scrollback, and glyph alignment.

### PHASE 4 — Bootstrap Filesystem & Package Manager Bridge

**Goal:** Install a valid Termux-compatible `$PREFIX` and `$HOME` so `pkg`, `apt`, and `dpkg` work in the app sandbox.

- [ ] P1 — Define bootstrap artifact format per ABI and Android API family.
- [ ] P2 — Port `TermuxInstaller` staging extraction behavior, including `SYMLINKS.txt`.
- [ ] P3 — Validate bootstrap archive integrity before extraction.
- [ ] P4 — Extract to staging prefix, chmod executables, create symlinks, then atomically move to `$PREFIX`.
- [ ] P5 — Generate shell environment with `PREFIX`, `HOME`, `TMPDIR`, `SHELL`, `PATH`, `LD_LIBRARY_PATH`, `LANG`, and Android variables.
- [ ] P6 — Add package repository configuration compatible with the bootstrap API level.
- [ ] P7 — Add first-run progress and failure recovery UI.
- [ ] P8 — Validate `bash --login`, `pkg update`, `apt update`, `apt install`, and `dpkg -l`.

**Success Criteria:** A clean install extracts bootstrap into app-private storage and successfully runs `pkg update` and `apt install` without relying on `/system/bin/sh`.

### PHASE 5 — Shell Session Management & Lifecycle

**Goal:** Move shell processes from Activity ownership into a foreground Android service with multi-session support.

- [ ] P1 — Create `TerminalForegroundService` modeled after upstream `TermuxService`.
- [ ] P2 — Define session handles, current-session state, and session list APIs.
- [ ] P3 — Bind Flutter Activity to the service and reconnect after configuration changes.
- [ ] P4 — Add persistent notification with session count and stop action.
- [ ] P5 — Preserve running shells while Flutter UI is backgrounded.
- [ ] P6 — Implement session create, rename, switch, close, and force-finish.
- [ ] P7 — Report process exit status and terminal title changes to Flutter.
- [ ] P8 — Add tests for Activity destroy/recreate and background package installation.

**Success Criteria:** Multiple shell sessions survive Activity recreation and backgrounding, remain visible in notification state, and reconnect to Flutter without duplicate subprocesses.

### PHASE 6 — Keyboard System (Extra Keys Row + Hardware Keyboard)

**Goal:** Match Termux keyboard behavior for IME input, hardware keys, modifiers, shortcuts, and extra keys.

- [ ] P1 — Port key sequence mapping from upstream `KeyHandler.java`.
- [ ] P2 — Implement configurable extra key row from Termux extra-keys metadata.
- [ ] P3 — Support Ctrl, Alt, Shift, Esc, Tab, arrows, function keys, Home, End, PageUp, and PageDown.
- [ ] P4 — Support application cursor and keypad modes from emulator state.
- [ ] P5 — Implement paste and bracketed paste behavior.
- [ ] P6 — Handle Android soft keyboard composition and Samsung-style delete quirks.
- [ ] P7 — Add hardware keyboard shortcut support for sessions, paste, copy, font size, and drawer actions.
- [ ] P8 — Add key mapping tests for common shell and editor workflows.

**Success Criteria:** Ctrl+C, Ctrl+D, Ctrl+Z, Tab completion, arrows, function keys, and editor shortcuts work from both soft and hardware keyboards.

### PHASE 7 — Theming, Fonts & Visual Polish

**Goal:** Provide Termux-like styling, font, color, and display customization.

- [ ] P1 — Implement color scheme loading compatible with Termux `colors.properties`.
- [ ] P2 — Implement font loading from app-private configuration paths.
- [ ] P3 — Support Nerd Fonts and fallback glyph handling.
- [ ] P4 — Add settings for font size, cursor style, cursor blink, bell behavior, and terminal margins.
- [ ] P5 — Integrate light/dark theme surfaces without breaking terminal palette.
- [ ] P6 — Add visual regression tests for ANSI color and box drawing.
- [ ] P7 — Define Termux:Styling compatibility boundaries.

**Success Criteria:** Users can customize fonts and colors with Termux-compatible files, and terminal rendering remains aligned for box drawing, CJK, emoji, and powerline glyphs.

### PHASE 8 — Termux:API Plugin Bridge

**Goal:** Expose a compatible bridge for Termux:API-style device integrations and CLI commands.

- [ ] P1 — Map Termux:API command expectations and package identity constraints.
- [ ] P2 — Define Flutter-side plugin bridge interfaces for command execution and result streaming.
- [ ] P3 — Implement Android intent dispatch to companion API apps where applicable.
- [ ] P4 — Add CLI helpers under `$PREFIX/bin` for clipboard, share, open, and URL open commands.
- [ ] P5 — Add permission request flow for API features such as camera, location, contacts, SMS, and clipboard.
- [ ] P6 — Implement error reporting compatible with shell command exit codes.
- [ ] P7 — Add integration tests with installed and missing companion API apps.

**Success Criteria:** Core Termux:API-style commands either execute through a documented bridge or fail with clear shell-visible errors and correct exit codes.

### PHASE 9 — Termux Plugin Ecosystem (Widget, Float, Boot, Tasker, X11)

**Goal:** Define and implement compatibility surfaces for the broader Termux plugin ecosystem.

- [ ] P1 — Implement RUN_COMMAND-compatible service contract.
- [ ] P2 — Define package/signature strategy for Termux plugin discovery.
- [ ] P3 — Implement Termux:Widget command launch semantics.
- [ ] P4 — Implement Termux:Tasker command execution and result handling semantics.
- [ ] P5 — Define Termux:Boot startup command behavior through Android boot receiver policy.
- [ ] P6 — Define Termux:Float window strategy using either Flutter overlay or native Android service.
- [ ] P7 — Document Termux:X11 expectations and native graphics boundaries.
- [ ] P8 — Add plugin intent contract tests.

**Success Criteria:** Plugin-facing intents and service contracts are documented and tested, and each plugin family has an implemented or explicitly scoped compatibility path.

### PHASE 10 — Full Feature Parity Validation & QA

**Goal:** Prove the Flutter migration against upstream Termux behavior with automated and manual parity validation.

- [ ] P1 — Build a feature parity matrix tied to upstream source modules.
- [ ] P2 — Run emulator, PTY, bootstrap, lifecycle, keyboard, and plugin test suites in CI.
- [ ] P3 — Test package workflows: `pkg update`, `apt install`, `dpkg -l`, `python`, `node`, `openssh`, and `git`.
- [ ] P4 — Test interactive apps: `vim`, `nano`, `less`, `top`, `htop`, `tmux`, and `ssh`.
- [ ] P5 — Test Android API levels and ABIs defined in Phase 0.
- [ ] P6 — Test session survival under rotate, background, low memory, and notification actions.
- [ ] P7 — Test storage, sharing, URL open, clipboard, wake lock, and plugin flows.
- [ ] P8 — Publish release criteria and known incompatibilities.

**Success Criteria:** The project passes the parity matrix on the supported device matrix, with every non-parity item documented as a deliberate compatibility decision.
