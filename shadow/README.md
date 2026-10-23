# shadow/ — the shadowing harness

Shadowing checks that a Kotlin port behaves identically to its C original: an instrumented build
of both prints a trace (every decision, propagation, conflict), and the two are diffed. The
saved C trace is the **golden trace**; the port passes when its trace matches it line for line.
Full methodology and per-solver status: [`../doc/`](../doc/README.md).

## What's here

- `microsat-c/`, `minisat-c/`, `kissat-c/` — the C references. `*_orig` are verbatim upstream
  copies (microSAT, MiniSat); `kissat_trace` is a self-contained instrumented transcription of
  the kissat CDCL core that prints the trace.
- `cadical-full/`, `minisat-full/` — verbatim upstream sources plus a trace patch, the references
  for the full 1:1 ports (see their READMEs). `cadical-full/` replaced the old hand transcription
  `cadical-c/cadical_trace.cc` (removed 2026-10-22 together with the old CaDiCaL core port).
- `cnf/`, `cnf-assume/` — the test CNFs (pigeonhole PHP instances etc.).
- `tools/` — scripts to generate CNFs, build the C references, and regenerate the golden traces.
- `BENCHMARK_RESULTS.md` — the raw runtime benchmark table.

The golden traces (`golden*/`) and compiled C binaries are **not** committed; they are
regenerated (needs a C/C++ compiler).

## Run the comparison

The Kotlin shadow tests (in the main repo) look for `ksat-extra/shadow/`. Without it, or with a
`golden-<solver>[-assume]/` dir that is missing or empty, they are reported as SKIPPED (visible
in a normal `jvmTest` run, with the reason and the regen script) and `jvmTest` stays green. A
half-generated state fails: a non-empty golden dir with a CNF that has no trace (or a
`cnf-assume/` CNF without its `.assume`), or a missing `cnf/`/`cnf-assume/`. To actually run them,
check out this submodule and regenerate the goldens (minisat/kissat each have an
`-assume` variant too; minisat shown; CaDiCaL uses `cadical-full/build_and_trace.sh`, see
`cadical-full/README.md`):

```bash
git submodule update --init --checkout ksat-extra
bash ksat-extra/shadow/tools/regen_golden_minisat.sh
bash ksat-extra/shadow/tools/regen_golden_minisat_assume.sh
./gradlew jvmTest                       # now runs the trace comparison
```

The large php_10_9 instance is only compared with `-Dbigtrace` (it needs ~8 GB test heap):

```bash
./gradlew :minisat:jvmTest -Dbigtrace
```
