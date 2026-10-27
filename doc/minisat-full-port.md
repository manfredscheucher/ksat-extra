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

## Coverage audit (2026-10-27)

Fresh, independent audit (auditor did not write the port), asked by Manfred 2026-10-23 before a
`copy()` extension: which MiniSat is ported, does the Kotlin port cover everything of the
original / meelgroup, what is new. Read-only on code. Sources: `~/github/minisat-meelgroup`
(`origin/master` 664490d, `origin/csb` 9a0382d, `origin/crystalball` 96ce818, niklasso 37dc6c6).
Kotlin paths below are relative to `solver/minisat/minisat-kotlin/src/commonMain/kotlin/org/bytefred/ksat/minisat/`;
`M` = `MiniSat.kt`, `S` = `MiniSatSimp.kt`, `T` = `SolverTypes.kt`, `X` = `Mtl.kt`.

**Verdict: COMPLETE-EXCEPT** the deliberately unported, non-algorithmic parts listed below
(printing/CLI/OS/file I/O, iterators, DIMACS parser replaced). Every function, struct and option of
`core/Solver.*`, `core/SolverTypes.h`, `simp/SimpSolver.*` and the `mtl` headers the solver uses is
ported; no algorithmic member is missing.

### Ported target

meelgroup `master` 664490d (= niklasso 37dc6c6 + 4565536 + a352df4 clang-format + DRUP/rdb-at
commits) with 4 bug fixes; `csbCompat = true` = meelgroup `csb` 9a0382d (= niklasso 37dc6c6 +
compile fixes). Nothing of `crystalball`.

### core/Solver.h + Solver.cc

| Upstream | Kotlin | Status |
|---|---|---|
| `Solver()` ctor, all member defaults | `M:53`ff | ported |
| `newVar(upol, dvar)` (free_vars reuse) | `newVar` / `solverNewVar` M:444/446 | ported |
| `releaseVar(Lit)` | M:474/476 | ported |
| `addClause(vec)`, `addEmptyClause`, `addClause(p[,q[,r[,s]]])`, `addClause_` | M:370-377, 484/486 | ported |
| `simplify()` | M:1025 | ported |
| `solve(assumps)`, `solve(p)`, `solve(p,q)`, `solve(p,q,r)`, `solveLimited(assumps)` | M:422-431 | ported |
| `solve()` (no argument) | `solve(IntVec())`; the name is `SatSolver.solve()` | renamed (see note A) |
| `okay`, `implies` | M:432, 1289 | ported |
| `toDimacs(FILE*, assumps)`, private `toDimacs(FILE*, Clause&, map, max)`, `mapVar` | `toDimacs(Appendable[, assumps])` M:434/1339, private M:1329/1321 | ported (Appendable) |
| `toDimacs(const char* file, ...)` 5 overloads | - | not ported (file I/O) |
| `clausesBegin/End`, `trailBegin/End` (`ClauseIterator`, `TrailIterator`) | - | not ported (no public clause/trail iteration) |
| `setPolarity`, `setDecisionVar` | M:402/403 | ported |
| `value(Var/Lit)`, `modelValue(Var/Lit)` | `valueVar/valueLit/modelValue/modelValueLit` M:392-395 | ported |
| `nAssigns/nClauses/nLearnts/nVars/nFreeVars` | M:396-401 | ported |
| `printStats` | - | not ported (cpuTime/memUsedPeak, printing) |
| `setConfBudget/setPropBudget/budgetOff/interrupt/clearInterrupt`, `withinBudget` | M:410-419 | ported (see note B) |
| `garbageCollect` (virtual), `checkGarbage()`, `checkGarbage(gf)` | M:1434, 360/361 | ported |
| `model`, `conflict` (LSet) | M:133/136 (`LitSet`) | ported |
| options: `verbosity var_decay clause_decay random_var_freq random_seed luby_restart ccmin_mode phase_saving rnd_pol rnd_init_act garbage_frac min_learnts_lim restart_first restart_inc learntsize_factor learntsize_inc learntsize_adjust_start_confl learntsize_adjust_inc` | M:82-111, upstream defaults (checked against `opt_*`) | ported; ranges not checked (upstream checks them only in CLI parsing; direct member assignment is unchecked too) |
| master: `drup_file`, `show_info`, `reduceDB_at_confl` (rdb-at), `reduceDB_call`, `reducedb_last_confl`, `add_oc`, `BIN_DRUP` buffer + `byteDRUP/binDRUP/binDRUP_strengthen/binDRUP_flush`, `reduceDB_needed` | M:63/85/102/128/129/176, 223-322, 1188 | ported (rdb-at range-checked, stricter than a member assignment upstream) |
| statistics `solves starts decisions rnd_decisions propagations conflicts dec_vars num_clauses num_learnts clauses_literals learnts_literals max_literals tot_literals` | M:114-126 (read-only) | ported |
| state `clauses learnts trail trail_lim assumptions activity assigns polarity user_pol decision vardata watches order_heap ok cla_inc var_inc qhead simpDB_assigns simpDB_props progress_estimate remove_satisfied next_var ca released_vars free_vars seen analyze_stack analyze_toclear add_tmp max_learnts learntsize_adjust_confl learntsize_adjust_cnt conflict_budget propagation_budget asynch_interrupt` | M:139-185 (`VarData` split in `vardataReason/vardataLevel`, `ShrinkStackElem` in `analyzeStackI/L`) | ported |
| `Watcher`, `WatcherDeleted`, `VarOrderLt` | `WatchVec`/`Watches` T:253/284, M:155 | ported |
| `insertVarOrder pickBranchLit newDecisionLevel uncheckedEnqueue enqueue propagate cancelUntil analyze analyzeFinal litRedundant search solve_ reduceDB (+ reduceDB_lt) removeSatisfied rebuildOrderHeap` | M:331, 611, 388, 841, 367, 854, 590, 647, 811, 745, 1080, 1234/1236, 929, 963, 1013 | ported |
| `varDecayActivity varBumpActivity(x2) claDecayActivity claBumpActivity` | M:335-349 | ported |
| `attachClause detachClause removeClause isRemoved locked satisfied decisionLevel abstractLevel reason level progressEstimate relocAll` | M:534, 544, 562/564, 383, 384, 582, 390, 391, 328, 329, 1195, 1385/1387 | ported |
| static `drand`, `irand`, file-static `luby` | M:1454, 1462, 1217 | ported |

