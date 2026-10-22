# Full CaDiCaL port (all of CaDiCaL 2.1.3)

## What was asked

Manfred, 2026-10-21: "mach weiter, alles portieren für cadical". Port all of CaDiCaL, not only the
CDCL core + incremental API. The rule from the start of the project still holds: translate the
upstream code 1:1, line by line; never invent. Follow upstream behaviour, including its no-ops;
deviate only for an upstream bug that can be isolated and reproduced.

## Key decision: the reference becomes real upstream

The existing shadow reference `shadow/cadical-c/cadical_trace.cc` is a simplified
re-implementation of the core, and it deviates from upstream 2.1.3 in places (reduce schedule and
`keep` flag, two restart margins, no root-level `mark_satisfied` during search; found while
writing the SAT techniques tutorial). A full port cannot be checked against it.

New reference: `shadow/cadical-full/` holds a verbatim copy of upstream CaDiCaL 2.1.3
(`f13d744`) plus a separate patch that only adds trace output at the shared events. The copy
stays verbatim; the build script applies the patch to a build directory. The Kotlin port must
match this reference with upstream default options, step by step.

## Plan

1. Foundation: instrumented upstream reference + build/trace scripts; Kotlin skeleton that mirrors
   the headers (`Internal`, `External`, `Var`, `Flags`, `Clause`, watches, occurrence lists, all
   options with upstream defaults, stats, limits, averages, queue, heap, random).
2. Parallel translation: each upstream `.cpp` becomes a `.kt` of extension functions on `Internal`
   (C++ member functions spread over files map to Kotlin extension functions spread over files).
3. Integration: compile, then match traces against the reference. Upstream has an option per
   technique, so first all inprocessing off (core must match), then enable one technique at a
   time until the default configuration matches.
4. Switch over: the facade's `Solver.CADICAL` uses the full port once it passes every existing test
   (facade tests incl. IPASIR-UP / failed / phase / listener) and the new shadow suite.

The new code lives next to the old port in package `org.bytefred.ksat.cadical.full` until the
switch. Branch: `incremental`.

## Scope

In: everything the solver does (all of `src/*.cpp` that implements solving, inprocessing,
incremental API, IPASIR-UP, model reconstruction, options, statistics as counters).
Proof tracers (DRAT/LRAT/FRAT/VeriPB/IDRUP/LIDRUP, checkers, LRAT builder): proof wave, writing
to a byte sink (see "Proof wave" below).
Out (not a solver): `mobical.cpp` (fuzzer), `cadical.cpp` (CLI app), `ccadical.cpp`/`ipasir.cpp`
(C API), terminal/signal/resources/file I/O and message formatting (mapped to no-ops or Kotlin
equivalents where the solver logic needs them).

## Reference build (step 1, done 2026-10-21)

`shadow/cadical-full/` (details and the exact trace vocabulary in its `README.md`):
`upstream/` verbatim 2.1.3 sources, `trace.patch` (adds `lstrace.hpp` and prints only,
no removed lines), `driver.cpp` (Solver API + a proof `Tracer` for ADD/DEL/WEAKEN lines),
`build_and_trace.sh` (golden traces for `plain` and `default` into
`shadow/golden-cadical-full-<config>/`).

Decisions taken while building it:
- Search events print external literals (`Internal::externalize`), clause reasons as
  `<id> :<lits>` in stored order, so the port must match clause ids and literal order.
- `START x`/`END x` bracket the whole upstream function (first statement to any return),
  so phases that return at once (e.g. `cover` with `cover=0`) still appear.
- Assignments inside probe/vivify/instantiate/condition are not traced (only their
  `BACKTRACK` lines and their clause effects via the tracer).
- The proof tracer does not change the search, but proof mode allocates extra clause ids
  (e.g. OTFS strengthening). Goldens are made with the tracer on; `LSPROOF=0` traces
  differ only in ids. `CHECK=1` verifies determinism and this neutrality.
- `plain` is upstream's config: it disables only the preprocessing-flagged options;
  lucky, walk, rephase, chrono, otfs stay on.
- With the current shadow CNFs, `default` only differs from `plain` on php_8_7, php_9_8
  (and php_10_9): the small instances finish before any inprocessing is scheduled.

## Integration (step 3, 2026-10-21)

Harness: `solver/cadical/src/jvmTest/kotlin/org/bytefred/ksat/cadical/full/FullShadowTraceTest.kt`
(main repo). For every `shadow/cnf/*.cnf` (php_10_9 only with `-Dbigtrace`) and every config in
{plain, default} it runs `runShadow` like `build_and_trace.sh` runs the C driver
(`--config=<config>`, no other options, proof tracer connected) and requires the trace to be
line-for-line identical to `golden-cadical-full-<config>/<name>.trace` (L1); on a mismatch it
prints the first differing line with +-5 lines of both sides. Verdict and (on SAT) the model
are checked separately. Skips visibly when ksat-extra or the goldens are missing. Filters:
`-Dfullshadow.only=a,b`, `-Dfullshadow.configs=plain`.

Result of the first run of the translated port: L1 on all 16 CNFs under both `plain` and
`default` (php_9_8: 1.37M / 708k trace lines), with no fix to search behaviour needed. The
`default` traces of php_8_7 / php_9_8 exercise probe, vivify, subsume, elim, block, cover,
ternary, decompose, transred, deduplicate, collect, rephase, walk and lucky.

