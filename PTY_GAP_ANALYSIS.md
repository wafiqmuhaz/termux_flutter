# PTY Gap Analysis

Phase 1 compared `android/app/src/main/cpp/pty_bridge.c` with upstream `termux-app/terminal-emulator/src/main/jni/termux.c` and the byte-queue lifecycle in `TerminalSession.java`.

## Summary

The previous bridge opened a PTY and forked a child, but it was not Termux-grade because PTY bytes were coerced into Java/Dart strings, termios did not enable UTF-8/no-flow-control raw mode, resize ignored pixel dimensions, signals only used `SIGTERM`, and `ShellEngine` silently started the pipe implementation after native startup failure.

## Line-Item Gaps And Fixes

| Area | Previous local behavior | Upstream reference | Root cause | Phase 1 fix |
| --- | --- | --- | --- | --- |
| PTY open | Used `posix_openpt(O_RDWR | O_NOCTTY)` with limited logging. | `termux.c` opens `/dev/ptmx` with `O_RDWR | O_CLOEXEC`. | Startup was harder to audit and did not match upstream fd close semantics. | `pty_bridge.c` now opens `/dev/ptmx` directly with `O_CLOEXEC` and logs `open`, `grantpt`, `unlockpt`, and `ptsname_r`. |
| Grant/unlock/slave | Did `grantpt`, `unlockpt`, `ptsname`; child opened slave. | Same lifecycle plus fd cleanup. | Broad shape existed, but no per-syscall trace and parent fallback masked failures. | Failures now throw `IOException`; normal interactive startup has no pipe fallback. |
| Controlling terminal | Child called `setsid()` and `TIOCSCTTY` without checking. | Upstream calls `setsid()` before opening/duping slave. | Failures could continue into a broken subprocess. | Child logs and exits on failed `setsid`, slave open, or `TIOCSCTTY`. |
| Termios | No UTF-8/no-flow-control/raw setup. | Upstream sets `IUTF8` and clears `IXON | IXOFF`. | Ctrl+S could freeze output and raw terminal behavior was incomplete. | Added `configure_termios()` using `cfmakeraw`, `IUTF8`, and no `IXON | IXOFF | IXANY`. |
| Window size | Set rows/cols only; resize also rows/cols only. | Upstream uses rows, columns, cell width, and cell height. | Full-screen apps could see incomplete geometry. | Startup and resize now call `TIOCSWINSZ` with `ws_xpixel = cols * cellWidth` and `ws_ypixel = rows * cellHeight`. |
| Signal delivery | `close()` called native `SIGTERM` only. | Upstream exposes lifecycle and `finishIfRunning()` kills the shell. | Ctrl+C/SIGHUP/SIGKILL were not method-channel operations. | Added `sendSignal` channel and `nativeSendSignal(pid, signal)` with process-group delivery and PID fallback. |
| PTY output | `PtyProcess` decoded each read chunk as UTF-8 `String`. | `TerminalSession` queues raw bytes and emulator appends bytes. | Split or invalid UTF-8 corrupted terminal data. | `PtyProcess` emits `byte[]`; `EventChannel` sends byte chunks; Dart decodes incrementally only for the current parser. |
| PTY input | Java accepted text and encoded UTF-8. | Upstream writes bytes. | Current Flutter UI still emits text only; full byte input belongs to later keyboard/emulator work. | Kept text input encoding scoped to current UI, while native write path remains `byte[]`. |
| Pipe fallback | `ShellEngine` caught PTY failure and launched `PipeShellProcess`. | Termux does not treat pipes as interactive terminals. | Hidden fallback faked terminal success. | Removed pipe fallback from `ShellEngine`; PTY failure is fatal for interactive startup. |
| Exit status | Waiter returned shell status after reader ended. | Upstream waits and reports exit status. | Existing behavior was mostly present. | Kept wait reporting and added instrumentation coverage. |

## Validation Commands

- Build: `cd android && gradlew.bat :app:assembleDebug`
- Instrumentation: `cd android && gradlew.bat :app:connectedAndroidTest`
- Native log trace: `adb logcat -s PTY_BRIDGE:*`

Local validation note: Gradle could not run in this shell because `JAVA_HOME` is unset and `java.exe` is not on `PATH`.