### simp/SimpSolver.h + SimpSolver.cc

| Upstream | Kotlin | Status |
|---|---|---|
| ctor (extra field, `bwdsub_tmpunit`, `remove_satisfied = false`), `newVar`, `releaseVar` | S:72, 187, 203 | ported |
| `addClause` variants, `addEmptyClause` (inline, call the hidden `addClause_`) | inherited M:370-377 (dispatch to S:256) | ported |
| `addClause_`, `removeClause`, `strengthenClause`, `merge` x2, `gatherTouchedClauses`, `implied`, `backwardSubsumptionCheck`, `asymm`, `asymmVar`, `mkElimClause` x2, `eliminateVar`, `substitute`, `extendModel`, `eliminate`, `relocAll`, `garbageCollect`, `updateElimHeap` | S:256, 294, 306, 339/371, 400, 425, 445, 529, 555, 582/587, 610, 715, 754, 775, 878, 903, 85 | ported |
| `setFrozen`, `isEliminated`, `freezeVar`, `thaw` | S:93, 83, 99, 107 | ported |
| `solve(assumps|p|p,q|p,q,r|-, do_simp, turn_off_simp)`, `solveLimited(assumps, do_simp, turn_off_simp)`, `solve_(do_simp, turn_off_simp)` | S:117-145, 214 | ported (no default args on the 2-flag overloads; the 1-arg overrides use `true, false`) |
| options `grow clause_lim subsumption_lim simp_garbage_frac use_asymm use_rcheck use_elim extend_model`; master `parsing` | S:33-42, upstream defaults | ported |
| stats `merges asymm_lits eliminated_vars` | S:45-47 | ported |
| state `elimorder use_simplification max_simp_var elimclauses touched occurs n_occ elim_heap subsumption_queue frozen frozen_vars eliminated bwdsub_assigns n_touched bwdsub_tmpunit`, `ElimLt`, `ClauseDeleted` | S:50-69, `CRefOccLists` T:330 | ported |
| `#if 0` toDimacs block | - | dead upstream |

### core/SolverTypes.h, mtl/*, utils/*, Dimacs.h, Main.cc