Integration cleanups done (no behaviour change on the traces): `searchAssignDriving` takes
`Clause?` in SIGNATURES.md (upstream passes null for units); `assume.cpp` uses the
`External.checkLearnedClause` wrapper instead of its inlined body; `External.checkFailing`
translated now that `Solver` exists (only with `opts.check`); ElimHpp.kt comment points to
backward.cpp. `lookahead_locc` sees literal 0 (the index 0 entry of `lookahead_populate_locc`);
in the release build `active (0)` reads `ftab[0]`, an UNUSED `Flags`, so 0 is simply not
active: well defined, no undefined behaviour (only the debug build's `vidx` assert would
fire). The port follows release and reads `ftab[0]` directly.

Release semantics (2026-10-22, owner: "cadical 1:1 übernehmen so wies original is"): the
target is the release (`NDEBUG`) build the reference is made with. `#ifndef NDEBUG` /
`#ifdef LOGGING` code is not ported; plain asserts stay as `check` (they cannot fire when the
port matches upstream; fail loudly otherwise). Full rule in PORTING.md. The `CaDiCaLFull`
facade adapter makes no checks of its own: API misuse fails in the port's `REQUIRE`
(`IllegalStateException`) exactly where upstream fails, and `valueOf` is `val (v) > 0`
(only in the satisfied state, as upstream).

### Live comparison (no golden files)

The disk is too full for more golden traces, so a second harness compares against the C
reference while both run: `FullLiveShadowTest.kt` (next to `FullShadowTraceTest.kt`) starts
`cadical-full/build/cadical_full_trace` with `LSTRACE=1` via `ProcessBuilder`, drops its `s `/`c `
lines like `build_and_trace.sh`, and compares each line against `runShadow` through a bounded
queue (first difference reported with +-5 lines from a ring buffer; nothing is written to disk).
Both drivers get exactly the same arguments. Suites: `cnfFull` (every `cnf-full/OPTIONS` line
under `--config=default` + its arguments), `cnfAssume` (`cnf-assume/*.cnf` + `.assume`, plain and
default), `bigPhp` (php_10_9 default, only with `-Dbigtrace`). Skips visibly without ksat-extra or
the C binary. `FullShadowTraceTest` now also streams its golden trace (bounded memory; the
512 MB test heap could not hold both php_9_8 traces) and writes only the context report.

New driver option `--limit:<name>=<n>` (driver.cpp and `runShadow`): `Solver::limit` right
before `solve`. Needed to reach `preprocess` (only runs with `limit("preprocessing", n > 0)`);
`cnf-full/OPTIONS` has `bin_gadgets_r4.cnf --limit:preprocessing=1`, and
`tools/cnf_full_coverage.sh` now reports every phase covered (preprocess counts as a phase
without own proof events; its probe/elim/condition nest inside it).

Result (2026-10-21): L1 on all 11 cnf-full runs, all 8 cnf-assume runs and php_10_9 default
(5.5M lines; Kotlin 9.6 s vs C 4.9 s), with no fix to the port needed.

## Proof wave (2026-10-21)

Asked: port the remaining part 1:1 (drat/lrat/frat/veripb/idrup/lidrup tracers, DRUP checker,
LRAT checker, LRAT builder), remove the `error(...)` placeholders, verify against upstream
byte for byte without large files.

Done: `DratTracer.kt`, `LratTracer.kt`, `FratTracer.kt`, `VeripbTracer.kt`, `IdrupTracer.kt`,
`LidrupTracer.kt`, `Checker.kt`, `LratChecker.kt`, `LratBuilder.kt` (replaces the forward
interface in ProofHpp.kt); `Internal.trace (file)`, `Internal.check ()` and
`setupLratBuilder` in Proof.kt construct them as upstream. `File` (FileHpp.kt) now writes
bytes to a `FileSink` (`put (unsigned char)` for the binary varints) and has
`close` / `flush` / `closed` / `piping` (always false). `Solver.traceProof (FileSink, name)`
added next to the `Appendable` one.

Verification: the C driver got `--proof=<path>|-` (trace_proof / close_proof_trace), the
Kotlin `runShadow` the same (`proofOut`, `lstrace = false` models LSTRACE unset).
`solver/cadical/src/jvmTest/.../FullProofTest.kt` streams the C stdout and compares it byte
by byte with the port (with `--quiet=1` so no `c` messages): 6 CNFs (php_5_4, php_6_5,
hard_rand_unsat_60, unsat_small, cnf-full/transred_parity40, cnf-full/lucky_horn (SAT)) x
16 format settings (drat/lrat/frat1 ascii+binary, frat2 binary, veripb 1-4, idrup/lidrup
ascii+binary, lrat with externallrat): all 96 identical. Checkers: `check=1` with
`checkproof` 1/2/3 and `externallrat=1` on the same CNFs: no checker error, upstream
verdict, LRAT proof still byte-identical to C.

Interpretation choices: VeriPB's `binary` member and `put_binary_*` helpers (only under
`#ifndef NDEBUG`, never called) and the never-read `last_clause` / unused `delete_ids`
members are not ported; `print_stats` / `print_statistics` / `dump` only print and are
empty or not ported; `fatal_message_*` -> `error`.

