# Run scripts

Convenience launchers for the multiplatform ksat demo (`demo/`). Each runs the same demo —
enumerate all models of XOR(x1,x2), then UNSAT — on a different target.

Prerequisite: `ksat-extra` must be checked out inside the `sat-solvers-kotlin` main repo
(the demo builds against `../ksat`). See the repo README's "Extras" section.

| Script | Target | Notes |
|--------|--------|-------|
| `runJVM.sh` | JVM console | works anywhere with a JDK |
| `runMacOS.sh` | native macOS console | macOS only; auto-picks arm64/x86_64 |
| `runLinux.sh` | native Linux console | Linux only (incl. Windows WSL); x86_64 |
| `runWeb.sh` | browser (Kotlin/JS) | blocking dev server; Ctrl-C to stop |
| `runAndroidEmulator.sh` | Android emulator | auto-picks the running `emulator-XXXX` |
| `runAndroidDevice.sh` | attached Android device | auto-picks the connected non-emulator device |

Native targets only build on a matching host (Kotlin/Native can't cross-compile here): macOS
for `runMacOS.sh`, Linux/WSL for `runLinux.sh`. Run one on the wrong OS and it exits with a
clear message instead of doing nothing. JVM, Web and Android work on any host.

The two Android scripts take an optional adb serial if more than one emulator/device is present.
This is bonus material — not every script has to work on every machine.