| Upstream | Kotlin | Status |
|---|---|---|
| `Lit`, `mkLit ~ ^ sign var toInt toLit`, `lit_Undef/lit_Error`, `var_Undef` | T:13-21 (Lit = Int, toInt/toLit identity) | ported |
| `lbool` (incl. the `==` with undef bit), `l_True/l_False/l_Undef`, `toInt/toLbool` | T:26-34 (`lbEq`, `lbXor`, `lbOf`) | ported |
| `Clause` (header bitfield, `size learnt has_extra mark reloced activity abstraction calcAbstraction shrink pop last subsumes strengthen`), `ClauseAllocator` (`alloc` x2, `free`, `reloc`, `moveTo`, `clauseWord32Size`, `extra_clause_field`) | T:52-250, word layout identical | ported |
| `OccLists` (`init lookup cleanAll clean smudge clear`), `VMap LMap LSet MkIndexLit` | T:284/330, `IntVec`/`DoubleVec`/`LitSet` | ported |
| `CMap` (+ mtl/Map.h) | - | unused by core/simp |
| mtl/Vec.h, Alg.h (`remove`, `append`, `copyTo`), Sort.h, Heap.h, Queue.h, IntMap.h (`IntMap`, `IntSet`), Alloc.h | X:26, 113/122, 133-169, 174, 282, 108-110/326, T:52 | ported (Heap/Sort/Queue/Alloc re-read against master: identical) |
| mtl/Rnd.h, XAlloc.h, IntTypes.h | - | Rnd.h unused by Solver; C memory/int typedefs |
| utils/Options.* (Option classes, `parseOptions`, usage) | public vars | not ported (CLI) |
| utils/System.* (`cpuTime memUsed memUsedPeak setX86FPUPrecision limitMemory limitTime sigTerm`) | - | not ported (OS) |
| utils/ParseUtils.h, core/Dimacs.h `parse_DIMACS` | replaced by `org.bytefred.ksat.DimacsCnf.parse` (ksat-common) | REPLACED, not equivalent (note C); closed: ported (follow-up below) |
| core/Main.cc, simp/Main.cc (`-verb -cpu-lim -mem-lim -strict -pre -solve -dimacs -drup -drup-file -show-info`, signal handlers, result printing, final proof line) | test `MiniSatShadowDriver` mirrors the parse / eliminate / solveLimited / proof-end flow | not ported (application) |

Notes:

- A. `SatSolver.solve()` on a `MiniSatSimp` is `solveLimited(assumps, do_simp = true, turn_off_simp = true)`
  (plus the eliminated-variable checks), not upstream `SimpSolver::solve()` (`turn_off_simp = false`).
  Documented in the facade decision; the upstream call is `solve(true, false)`.
- B. (closed: `@Volatile`, follow-up below) `asynchInterrupt` is a plain `var` (M:185). Upstream's `bool` is not atomic either, but on the
  JVM the JIT may hoist the read out of the search loop, so `interrupt()` from another thread is
  not guaranteed to be seen. CaDiCaL's port uses `@Volatile` for its terminate flag.
- C. (closed: parser ported, DimacsCnf fixed, follow-up below) `DimacsCnf.parse` vs `parse_DIMACS` (probe CNFs run on `minisat_master_trace`, Kotlin side by
  code reading):

  | Input | MiniSat | DimacsCnf |
  |---|---|---|
  | more clauses than the header `m` (`p cnf 1 1`, `1 0`, `-1 0`) | reads all: UNSAT | stops after `m`: drops `-1 0` silently (SAT) |
  | last clause without `0` | PARSE ERROR, exit 3 | accepted |
  | `1 2 0 c comment` (comment after a clause on the same line) | comment skipped | `NumberFormatException` |
  | `p wcnf ...`, `p  cnf` (two spaces) | PARSE ERROR | accepted |
  | SATLIB tail `%` / `0` after `m` clauses | PARSE ERROR | accepted |
  | header variable count | ignored (vars created lazily) | kept in `numVars`, not used by the MiniSat adapter |

  The live shadow CNFs are well-formed, so the tests are unaffected. For the facade it matters little,
  but the first row is a silent clause drop.

### Test claims checked

