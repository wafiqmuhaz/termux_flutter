Place Termux-compatible bootstrap archives here, named by Android ABI and Android API family:

For Android 7/API 24 and newer:

- android-7/armeabi-v7a.zip
- android-7/arm64-v8a.zip
- android-7/x86.zip
- android-7/x86_64.zip

For Android 5 or 6/API 21-23:

- android-5/armeabi-v7a.zip
- android-5/arm64-v8a.zip
- android-5/x86.zip
- android-5/x86_64.zip

The installer also accepts legacy top-level `arm64-v8a.zip` style names, but those are treated as `android-7`
assets. Do not use an `apt.android-7` bootstrap on Android 5 or 6: old Android linkers will fail with
`CANNOT LINK EXECUTABLE: empty/missing DT_HASH ... built with --hash-style=gnu?`.

Each archive must extract into the app files directory and provide at least:

- usr/bin/bash
- usr/bin/pkg
- usr/bin/apt
- usr/lib and other runtime/package-manager dependencies

Without a matching archive, the app refuses to fall back to /system/bin/sh.

Official Termux bootstrap archives contain native binaries and package metadata built for the absolute prefix
`/data/data/com.termux/files/usr`. The Android `applicationId` must therefore remain `com.termux` unless the
bootstrap is rebuilt with a different prefix.

The official upstream Termux bootstrap archives are prefix-relative and named:

- bootstrap-aarch64.zip -> arm64-v8a.zip
- bootstrap-arm.zip -> armeabi-v7a.zip
- bootstrap-i686.zip -> x86.zip
- bootstrap-x86_64.zip -> x86_64.zip

Current bundled arm64-v8a asset:

- Source: https://github.com/termux/termux-packages/releases/download/bootstrap-2026.02.12-r1%2Bapt.android-7/bootstrap-aarch64.zip
- SHA-256: ea2aeba8819e517db711f8c32369e89e7c52cee73e07930ff91185e1ab93f4f3
- Compatibility: Android 7/API 24 and newer only. Android 5/6 devices need an `android-5` bootstrap built with
  binaries compatible with the old linker.
