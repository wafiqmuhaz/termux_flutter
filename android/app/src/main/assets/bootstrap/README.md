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
