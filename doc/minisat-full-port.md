# Full MiniSat port (core Solver + SimpSolver)

Current target (since 2026-10-27, see "Decision 2026-10-27" below): meelgroup/minisat branch
`master` 664490d with four upstream bugs fixed; meelgroup `csb` 9a0382d is reproduced exactly with
the switch `csbCompat = true`. The sections up to "Open" describe the first step (2026-10-22,
target csb 9a0382d); they still hold for `csbCompat = true`.

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
- DRAT check of the proofs with drat-trim: no binary available (only the source
  `~/github/cadical/test/cnf/drat-trim.c`); `MiniSatDrupTest.unsatProofsVerifyWithDratTrim` runs
  once `DRAT_TRIM=<binary>` is set.

## Master features: DRUP/DRAT proofs and rdb-at

### What was asked

Manfred, 2026-10-22, picked two features of `meelgroup/minisat` branch `master` (664490d,
2020-07-11): "DRUP/DRAT aus master" and "rdb-at Option aus master". Translate 1:1 (never invent,
follow upstream incl. no-ops, release semantics as above). Binary proofs byte-identical to
master's `binDRUP`. show_info statistics printing: not ported (output), the state it maintains is.

First step (2026-10-23): ported with the default kept at csb, i.e. master's elimination order
only while a proof is written. Two decisions were left to Manfred (that gate, and the trim guard).

### Decision 2026-10-27

Manfred: "würde meelgroup default nehmen, nicht csb; das löschen ist sinnvoll ... allgemein würd
ich meelgroup als default sehen ... kannst ja im allgemeinen schalter einführen aber meelgroup
defaults". And on bugs: "wenn du bugs findest behebst die und gibst mir am ende ne liste". Quick
mode of the live tests is enough.

So:

- Default = master 664490d behaviour everywhere, in particular 333d3ef's order in `eliminateVar`
  and `substitute` (old clauses deleted after the new ones are added), with or without a proof.
