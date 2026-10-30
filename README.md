# ksat-extra

Extra material for [ksat](https://github.com/manfredscheucher/ksat):
a multiplatform demo, an interactive playground, runtime benchmarks, docs, and the shadowing harness. Its own repo so the
main one stays small; an optional submodule there, NOT pulled by default.

Clone the main repo recursively, then add this submodule (`--recursive` alone skips it, since
it's optional):

```bash
git clone --recursive https://github.com/manfredscheucher/ksat.git
cd ksat
git submodule update --init --checkout ksat-extra
```

Everything builds from inside `ksat-extra/` (it consumes the solvers from the main repo via
relative paths). Run the demo with a script from `scripts/`, e.g. `./scripts/runJVM.sh`, and the
playground with e.g. `./scripts/runPlaygroundWeb.sh`.

## Demo

`demo/` enumerates all models of XOR(x1,x2) with every solver, then UNSAT — the SAME Kotlin
running on JVM, in the browser, on Android and on iOS. One-line run scripts per target in
`scripts/`; see [`demo/README.md`](demo/README.md).

<table>
  <tr>
    <td align="center" width="50%">
      <b>JVM</b>
      <p><img src="misc/screenshot-jvm.png" alt="demo on JVM" width="100%" /></p>
    </td>
    <td align="center" width="50%">
      <b>JS/Browser</b>
      <p><img src="misc/screenshot-web.png" alt="demo in the browser" width="100%" /></p>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <b>Android</b>
      <p><img src="misc/screenshot-android.png" alt="demo on Android" width="60%" /></p>
    </td>
    <td align="center" width="50%">
      <b>iOS</b>
      <p><img src="misc/screenshot-ios.png" alt="demo on iOS" width="60%" /></p>
    </td>
  </tr>
</table>

## Playground

`playground/` is an interactive app (Compose Multiplatform: web, JVM desktop, Android): paste or
load a DIMACS CNF (or generate an example: XOR, exactly k of n, pigeonhole, Ramsey graph), pick a
solver and its options, find one or all solutions, and read the time-stamped output. On the web the solver runs in a Web Worker, so
Stop works at once. Run it with `scripts/runPlaygroundWeb.sh`, `runPlaygroundJVM.sh` or
`runPlaygroundAndroidEmulator.sh`; spec and decisions: [`doc/playground.md`](doc/playground.md).

## Benchmarks

`doc/benchmarks.*` — measured runtime of each Kotlin port vs the original C solver (and
Kotlin/JVM vs Kotlin/Native), on pigeonhole instances.

## Shadowing harness

`shadow/` holds the C references and the tooling to verify each Kotlin port behaves identically
to its C original (not just same SAT/UNSAT, but the same step-by-step trace). What that means
and how to run it: [`shadow/README.md`](shadow/README.md); the methodology and per-solver status:
[`doc/`](doc/README.md).

## License

MIT. The C/C++ references are derivative of their MIT-licensed originals (microSAT © Marijn
Heule; MiniSat © Niklas Eén & Niklas Sörensson; CaDiCaL and kissat © Armin Biere and
contributors); their license headers are preserved in the source files.
