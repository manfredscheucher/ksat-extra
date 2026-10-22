# Full MiniSat port (core Solver + SimpSolver)

## What was asked

Manfred, 2026-10-22: "minisat ganz hochziehen". Port all of MiniSat, not only the core CDCL
solver: `core/Solver.cc` and the preprocessor `simp/SimpSolver.cc`, 1:1, line by line, never
invent. Follow upstream including its no-ops; fail loudly where upstream asserts (release
semantics, the rule in `cadical-kotlin/.../full/PORTING.md`, "Checks, messages, profiling":
`#ifndef NDEBUG`-only code is not ported, a plain `assert` becomes a check). Target the
maintained fork `meelgroup/minisat` instead of `niklasso/minisat`, because niklasso is
unmaintained (last commit 2013).

## Source choice: meelgroup/minisat 9a0382d

- Local clone `~/github/minisat-meelgroup`, HEAD `9a0382d` (2026-03-14), clean.
- It contains niklasso's last commit `37dc6c6`. `git diff 37dc6c6 9a0382d` over
  `minisat/{core,simp,mtl,utils}` touches 16 lines in 5 files, all compile fixes:
  `mkLit` default argument moved from the friend declaration to the definition
  (`SolverTypes.h`), `"%" PRIu64 "` spacing (`Solver.cc` printStats, `Options.h`),
  `memUsedPeak(bool)` definitions matching the declaration (`System.cc`), FPU guard
  `__linux__` -> `__GLIBC__` (`System.h/.cc`). No behaviour change, so the algorithm is the
  one of niklasso 37dc6c6 ("MiniSat 2.2.0, GitHub final").

## Reference (ksat-extra/shadow/minisat-full)

- `upstream/`: verbatim copy of the clone's `minisat/{core,simp,mtl,utils}` + `LICENSE`
  (25 files; sha256 per file listed in `upstream/README.md`, identical to the clone).
- `trace.patch`: only adds prints (no removed lines; every added line in an upstream file ends
  in `// LSTRACE`, plus the new header `core/lstrace.h`).
  Regenerated against the meelgroup sources: byte-identical to the patch made for niklasso
  (no hunk touches a changed line).
- Built with `clang++ -O2 -std=c++98 -ffp-contract=off -DNDEBUG -D__STDC_LIMIT_MACROS
  -D__STDC_FORMAT_MACROS`; `utils/System.cc` is compiled now. The niklasso build needed
  `g++ -fpermissive` and a `memUsedPeak` stub in `driver.cpp`; both are gone.
- Determinism: every `shadow/cnf/*.cnf` with `--simp=0` and `--simp=1` run twice, same sha256;
  every trace has the same line count as with the niklasso/g++ build.
- Event vocabulary and driver: `shadow/minisat-full/README.md`.

## Port (solver/minisat/minisat-kotlin)

| Kotlin | Upstream |
|---|---|
| `MiniSat.kt` | `core/Solver.h` + `core/Solver.cc` (class `MiniSat` = `Solver`) |
| `MiniSatSimp.kt` | `simp/SimpSolver.h` + `simp/SimpSolver.cc` (`MiniSatSimp : MiniSat`) |
| `SolverTypes.kt` | `core/SolverTypes.h` (lit/lbool, `Clause`, `ClauseAllocator` over `mtl/Alloc.h`, `OccLists`) |
| `Mtl.kt` | `mtl/Vec.h`, `Alg.h`, `Sort.h`, `Heap.h`, `Queue.h`, `IntMap.h` (`IntSet`) |

Notes on the translation:

- Clause memory is upstream's `RegionAllocator<uint32_t>` word by word (header bitfield, extra
  word for activity/abstraction, `wasted`, 13/8 growth), so CRef values, `checkGarbage`,
  `garbageCollect`/`relocAll` and the resulting clause and watch order are upstream's.
- C++ static vs virtual binding: only `garbageCollect` is virtual upstream. `SimpSolver` hides
  `newVar`, `releaseVar`, `addClause_`, `removeClause`, `relocAll`, `solve_` and the solve
  overloads; Solver code that calls them binds to the Solver version (e.g. `reduceDB` and
  `removeSatisfied` call `Solver::removeClause`). In Kotlin those members are `open`, the
  Solver body is `solverXxx`, and Solver-internal call sites call `solverXxx` explicitly.
  Kotlin has no static binding, so a `MiniSatSimp` held as `MiniSat` still dispatches to the
  SimpSolver versions (C++ through a `Solver&` would call the Solver ones); used through its own
  type it behaves as upstream. `solve_()` is not virtual (as upstream).
