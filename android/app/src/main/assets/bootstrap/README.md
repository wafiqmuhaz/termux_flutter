Place Termux-compatible bootstrap archives here, named by Android ABI:

- armeabi-v7a.zip
- arm64-v8a.zip
- x86.zip
- x86_64.zip

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
