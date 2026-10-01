# Run scripts

Convenience launchers for the multiplatform ksat demo (`demo/`). Each runs the same demo —
enumerate all models of XOR(x1,x2), then UNSAT — on a different target.

Prerequisite: `ksat-extra` must be checked out inside the `sat-solvers-kotlin` main repo
(the demo builds against `../ksat`). See the repo README's "Extras" section.

| Script | Target | Notes |
|--------|--------|-------|
| `runJVM.sh` | JVM console | works anywhere with a JDK |
| `runMacOS.sh` | native macOS console | Apple Silicon; edit for Intel (MacosX64) |
| `runLinux.sh` | native Linux console | x86_64 |
| `runWeb.sh` | browser (Kotlin/JS) | opens a dev server |
| `runAndroidEmulator.sh` | Android emulator | auto-picks the running `emulator-XXXX` |
| `runAndroidDevice.sh` | attached Android device | auto-picks the connected non-emulator device |

The two Android scripts take an optional adb serial if more than one emulator/device is present.
This is bonus material — not every script has to work on every machine.