- Release semantics: `SimpSolver::addClause_`'s `#ifndef NDEBUG` loop over `isEliminated` is
  not ported (comment at its place). Plain asserts are checks (`mAssert`), including
  `IntMap::operator[]`'s `assert(has(k))` (a size check in `IntVec`/`DoubleVec` `get`/`set`;
  plain `vec` has no assert, but an index >= size is undefined behaviour there, so the check
  cannot change a result where the port matches upstream), `RegionAllocator::operator[]`'s
  `assert(r < sz)` (every `ClauseAllocator` clause accessor) and `vec::shrink`'s assert (also
  for watcher lists). One exception: `uncheckedEnqueue` uses a growing push instead of
  `trail.push_` (`assert(sz < cap)`), which always holds because `newVar` reserves
  `trail.capacity(v+1)`.
- Not ported: `printStats` (cpuTime/memUsedPeak), the file-name `toDimacs` overloads (an
  `Appendable` variant exists; the per-clause overload is private), `ClauseIterator`/
  `TrailIterator`, the `#if 0` simp toDimacs, the no-argument `Solver::solve()` (its name is
  the `SatSolver` adapter's `solve()`; use `solve(IntVec())`).
- Floating point: `drand`/`irand`, activities and limits are plain `double` (JVM = C with
  `-ffp-contract=off`). `pow` (non-Luby restarts, `progressEstimate`) comes from the platform
  library on both sides; it matched on every tested case (incl. `--luby=0 --rinc=1.3`), but a
  last-ulp difference between libm and the JVM/JS/native `pow` is possible in principle.

## Verification

`MiniSatLiveShadowTest` (JVM, main repo) starts the reference per case with `LSTRACE=1`
(ProcessBuilder) and compares its stdout line by line in memory with the Kotlin trace of the
same driver flow; no trace files. First difference is reported with 5-6 lines of context on
both sides; the test is skipped visibly when ksat-extra or the reference binary is missing.

Cases: `shadow/cnf/*.cnf` (php_10_9 only with `-Dbigtrace`), `cnf-full/*.cnf`,
`cnf-assume/*` (with assumptions), each with `--simp=0` (core) and `--simp=1` (SimpSolver,
`eliminate(true)` + solve), under 8 option sets: defaults; `--rnd-freq=0.1 --rnd-init=1
--rnd-seed=12345`; `--ccmin-mode=1 --phase-saving=1 --luby=0 --rfirst=7 --rinc=1.3`;
`--ccmin-mode=0 --phase-saving=0 --gc-frac=0.01 --min-learnts=5`; `--asymm=1 --rcheck=1
--grow=2 --cl-lim=-1 --sub-lim=3 --simp-gc-frac=0.01`; `--elim=0 --gc-frac=0.001`;
`--asymm=1`; `--rcheck=1 --rnd-freq=0.05 --rnd-seed=7 --phase-saving=1` (the simp-only sets
run with `--simp=1` only). Result (2026-10-22): 360 runs, all full trace equality (L1,
including the final `MODEL` line), plus php_10_9 (12 runs, all L1) under `-Dbigtrace`. Default `jvmTest`
compares the first 20000 lines per run; `LIVESHADOW_FULL=1` compares everything (about a
minute).

The reference fires every event of the vocabulary over these cases (GC core / GC simp, TRIM,
REDUCE, SUBSUME, STRENGTHEN, ELIM, START asymm, ASSIGN reason=P, ...;
`scripts/probe/minisat_full_event_coverage.sh` counts them).

Harness check: two deliberate mutations (reduceDB `i < learnts.size()/2` -> `<=`, and dropping
the `j--` after strengthening in `backwardSubsumptionCheck`) made 130 runs fail; the simp
mutation alone made 5 runs fail (first diff at a `STRENGTHEN` line). Both reverted.

API paths the driver does not reach (released/free variables incl. both branches of
`SimpSolver::releaseVar`, user polarity, decision variables, budgets/interrupt, `implies`,
`substitute`, `toDimacs`, `freezeVar`/`thaw`, repeated `solve(do_simp = true, turn_off_simp =
false)`) were reviewed line by line against upstream (fresh reviewer, no deviation) and are
exercised by `MiniSatApiTest` (common test; it checks expected behaviour, not trace equality).
Not reached by any test: `SimpSolver::relocAll` with a non-empty subsumption queue.

## Deviations fixed during this step

The two earlier (stopped) agents left a nearly complete port; reviewed against upstream line by
line. Fixed:

- `SimpSolver::addClause_`: the debug-only `isEliminated` assert loop had been ported as an
  always-on check (release has no such check). Removed; the loud failure on an eliminated
  variable moved to the `SatSolver` adapter (`MiniSatSimp.addClause(IntArray)`), see facade.
- `ClauseAllocator` copy constructor (`Clause(const Clause&, bool use_extra)`): the extra word
  was read with a silent `0` fallback past the array end; now a plain word copy as upstream.
- `IntMap::operator[]` `assert(has(k))` was not checked (reads past the size within the
  capacity were silent); now a size check.
- The `SatSolver` adapter of `MiniSatSimp` now calls upstream's own entry point
  `SimpSolver::solveLimited(assumps, do_simp = true, turn_off_simp = true)` (after
  `budgetOff()`, i.e. `solve(assumps, true, true)`) instead of a hand-written
  freeze/eliminate/solve sequence.
- Missing checks found by the fresh review: `RegionAllocator` `assert(r < sz)` and the
  watcher-list `vec::shrink` assert; now checks.
- `MiniSatSimp` had an extra virtual `solve_()` override with no C++ counterpart (dead code);
  removed, `solve_()` is non-virtual like upstream.
- Headers/README: target meelgroup 9a0382d.

No divergence against the upstream traces was found (every run matched before and after these
changes).

## Facade decision

- `Solver.MINISAT` stays the core `Solver` (no preprocessing, fully incremental, like the
  IPASIR wrappers of MiniSat).
- New enum value `Solver.MINISAT_SIMP` = `MiniSatSimp` (an enum value, like the other solver
  choices, rather than a constructor flag). Semantics follow upstream incremental use of
  SimpSolver: `solve(assumps, do_simp = true, turn_off_simp = true)`, i.e. the first solve
  freezes its assumption variables for the elimination and eliminates once; later solves run
  the plain search, and every SAT result goes through `extendModel`. (If the formula is UNSAT
  at the root already, upstream `eliminate` returns before turning simplification off; later
  solves re-enter it and answer UNSAT at once. Harmless.)
- A variable eliminated by the first solve must not be used again: upstream only asserts this in
  debug builds and is unsound in release. The adapter fails loudly instead
  (`IllegalStateException` on an assumption or clause with an eliminated variable), and
  `enumerateModels(MINISAT_SIMP, incremental = true)` is rejected up front (a blocking clause
  names every variable).
- Facade tests with `MINISAT_SIMP`: KsatFacadeTest (all entries), AssumptionsTest (fresh
  instance per assumption, model respects assumption), FailedAssumptionsTest (all; re-solves
  only assume variables the first solve froze), AddClauseAfterSolveTest
  `plainResolveWithoutAddingIsStable`, EnumerateModelsTest (fresh-solver enumeration, under
  assumptions, incremental rejected), and the "unsupported" checks (copy, external propagator,
  phase/listener). Not added, because upstream SimpSolver semantics do not support them
  (they fail loudly with the eliminated-variable error): AssumptionsTest
  `sameInstanceReusableAcrossAssumptions`, AssumptionsReuseStressTest, the add-after-solve
  tests of AddClauseAfterSolveTest, incremental enumeration.

## Open

- The old golden-file tests `ShadowTraceFilesTest` / `ShadowAssumeTraceFilesTest` compare against
  the hand-written `shadow/minisat-c` reference, which deviates from upstream (see
  `shadow/minisat-full/README.md`, "Old reference vs upstream"). They skip today (no golden
  traces generated); regenerated, they would disagree with the port on sat_small, php_4_3 and
  php_7_6..php_9_8. `MiniSatLiveShadowTest` supersedes them. Remove or keep: Manfred's call.
