# termux_flutter

![Flutter](https://img.shields.io/badge/Flutter-Android-blue)
![Status](https://img.shields.io/badge/status-migration%20planning-orange)
![Termux parity](https://img.shields.io/badge/Termux%20parity-not%20complete-red)

`termux_flutter` is a Flutter and Android experiment aimed at becoming a Termux-like terminal application. The current project already contains a Flutter terminal surface, Android channel bindings, native PTY-related code, and a bundled upstream `termux-app/` reference tree, but it is not yet feature-equivalent to Termux. In particular, a real Termux bootstrap filesystem is not currently installed, so commands such as `pkg`, `apt`, and `dpkg` should be treated as roadmap goals rather than working guarantees.

## Current Status

| Area | Current project state | Target state |
| --- | --- | --- |
| Android embedding | Modern Flutter Android embedding is present | Keep current embedding and remove legacy assumptions |
| Terminal UI | Flutter `CustomPainter` terminal surface with limited ANSI behavior | Full Termux-grade terminal view with scrollback, selection, gestures, and IME parity |
| PTY process | Phase 1 native PTY bridge implemented; device validation still required | Native PTY subprocess behavior matching upstream Termux `termux.c` |
| Shell | May fall back to Android shell if bootstrap shell is missing | Launch app-private `$PREFIX/bin/bash` or equivalent shell |
| Bootstrap | Installer scaffold expects ABI bootstrap archives | Verified Termux-compatible bootstrap extraction with symlinks, chmod, and atomic install |
| Package manager | Not guaranteed; no valid bundled package rootfs confirmed | `pkg update`, `apt update`, and `apt install` work inside app sandbox |
| VT emulator | Minimal ANSI parser | VT100/xterm compatible emulator or vetted `xterm` package integration |
| Lifecycle | Activity-oriented shell ownership | Foreground service with persistent multi-session support |
| Plugins | Not implemented | Termux:API and plugin ecosystem compatibility bridge |

## Documentation Map

- [ARCHITECTURE.md](ARCHITECTURE.md) explains the current system, upstream Termux reference architecture, data flow, gaps, and target design.
- [ROADMAP.md](ROADMAP.md) lists the implementation phases and acceptance criteria.
- [DESC_ROADMAP.md](DESC_ROADMAP.md) expands each roadmap phase with rationale, implementation notes, risks, and dependencies.
- [AGENTS.md](AGENTS.md) defines the specialist agent responsibilities for coordinated development.

## Prerequisites

- Flutter stable SDK compatible with this project.
- Android Studio or Android SDK command-line tools.
- JDK compatible with the Android Gradle Plugin used by the project.
- Android NDK and CMake for native PTY work.
- An Android device or emulator. Android 5.1/API 22 and older ABI targets require extra validation because modern Flutter and Android tooling may drop or reduce support over time.

## Build And Run

From the project root:

```powershell
flutter pub get
flutter doctor
flutter build apk --debug
flutter install
flutter run
```

For a release APK:

```powershell
flutter pub get
flutter build apk --release
```

For ABI-specific debugging:

```powershell
flutter run --target-platform android-arm
flutter run --target-platform android-arm64
flutter build apk --debug --target-platform android-arm
flutter build apk --release --target-platform android-arm64
```

For Phase 1 PTY validation:

```powershell
cd android
.\gradlew.bat :app:assembleDebug
.\gradlew.bat :app:connectedAndroidTest
adb logcat -s PTY_BRIDGE:*
```

## Important Runtime Notes

If the terminal reports errors like `pkg: not found`, the app is not running inside a Termux-compatible userspace. That is expected until the bootstrap filesystem phase is implemented. The app should not silently start `/system/bin/sh` as an interactive fallback; missing bootstrap assets now surface as an explicit failure. The correct target behavior is to install an app-private `$PREFIX`, set `HOME`, `PATH`, `SHELL`, `TMPDIR`, and related environment variables, and start a real shell from that prefix through the native PTY layer.

The bundled `termux-app/` directory is a reference source for parity work. It should be treated as upstream guidance for PTY startup, bootstrap installation, terminal emulation, terminal rendering, lifecycle, storage, plugins, and testing.

## Contributing

Work should follow the phase order in [ROADMAP.md](ROADMAP.md). Keep source changes focused, compare behavior against the upstream `termux-app/` modules before replacing core terminal behavior, and add validation for every Android API level and ABI touched by a change.

Recommended first contributions:

- Harden the native PTY startup path so interactive sessions never silently fall back to `/system/bin/sh`.
- Port or adopt a real VT100/xterm emulator.
- Implement bootstrap extraction with `SYMLINKS.txt` support and verified `$PREFIX` environment setup.
- Move session ownership into a foreground service.

## License

This repository contains project-specific Flutter/Android code and a local upstream Termux reference tree. Check the license files in this repository and in `termux-app/` before redistributing binaries or copying upstream code.