| Claim | Check | Result |
|---|---|---|
| live shadow: simp=0/1, master default and csbCompat, assumptions, 8 option sets, 360 runs | read `MiniSatLiveShadowTest`: 30 cases (cnf 16 without php_10_9, cnf-full 10, cnf-assume 4) x (4 core sets + 8 simp sets) = 360; both references | confirmed |
| master default verified | 2026-10-27 only in quick mode (first 20000 lines per run); full traces were compared for csb (2026-10-22) | gap, low |
| option coverage | never varied: `var-decay`, `cla-decay`; no CLI upstream (so no shadow): `rnd_pol`, `learntsize_*`, `verbosity` | gap, low (one-line code) |
| incremental use | every shadow run is one `solveLimited`; repeated solve, add-after-solve, release/reuse only behaviour-tested (`MiniSatApiTest`, facade tests) | gap, medium for `copy()`; closed: incremental shadow (follow-up below) |
| bugs 1-4 reproduce on raw master, fixed build differs | raw binaries run: bug 1 exit 139 vs 20; bug 2 3616 vs 310 REDUCE; bug 3 2 bytes vs 93 (ASCII 24 lines); bug 4 SATISFIABLE vs UNSATISFIABLE on php_3_2 | confirmed |
| `SimpSolver::relocAll` with non-empty queue (untested) | code compared with master line by line | identical |

Gradle tests were not run in this audit (cold Gradle start exceeds the short-timeout rule).

### Diffs

| Range | Commits (minisat/ only) | Content | In the port |
|---|---|---|---|
| niklasso 37dc6c6 -> csb 9a0382d | c554273 4d9462e 3db5894 26b58cf a98e44f dbef978 4c8afcd (+ CMake/CI commits) | 16 lines in 5 files: friend default arg, `PRIu64` spacing, `memUsedPeak` signature, `__GLIBC__` FPU guard | n/a (no behaviour); `csbCompat = true` |
| 37dc6c6 -> master 664490d | 4565536 (compile fix), a352df4 (clang-format, token-identical), 1d1940a DRUP, 9e03655 `parsing`, 333d3ef eliminateVar/substitute order, 6b0d7ff trim proof lines, b1f6f7f show_info, a19dbf7 rdb-at, 664490d CMake | proofs, rdb-at, show_info counters, elimination order | all; show_info printing not ported |
| master -> crystalball 96ce818 | 94 commits from merge base a19dbf7 (eb49954 SQLite .. 96ce818) | SQLite clause statistics, clause IDs in DRAT, ML clause deletion `reduceDB_ml` (`pred-rdb`, json model), glucose restarts (`glu-rst`), ML restarts (`pred-rst`), locked-clause counting in reduceDB, drup_debug prints, scripts | nothing (research branch) |

