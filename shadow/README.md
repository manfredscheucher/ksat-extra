# shadow/ — the shadowing harness

Shadowing checks that a Kotlin port behaves identically to its C original: an instrumented build
of both prints a trace (every decision, propagation, conflict), and the two are diffed. The
saved C trace is the **golden trace**; the port passes when its trace matches it line for line.
Full methodology and per-solver status: [`../doc/`](../doc/README.md).

## What's here

- `microsat-c/`, `minisat-c/`, `cadical-c/`, `kissat-c/` — the C/C++ references. `*_orig` are
  verbatim upstream copies (microSAT, MiniSat); `*_trace` are self-contained instrumented
  transcriptions of the CDCL core (CaDiCaL, kissat) that print the trace.
- `cnf/`, `cnf-assume/` — the test CNFs (pigeonhole PHP instances etc.).
- `tools/` — scripts to generate CNFs, build the C references, and regenerate the golden traces.
- `BENCHMARK_RESULTS.md` — the raw runtime benchmark table.

The golden traces (`golden*/`) and compiled C binaries are **not** committed; they are
regenerated (needs a C/C++ compiler).

## Run the comparison

The Kotlin shadow tests (in the main repo) look for `ksat-extra/shadow/`. Without it, or without
the goldens, they just skip and `jvmTest` stays green. To actually run them, check out this
submodule and regenerate the goldens (minisat/cadical/kissat each have an `-assume` variant too;
minisat shown):

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
