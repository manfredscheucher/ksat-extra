# ksat multiplatform demo

One tiny SAT demo, compiled to **every** Kotlin Multiplatform target, to show that the
`ksat` solver is pure Kotlin common code that runs everywhere. The shared logic is in
`src/commonMain/.../XorDemo.kt`; each target has only a thin entry point.

## What it does

Solves `XOR(x1, x2)` = `(x1 OR x2) AND (NOT x1 OR NOT x2)` and enumerates **all** models,
then shows the search run out (UNSAT). Enumeration blocks each model found (add a clause that
forbids that exact assignment) and solves again until UNSAT. Output:

```
CNF:  (x1 OR x2) AND (NOT x1 OR NOT x2)      // XOR(x1, x2)
start solver: ksat / MINISAT
solution 1: x1=false, x2=true
solution 2: x1=true, x2=false
no other solutions (UNSAT).
```

## Prerequisite

The demo consumes the solver from the main repo via relative paths, so it only builds when
`ksat-extra` is checked out **inside** `sat-solvers-kotlin` (the normal case):

```bash
# from the main repo
git submodule update --init ksat-extra
cd ksat-extra
```

## Run it per target

```bash
./gradlew :demo:runJvm                          # JVM (console)
./gradlew :demo:jsBrowserDevelopmentRun         # JS in the browser
./gradlew :demo:wasmJsBrowserDevelopmentRun     # WebAssembly in the browser
./gradlew :demo:runDebugExecutableLinuxX64      # Linux native console
./gradlew :demo:runReleaseExecutableMingwX64    # Windows native console (on Windows)
./gradlew :demo:installDebug                     # Android app "ksat demo"
```

iOS builds as a framework (`:demo:linkDebugFrameworkIosSimulatorArm64`); call
`iosDemoReport()` from Swift, e.g. `Text(DemoKt.iosDemoReport())` in SwiftUI. macOS: run the
JVM console (macOS desktop-native is not a `ksat` target).