Upstream bugs (verified against the source): 1 `if (trimmed)` without `drup_file &&` (master
Solver.cc removeSatisfied; crystalball fixed it as `drup_file && trimmed && !empty_on_trimming`);
2 `reducedb_last_confl = conflicts` only inside `if (show_info == 1)` (crystalball fixed it
differently: `last_conflicts = conflicts` after every reduceDB in search, same semantics as the
port's fix); 3 `binDRUP_flush` protected and never called in simp/Main.cc (still so in crystalball);
4 resolvents added through `addClause_` with `use_rcheck` while their antecedents are still in the
database, so `implied()` is always true (still so in crystalball).

### State a `copy()` of the core solver must handle

| Area | State | Pitfall |
|---|---|---|
| clause memory | `ca` (`memory`, `sz`, `cap`, `wasted`, `extraClauseField`), `clauses`, `learnts` | CRefs are word offsets; a copy either clones the array (same CRefs) or relocates (like `garbageCollect`), and then every CRef holder must be remapped |
| CRef holders | `watches` (cref+blocker pairs, `dirty`/`dirties`), `vardataReason`, Simp `occurs` (+ dirty), `subsumptionQueue`, `bwdsubTmpunit` | all private in `Watches`/`CRefOccLists`/`IntQueue`; needs copy methods in T/X |
| assignment | `assigns`, `trail`, `trailLim`, `qhead`, `vardataLevel` | level-0 units are only on the trail, not clauses: a replay copy must add them |
| heuristics | `activity`, `orderHeap` (heap + indices; history-dependent order), `polarity`, `userPol`, `decision` + `decVars`, `varInc`, `claInc`, clause activities in `ca` | rebuilding the heap changes the decision order |
| variables | `nextVar`, `releasedVars` (still on the trail until `simplify`), `freeVars` (reused by `newVar`) | a replay copy must keep variable numbering |
| limits | `maxLearnts`, `learntsizeAdjustConfl/Cnt`, `simpDBAssigns/Props`, `progressEstimate`, `removeSatisfied`, `ok` | `ok = false` copy |
| budgets | `conflictBudget`/`propagationBudget` are absolute (`conflicts + x`), `asynchInterrupt` | copying budgets without stats changes their meaning |
| options | all public vars, incl. `randomSeed`, which is also the RNG state mutated by `drand` | copy the current seed, not the default |
| results | `model`, `conflict` (`LitSet`), `assumptions` | Copying contract (CaDiCaL): no assumptions |
| proof | `drupFile` sink, `binDrup`, `drupBuf`/`bufLen` pending bytes, `reduceDBCall`, `reducedbLastConfl`, `showInfo`, `csbCompat` | sharing one sink interleaves two proofs; pending bytes belong to the original |
| temporaries | `seen`, `analyzeStack*`, `analyzeToclear`, `addTmp`, `addOc` | sizes only (`seen` must be sized to nVars) |
| SimpSolver | `elimclauses`, `eliminated`, `frozen`, `frozenVars`, `touched`, `nOcc`, `elimHeap`, `useSimplification`, `maxSimpVar`, `elimorder`, `nTouched`, `bwdsubAssigns`, `parsing`, options, stats | after elimination the clauses are only equisatisfiable; `elimclauses` is needed for `extendModel` |
| other | trace sink (`setTraceSink`), `MiniSatSimp` must copy to `MiniSatSimp` | |

## Coverage audit follow-up (2026-10-27)

Closes the audit's gaps B, C and "incremental use". Port stays 1:1 (master 664490d + bugs 1-4;
csb with `csbCompat`); no divergence between port and references was found, so the port's solver
code is unchanged except for `@Volatile`.

### What was done

1. **`asynchInterrupt` `@Volatile`** (MiniSat.kt). Correction to the request: upstream's member is
   a plain `bool asynch_interrupt` (master Solver.h:293, also csb, niklasso 37dc6c6, crystalball), not
   `volatile`. `@Volatile` is a port addition, marked as such in the code: no effect single-threaded
   (traces unchanged), but without it the JIT may hoist the read in `withinBudget()` out of the search
   loop and never see an `interrupt()` from another thread (upstream documents interrupt() as
   "potentially asynchronous"; the CaDiCaL port does the same for its terminate flag).
   Test: `MiniSatInterruptTest` (core and simp: interrupt from a second thread stops a PHP(13,12)
   solve with l_Undef; clearInterrupt + budgeted solve afterwards).
2. **core/Dimacs.h + utils/ParseUtils.h ported** (`Dimacs.kt`, `ParseUtils.kt` in the port):
   `parseDimacs(input: ByteArray | String, solver, strictp = false, out = println)` = `parse_DIMACS`
   / `parse_DIMACS_main` / `readClause`, and `StreamBuffer`, `isEof`, `skipWhitespace`, `skipLine`,
   `parseInt`, `eagerMatch` (not ported, unused by Dimacs.h: `StreamBuffer::position`,
   `isEof(const char*)`, `match`). Adaptations: in-memory bytes instead of a gzFile;
   `printf/fprintf("PARSE ERROR! Unexpected char: %c\n"), exit(3)` -> `DimacsParseError` with the
   same message (`toStderr` says whether upstream printed it to stderr (`parseInt`) or stdout
   (`parse_DIMACS_main`); `%c` of EOF is the byte 0xFF, here `'ÿ'`); strict mode's header
   mismatch is only printed upstream (no exit), so it goes to the `out` sink and parsing goes on.
   `MiniSatShadowDriver.run` now reads CNFs with it (instead of `DimacsCnf`), so Kotlin reads them
   exactly like the C driver. Both drivers got `--strict=0|1` (default 0, as upstream).
   Tests: `MiniSatDimacsLiveTest` (30 crafted inputs: the audit's six cases plus header variants,
   comments, CR LF, `\v \f`, no header, header after clauses, `+1`, `-0`, empty clause/input,
   non-ASCII byte, `12x`, `1-2`, ...; `--simp=0/1` x `--strict=0/1`, master and csb: complete
   stdout incl. `PARSE ERROR!` lines and `s ...`, exit code (3 on error) and the stderr line
   compared live), `MiniSatDimacsTest` (commonTest, the outcomes without the reference).