- Switch `MiniSat.csbCompat` (property, default `false`, also on `MiniSatSimp`): `true`
  reproduces csb 9a0382d exactly (verified against `shadow/minisat-full`). Audit of master vs
  csb: `git diff a352df4 origin/master -- minisat` (a352df4 = csb token-wise, see "Source
  commits") has exactly one behaviour change without a proof and with rdb-at 0: the 333d3ef
  order. Everything else is proof output (only with a proof file), rdb-at (default 0: the old
  condition), show_info (state for rdb-at, printing), and the `verbosity && show_info != 1`
  progress print. So `csbCompat` switches only that order (and the FIX 4 below, which only exists
  for master's order). The facade (`Solver.MINISAT`, `Solver.MINISAT_SIMP`) uses the defaults,
  i.e. master.
- Genuine upstream bugs are fixed, each isolated, reproduced and marked `BUG FIX` in the code;
  see the bug list.

### Bug list (upstream = meelgroup/minisat master 664490d)

| # | Bug | Upstream | Repro (raw master, `shadow/minisat-master/build/*_raw_*`) | Fix (port; reference: `fixes.patch`, driver `-DMASTER_FIXES`) |
|---|---|---|---|---|
| 1 | Proof lines for trimmed clauses are written even without a proof file: `if (trimmed)` lacks the `drup_file &&` of every other proof block. ASCII build: `fprintf(NULL, ...)` crashes at the first trim; binary build: buffers the bytes and would `fwrite` to NULL once 1 MB is pending. | 6b0d7ff, core/Solver.cc `removeSatisfied` (`if (trimmed){`) | `minisat_master_raw_trace_ascii --simp=0 cnf/php_5_4.cnf` exits 139 (SIGSEGV; php_5_4 .. php_8_7) | `if (trimmed && drupFile != null)` (MiniSat.kt removeSatisfied) |
| 2 | rdb-at does not work without show_info: `reducedb_last_confl = conflicts` is set only inside the `show_info == 1` block, so with `-rdb-at=k` it stays 0 and reduceDB runs before every decision once `conflicts >= k`. | a19dbf7 / b1f6f7f, core/Solver.cc `reduceDB` | `--rdb-at=7 cnf/php_7_6.cnf`: 3616 REDUCE for 2635 CONFLICT; with `--show-info=1`: 310 REDUCE | assignment moved after the block (same value as with show_info 1); MiniSat.kt reduceDB |
| 3 | Binary proof tail lost: the solver writes its static proof buffer only when more than 1 MB is pending or when `solve_` returns `l_False`; simp/Main.cc never flushes it, so when `eliminate` proves UNSAT (Main.cc does not call solve) only the final `a 0` reaches the file (SAT/UNKNOWN runs lose the tail too). | 1d1940a, core/Solver.h `binDRUP_flush` (protected), simp/Main.cc | `minisat_master_raw_trace --simp=1 --drup=1 cnf/php_3_2.cnf` writes 2 bytes; the ASCII proof has 24 lines | `binDRUPFlush()` public; the application flushes before the final clause / close (Kotlin test driver, reference driver.cpp `DrupFlush`). Fixed binary proof = ASCII proof binary-encoded (checked) |
| 4 | With `-rcheck`, variable elimination is unsound in master's order: every resolvent is added while its antecedents are still present, so `implied()` finds each resolvent implied and drops it, then the antecedents are deleted. Same in `substitute`. | 333d3ef, simp/SimpSolver.cc `eliminateVar`, `substitute` | `minisat_master_raw_trace --simp=1 --rcheck=1 cnf/php_3_2.cnf`: SATISFIABLE (php_3_2 .. php_8_7, conflict_small, 4 cnf-full instances; csb: UNSATISFIABLE) | the resolvents / substituted clause are added without the rcheck (`addClauseWithoutRcheck`, MiniSatSimp.kt); in csb order (`csbCompat`) unchanged |

`MiniSatDrupTest.upstreamBugsReproduceAndAreFixed` checks each repro on the raw build and the fix
in the fixed reference and in the port; `MiniSatApiTest.substituteWithRcheckKeepsUnsatInBothOrders`
covers bug 4 in `substitute` (not reachable from the driver).

Not changed (not a demonstrable failure): `SimpSolver::addClause_` writes `a ps` also after
`Solver::addClause_` returned early (satisfied/tautological clause, `ps` partly compacted) and
writes a clause again that `Solver::addClause_` already wrote shortened; `removeClause`'s
`printf("c Bug ...")` (message, not ported); show_info prints `c [reduceDB]` lines to stdout, into
a proof written to stdout (output, not ported).

### Source commits

master = niklasso 37dc6c6 + `4565536` (mkLit compile fix) + `a352df4` (clang-format; token-wise
identical to csb 9a0382d apart from csb's compile fixes, checked with
`scripts/probe/minisat_token_diff.py`) + the feature commits, read one by one:
`1d1940a` Adding DRUP (`drup_file`, `add_oc`, `BIN_DRUP` buffer, `binDRUP`/`byteDRUP`/
`binDRUP_strengthen`/`binDRUP_flush`, proof lines in `addClause_`, `removeClause`, learnt clauses
in `search`, flush in `solve_`, `SimpSolver::addClause_`, `strengthenClause`, simp/Main.cc
`-drup`/`-drup-file`), `9e03655` (`SimpSolver::parsing`), `333d3ef` "Fixing DRAT" (eliminateVar /
substitute delete the old clauses after adding the new ones), `6b0d7ff` (removeSatisfied: proof
lines for trimmed clauses), `b1f6f7f` (`show_info`, `reduceDB_call`, `reducedb_last_confl`,
statistics prints), `a19dbf7` (option `rdb-at` = `reduceDB_at_confl`, `reduceDB_needed()`),
`664490d` (CMake only).

### Port

| Upstream (master) | Kotlin |
|---|---|
| `FILE* drup_file` | `MiniSat.drupFile: DrupFile?` (`fun interface DrupFile { write(buf, off, len) }`, `DrupFile.kt`); null = off (default) |
| `#define BIN_DRUP` (set in master's Solver.h) | `MiniSat.binDrup: Boolean = true`; `false` = the `#else` ASCII branches |
| `SimpSolver::parsing` | `MiniSatSimp.parsing` (default false) |
| `int show_info` | `MiniSat.showInfo` (default 0) |
| option `rdb-at` / `reduceDB_at_confl` | `MiniSat.reduceDBAtConfl` (default 0, range checked like `IntRange(0, INT32_MAX)`) |
| `reduceDB_call`, `reducedb_last_confl` | read-only `reduceDBCall`, `reducedbLastConfl` |
| `reduceDB_needed()` | `reduceDBNeeded()` |
| `byteDRUP`, `binDRUP`, `binDRUP_strengthen`, `binDRUP_flush`, `add_oc` | same names (`binDRUPClause` for the clause overload, `binDRUPFlush`, public: bug 3), `addOc` |
| (csb 9a0382d) | `MiniSat.csbCompat` (default false) |

Every proof line sits where master writes it; the `#ifdef BIN_DRUP ... #else ... #endif` blocks
are `drupLits`/`drupClause` (binary or ASCII by `binDrup`). The ASCII form is written one line per
`write` call (`fprintf` per literal upstream; same bytes). simp/Main.cc's part (open the file,
`parsing` around reading, `binDRUPFlush()`, the final empty clause `a 0` / `0\n` after UNSAT,
`fclose`) is application code: the user of the API does it (`MiniSatShadowDriver` mirrors it).
show_info's `printf`s and header lines are not ported; `verbosity >= 1 && show_info != 1` for the
progress line is.

Remaining differences from master besides the bug fixes: master's proof buffer (`drup_buf`,
`buf_len`, `buf_ptr`) is static, one per process, shared by all Solver objects; the port has one
per solver (2 MB, allocated on first use). Same byte stream for one solver.

Faithfully ported oddities: binary proofs are written in chunks only by `binDRUPFlush` (more than
1 MB pending, end of `solve_` with `l_False`, or the application); `SimpSolver::addClause_` writes
clauses `Solver::addClause_` already wrote (see bug list, "not changed").

### Reference (shadow/minisat-master)

Second reference next to `shadow/minisat-full` (csb, the `csbCompat` reference): verbatim export
of master 664490d, the same trace events (`trace.patch` re-anchored for the clang-formatted
sources), `fixes.patch` (bugs 1, 2, 4) and `driver.cpp` (`--drup=0|1|devnull`, `--show-info`;
bug 3 with `-DMASTER_FIXES`). Four builds: fixed binary/ASCII (`minisat_master_trace`,
`_ascii`: the port's default target) and raw binary/ASCII (`minisat_master_raw_trace`, `_ascii`:
for the repros). clang++ with the csb flags plus `-Dfwrite_unlocked=fwrite` (glibc-only function,
missing on macOS); `utils/System.cc` not compiled (does not compile on macOS; `memUsedPeak` stub in
the driver). Details: `shadow/minisat-master/README.md`.

### Verification (2026-10-27, quick mode)

- `MiniSatLiveShadowTest.portMatchesMasterLive`: default options against the fixed master
  reference, `cnf` + `cnf-full` + `cnf-assume`, `--simp=0/1`, the 8 option sets (incl. rcheck /
  asymm sets): 360 runs, L1 on the first 20000 lines, 0 failing.
- `MiniSatLiveShadowTest.csbCompatMatchesCsbLive`: `csbCompat = true` against
  `shadow/minisat-full`: 360 runs, 0 failing.
- `MiniSatDrupTest.proofsMatchMaster`: proof bytes vs. the fixed reference `--drup=1`, binary and
  ASCII, `cnf` + `cnf-full`, `--simp=0/1`, option sets default; `--ccmin-mode=0 --phase-saving=0
  --gc-frac=0.01 --min-learnts=5`; `--asymm=1 --rcheck=1 --grow=2 --cl-lim=-1 --sub-lim=3
  --simp-gc-frac=0.01`; `--rdb-at=7` (cnf only: on cnf-full its proofs reach several GB):
  310 runs, 282,412,986 proof bytes compared byte for byte (298 runs with more than the final
  clause; several cnf-full proofs exceed 1 MB, so mid-run flushes are covered), 0 failing.
- `MiniSatDrupTest.tracesMatchMasterRdbAt`: `--rdb-at` 1/7/50/3 with and without show-info
  (`--simp=1` with `--drup=devnull`): 319 runs, 0 failing, plus `reduceDBCall` == number of
  `c [reduceDB]` lines.
- `MiniSatDrupTest.upstreamBugsReproduceAndAreFixed`: bugs 1-4 reproduced on raw master and fixed.
- `MiniSatApiTest` (15, incl. bug 4 in `substitute`), `MiniSatSanityTest`, facade tests
  (`:ksat:jvmTest --tests 'org.bytefred.ksat.facade.*'`, 65 tests) green.
- Harness checks: dropping the rcheck fix made `substituteWithRcheckKeepsUnsatInBothOrders` and 30
  master live runs fail; (2026-10-23) forcing the csb order with a proof made 78 proof and 94 trace
  runs fail. Both reverted.