3. **ksat-common `DimacsCnf` fixed** (bug K1 below). New semantics, picked by the rule "what both
   upstream default parsers agree on; where they disagree the more permissive reading that loses
   nothing": MiniSat `parse_DIMACS` non-strict (its default) and CaDiCaL `read_dimacs` strict = 1
   (its API and app default, `cadical.hpp`), both run on the inputs below
   (`scripts/probe/probe_dimacs_upstreams.py`, main repo):

   | Input | MiniSat | CaDiCaL | DimacsCnf (new) |
   |---|---|---|---|
   | more clauses than the header | reads all | "too many clauses" | reads all |
   | fewer clauses than the header (also `p cnf 1 1` and nothing) | accepted | "clause missing" | accepted |
   | last clause without `0` | PARSE ERROR | "last clause without terminating '0'" | rejected |
   | `p wcnf` | PARSE ERROR | "expected 'c' after 'p '" | rejected |
   | `p  cnf`, `p<tab>cnf` | PARSE ERROR | accepted | accepted |
   | `p cnf3 1` | accepted | "expected space after 'p cnf'" | accepted |
   | `p cnf 3 1 x` | PARSE ERROR | "expected new-line" | rejected |
   | `p cnf 0 0` at EOF without newline | accepted | "expected new-line" | accepted |
   | `p cnf 3` then a line `1 0` | header 3 1, then the empty clause `0`: UNSAT | "expected new-line after 'p cnf 3 1'" | rejected (CaDiCaL's reading: header numbers must be on the header line; MiniSat's reading would silently turn the unit `1` into the clause count) |
   | `p cnf -1 1` | accepted (counts unused) | "expected digit" | accepted, negative count = 0 |
   | `%` tail | PARSE ERROR | "expected digit or '-'" | rejected |
   | `1 2 0 c comment` | accepted | accepted | accepted |
   | `1 c comment` / `2c x` inside a clause | PARSE ERROR | accepted | accepted (comment to end of line) |
   | no header, empty input | accepted | "expected 'c' or 'p'" | accepted |
   | header after clauses, two headers | accepted | "expected digit or '-'" | accepted, `numVars` = the largest |
   | literal beyond the header's variable count | accepted | "literal 5 exceeds maximum variable 1" | accepted, `numVars` covers it |
   | `+1` | accepted | "expected digit or '-'" | accepted |
   | `-0` | end of clause | end of clause | end of clause |
   | `\v`, `\f` as whitespace | accepted | "expected digit or '-'" | accepted (MiniSat's 9..13, 32) |
   | `1 - 2`, `12x` | PARSE ERROR | "expected digit after '-'", "expected white space" | rejected |
   | `1-2` | 1 and -2 | "expected white space after '1'" | 1 and -2 |
   | `99999999999` | int wraps silently (newVar loops ~1e9 times) | "literal too large" | rejected (a wrapped number is a different literal) |

   Errors: `DimacsParseException(line, reason)` (an `IllegalArgumentException`, message `DIMACS parse
   error at line N: ...`). `numVars` = max(header variable counts, largest variable in a clause).
   Note: microSAT's C `parse` reads exactly the header's `m` clauses and sizes its arrays from the
   header; the old DimacsCnf mirrored that (its KDoc said so). The shadow CNFs are well-formed, so
   no shadow test changes. Tests: `DimacsCnfTest` (ksat-common commonTest, 8 tests).
4. **Incremental shadow.** Both C drivers got `--script=<file.ops>` (shared code
   `shadow/minisat-full/driver_script.h`): one solver, operations in order: `add`, `assume`, `solve
   [simp=0|1] [turnoff=0|1]` (`solveLimited`; SimpSolver: do_simp / turn_off_simp), `release`
   (`releaseVar`), `simplify`, `newvar [pol=t|f|u] [dvar=0|1]` (results referenced as `@k`, so a
   variable reused from `free_vars` can be addressed), `polarity`, `decision`, `budget
   conf=<n>|prop=<n>|off`, `interrupt`, `clear-interrupt`, `freeze`, `eliminate [turnoff=0|1]`. Output
   per operation `OP ...`, `RET ...`, `VAR <v>`, after each solve `MODEL ... 0` (undefined as `?v`) or
   `FAILED ... 0` (`conflict` in its order), interleaved with the trace. For `--simp=1` every call
   goes to the SimpSolver member (a C++ user holding a `SimpSolver`). Kotlin mirror:
   `MiniSatShadowDriver.runScript`. Generator: `shadow/tools/gen_minisat_scripts.py` (seeded,
   byte-identical on re-run) -> `shadow/minisat-scripts/`, 22 scripts as 41 files (`.core.ops` for
   `--simp=0`, `.simp.ops` for `--simp=1`; the simp variant freezes every variable referenced after
   the first solve and every `newvar`, as SimpSolver's contract requires): add_after_solve,
   changing_assumptions, failed_cores (PHP(5,4) with selectors), failed_units, release_reuse (reuse
   via free_vars: `VAR 22`, `VAR 21` again in the core run), conf_budget (PHP(7,6), budgets 5 0 20 200
   1000 -> UNKNOWN, then UNSAT), prop_budget, interrupt, polarity_decision, simp_frozen (do_simp,
   simp=0, turnoff=1, adds on frozen vars), simp_eliminate, simp_newvar, random_00 .. random_09 (mixed
   ops). Test: `MiniSatIncrementalShadowTest`, every script x 3 option sets (core runs skip the simp
   option set): 104 runs per reference, complete output compared (no quick limit), master default
   and csbCompat. Results: 0 divergences, nothing to fix.

### Verification (2026-10-27)

- `MiniSatIncrementalShadowTest`: master 104 runs (337,151 lines), csb 104 runs (388,875 lines),
  0 failing.
- `MiniSatDimacsLiveTest`: 120 runs per reference, 0 failing.
- `MiniSatLiveShadowTest` (now parsing with `parseDimacs`): 360 + 360 runs (quick), 0 failing;
  `MiniSatDrupTest`: proofs 310 runs / 282,412,986 bytes, traces 319 runs, bugs 1-4, 0 failing
  (drat-trim check skipped: `DRAT_TRIM` not set); `MiniSatApiTest` 15, `MiniSatSanityTest` 6,
  `MiniSatDimacsTest` 3, `MiniSatInterruptTest` 1 green. Whole `:minisat:jvmTest`: 38 tests, 4
  skipped (golden-file suites without golden traces, drat-trim), 0 failing.
- ksat-common `DimacsCnfTest` 8; `:microsat:jvmTest` (ShadowTraceTest 5, golden suites skipped),
  `KissatSanityTest` 6, `CaDiCaLSanityTest` 6, facade `org.bytefred.ksat.facade.*` 65: green.
- Harness checks (reverted): dropping `releasedVars.push` in `releaseVar` made 2 (csb) / 3 (master)
  script runs fail; making the strict check `cnt != clauses + 1` made 34 Dimacs runs fail per
  reference.

### Bug list additions

| # | Bug | Where | Repro | Fix |
|---|---|---|---|---|
| K1 | `DimacsCnf.parse` (ksat-common, shared by all solvers' tests/benchmarks) stopped after the header's clause count and silently dropped the rest, which can turn UNSAT into SAT; it also accepted a last clause without `0`, `p wcnf`, a `%` tail (as literals), and threw a bare `NumberFormatException` on `1 2 0 c comment` and `IndexOutOfBounds` on a short header | ksat-common `DimacsCnf.kt` (up to 9db30cc) | `DimacsCnf.parse("p cnf 1 1\n1 0\n-1 0\n").clauses.size` == 1 (formula SAT instead of UNSAT) | new parser (item 3 above), `DimacsCnfTest` |

No new upstream bugs. Upstream oddities seen and kept 1:1 in the parser port (not changed, no
failure of the solver itself): `parseInt` wraps on overflow (C signed overflow, UB), so a huge literal
becomes a different variable (or newVar runs ~1e9 times); strict mode reports a header mismatch but
does not stop; `p  cnf` (two blanks) is rejected.
