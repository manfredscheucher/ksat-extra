# minisat-full: instrumented upstream MiniSat (shadow reference)

Reference for a full 1:1 Kotlin port of MiniSat (core `Solver` + `SimpSolver`), built the
same way as `../cadical-full/`. Unlike `../minisat-c/minisat_trace.cc` (a hand transcription
of the core that deviates from upstream, see "Old reference" below), this is the real
upstream solver, unmodified, plus trace prints.

| File | What |
|---|---|
| `upstream/` | verbatim `meelgroup/minisat` (`9a0382d`, the maintained fork; solver code = `niklasso/minisat` `37dc6c6` + compile fixes), never edited, see `upstream/README.md` |
| `trace.patch` | unified diff applied to a copy of `upstream/minisat`; only adds output (no removed lines) |
| `zlib-shim/zlib.h` | replaces `<zlib.h>`: `gzFile` = `FILE*`, `gzread` = `fread` (no zlib needed) |
| `driver.cpp` | small `main`: options, upstream DIMACS parser, `Solver` or `SimpSolver`, verdict |
| `driver_script.h` | the drivers' incremental `--script` mode (also included by `../minisat-master/driver.cpp`) |
| `build_and_trace.sh` | builds `build/minisat_full_trace`; prints one trace, or a determinism summary |
| `build/` | build directory (gitignored via `**/build/`) |

No golden traces are written (disk is tight). The Kotlin side is meant to compare live,
like `FullLiveShadowTest` does for CaDiCaL: start the binary with `LSTRACE=1`, drop the
`s ...` line, compare line by line.

## Build and trace

    bash ksat-extra/shadow/minisat-full/build_and_trace.sh --build-only
    bash ksat-extra/shadow/minisat-full/build_and_trace.sh --trace [driver args]   # one trace to stdout
    bash ksat-extra/shadow/minisat-full/build_and_trace.sh            # determinism summary
    BIG=1 bash ksat-extra/shadow/minisat-full/build_and_trace.sh      # ... including php_10_9

`--trace` rebuilds when the binary is missing or older than the patch, driver, shim or
script, runs the binary with `LSTRACE=1` and drops the `s ...` verdict line; an exit code
other than 10/20/0 is an error. The summary runs every `../cnf/*.cnf` with `--simp=0` and
`--simp=1` twice, requires identical sha256 of the two traces, and prints line count,
verdict and the event counts. Nothing is written outside `build/`.

The script copies `upstream/minisat` to `build/src/minisat`, applies `trace.patch`
(`patch -p1`), and compiles `core/Solver.cc`, `simp/SimpSolver.cc`, `utils/Options.cc`,
`utils/System.cc` and `driver.cpp` (not the `Main.cc` apps) with

    clang++ -O2 -std=c++98 -ffp-contract=off -DNDEBUG -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS

`CXX=...` overrides the compiler. Flags: upstream's `Makefile` release flags are
`MINISAT_REL = -O3 -D NDEBUG` plus `MINISAT_CXXFLAGS = -D __STDC_LIMIT_MACROS -D
__STDC_FORMAT_MACROS`; here `-O2` instead of `-O3`. `-std=c++98` is the dialect the code is
written in. `-ffp-contract=off` forbids fused multiply-add, so every `double` operation
rounds separately as on the JVM (relevant e.g. for `drand` in `mtl/Rnd.h`:
`seed -= q * 2147483647`). Upstream's warnings are hidden with `-w` (drop `-w` to see them).

History: the first version of this reference used `niklasso/minisat` 37dc6c6, which does not
compile with clang (`friend Lit mkLit(Var, bool sign = false)`) and whose `System.cc` does not
compile on macOS (`memUsedPeak()` vs `memUsedPeak(bool)`); it needed `g++ -fpermissive` and a
`memUsedPeak` stub in the driver. The meelgroup fork fixes exactly these (see
`upstream/README.md`), so both workarounds are gone. `trace.patch` regenerated against the
new sources is byte-identical (no hunk touches the changed lines), and every trace has the
same line count as with the niklasso/g++ build.

### zlib

`utils/ParseUtils.h` includes `<zlib.h>`; its `StreamBuffer` calls `gzread`, and
`core/Dimacs.h`'s `parse_DIMACS` takes a `gzFile`. These are the only zlib names in the
compiled code (`gzopen`/`gzdopen`/`gzclose` are only in the Main.cc apps). `zlib-shim/` is
first on the include path, so upstream's parser reads plain DIMACS from a `FILE*` without
zlib. The driver checks `ferror` after parsing (the shim maps a read error to end of file).

## Driver

    build/minisat_full_trace [--simp=0|1] [--strict=0|1] [--<option>=<value> ...] <file.cnf> [<file.assume>]
    build/minisat_full_trace [--simp=0|1] [--<option>=<value> ...] --script=<file.ops>

- `--simp=0` (default): `Minisat::Solver`. `parse_DIMACS`, read assumptions,
  `solveLimited(assumptions)`.
- `--simp=1`: `Minisat::SimpSolver`, as upstream `simp/Main.cc`: `parse_DIMACS`, read
  assumptions, `setFrozen(v, true)` for every assumption variable (upstream's `solve_`
  only freezes assumptions when it runs elimination itself; `eliminate(true)` turns
  simplification off for good, so an assumption variable must be frozen before it), then
  `eliminate(true)`; if `!okay()`: print `RESULT UNSAT` (Main.cc does not call solve in that
  case), else `solveLimited(assumptions)` (do_simp has no effect any more).
- Every other `--<name>=<value>` goes to upstream's own option parser
  (`Minisat::parseOptions(argc, argv, strict=true)`) before the solver is constructed
  (upstream reads the options in the constructor), translated to upstream syntax:
  `-<name>=<value>` for int/double options, `-<name>` / `-no-<name>` for the bool options
  `luby rnd-init elim asymm rcheck` (value `1` / `0`). Names are upstream's:
  core `var-decay cla-decay rnd-freq rnd-seed ccmin-mode phase-saving rnd-init luby rfirst
  rinc gc-frac min-learnts`, simp `asymm rcheck elim grow cl-lim sub-lim simp-gc-frac`.
  Upstream checks the ranges (exit 1). Upstream's parser accepts trailing garbage
  (`-rnd-freq=0.2x` = 0.2), so the driver first requires the value to be a complete number.
  Unknown names: upstream error, exit 1.
- Assumptions file: signed DIMACS literals, whitespace separated, `0` ignored; a variable
  beyond `nVars()` is created with `newVar()` (as `../minisat-c` does).
- Output: trace events (with `LSTRACE`), then after a SAT result
  `MODEL l1 ... ln 0` (with `LSTRACE`; `model[i] == l_True ? i+1 : -(i+1)`, `i < nVars()`,
  an undefined model value is an error), then always `s SATISFIABLE` / `s UNSATISFIABLE` /
  `s UNKNOWN`. Exit code 10 / 20 / 0, 1 on any error.
- `--strict=1`: `parse_DIMACS(in, S, true)` (upstream Main.cc `-strict`): prints `PARSE ERROR!
  DIMACS header mismatch: wrong number of clauses` to stdout when the clause count differs from the
  header, and goes on (upstream does not exit). Malformed input: upstream's parser prints
  `PARSE ERROR! Unexpected char: <c>` (stdout from `parse_DIMACS_main`, stderr from `parseInt`)
  and exits with 3. Kotlin mirror: `parseDimacs` (port, `Dimacs.kt`), checked by
  `MiniSatDimacsLiveTest` on crafted inputs.
- `--script=<file.ops>` (2026-10-27): incremental mode, instead of a CNF. The operations of the
  file run in order on ONE solver (`add`, `assume`, `solve [simp=0|1] [turnoff=0|1]`, `release`,
  `simplify`, `newvar`, `polarity`, `decision`, `budget conf=|prop=|off`, `interrupt`,
  `clear-interrupt`, `freeze`, `eliminate`); every operation is echoed as `OP ...`, results as
  `RET`, `VAR`, `MODEL` (undefined values as `?v`) and `FAILED` (the final conflict after UNSAT).
  Format: `driver_script.h`. Scripts: `../minisat-scripts/` from `../tools/gen_minisat_scripts.py`;
  Kotlin mirror `MiniSatShadowDriver.runScript`, test `MiniSatIncrementalShadowTest`.

## Trace vocabulary

One event per line on stdout, only when the environment variable `LSTRACE` is set (any
value, like `../minisat-c`). `<lit>` is a signed DIMACS literal (internal var v -> v+1).
`:<lits>` is ` :` followed by ` l1 l2 ... lk 0`, the literals in the clause's current stored
order (watch order, so the port must keep the same order). All prints come from
`core/lstrace.h` (added by the patch).

Events of the old core vocabulary (`../minisat-c`, the current Kotlin port), same text:

| Line | Printed in | Meaning |
|---|---|---|
| `DECIDE <lit>` | `Solver::search`, after `newDecisionLevel(); uncheckedEnqueue(next);` | new decision level with decision `<lit>` (also an assumption literal). A dummy level for an already-true assumption prints nothing (as before) |
| `ASSIGN <lit> reason=D` | same place, right after `DECIDE` | the decision |
| `ASSIGN <lit> reason=F` | `Solver::addClause_` (unit after normalisation); `SimpSolver::strengthenClause` (clause became unit and the literal is unassigned, printed just before upstream's `enqueue`) | root-level unit not implied by a stored clause |
| `ASSIGN <lit> reason=C` | `Solver::uncheckedEnqueue` when `from != CRef_Undef` (every propagation, the asserting literal of a learnt clause); `Solver::search` for a learnt unit | implied by a clause / learnt unit |
| `CONFLICT` | `Solver::search`, first statement of the conflict branch | propagate returned a conflict (also at level 0, before returning UNSAT) |
| `RESTART` | `Solver::solve_`, before each `search` call except the first | restart |
| `REDUCE` | `Solver::reduceDB` entry | learnt clause reduction |
| `RESULT UNSAT` | `Solver::solve_` when `!ok` at entry | |
| `RESULT SAT\|UNSAT\|UNKNOWN` | `Solver::solve_` after the final `cancelUntil(0)` | verdict of the search |

New events:

| Line | Printed in | Meaning |
|---|---|---|
| `ASSIGN <lit> reason=P` | `SimpSolver::asymm`, `SimpSolver::implied`, `Solver::implies`: right before their `propagate()`, one line per literal of `trail[trail_lim.last() ..]` | probe assignments (negated clause literals on the temporary level 1); the propagations follow as `reason=C`; all are undone by `cancelUntil(0)` (no event). An early return before `propagate()` (literal already true / false) prints nothing |
| `LEARN level=<bt> :<lits>` | `Solver::search`, after `analyze` | learnt clause (minimised, asserting literal first, `lits[1]` has the highest level), `bt` = backtrack level; also for units |
| `ADD :<lits>` | `Solver::addClause_`, after the clause is stored and attached (size >= 2) | problem clause stored, after upstream's normalisation (sorted, false/duplicate literals removed); parser clauses and SimpSolver resolvents. Satisfied/tautological clauses print nothing, units print `ASSIGN ... reason=F`, the empty clause prints nothing (the solver becomes inconsistent: `RESULT UNSAT` follows) |
| `DEL learnt\|orig :<lits>` | `Solver::removeClause` entry (also reached from `SimpSolver::removeClause`) | every clause deletion: reduceDB, removeSatisfied, subsumption, elimination, strengthening of a binary |
| `TRIM learnt\|orig :<lits>` | `Solver::removeSatisfied`, after the trim loop, only if the clause got shorter | false literals at positions >= 2 removed; `<lits>` after trimming |
| `SIMPLIFY` | `Solver::simplify`, after the early `return true` (`nAssigns() == simpDB_assigns \|\| simpDB_props > 0`) | the clause database pass actually runs (removeSatisfied(learnts), removeSatisfied(clauses) if `remove_satisfied`, checkGarbage, rebuildOrderHeap) |
| `GC core` / `GC simp` | `Solver::garbageCollect` / `SimpSolver::garbageCollect` entry | garbage collection (virtual: with a SimpSolver it is always `GC simp`, also during search after `eliminate(true)`) |
| `START eliminate` / `END eliminate` | `SimpSolver::eliminate` whole function (scope guard: END on any return) | preprocessing |
| `START bwdsub` / `END bwdsub` | `SimpSolver::backwardSubsumptionCheck` whole function | backward subsumption + self-subsuming resolution |
| `SUBSUME :<lits>` | `backwardSubsumptionCheck`, after `c.subsumes(d)` returned `lit_Undef` | `<lits>` = the subsuming clause `c` (for a top-level unit: the dummy unit clause holding that trail literal); the `DEL` of the subsumed clause follows |
| `STRENGTHEN <lit> :<lits>` | `SimpSolver::strengthenClause` entry | literal `<lit>` is removed from the clause `<lits>` (shown before the change). Size 2: `DEL` of the binary follows; if the result is a unit with an unassigned literal, `ASSIGN ... reason=F` follows |
| `ELIM <v> pos=<p> neg=<n>` | `SimpSolver::eliminateVar`, after the grow / clause-limit checks passed, before `eliminated[v] = true` | variable `v` (DIMACS) is eliminated; `p`/`n` = number of occurrences with positive/negative literal. The `DEL`s of all its clauses and the `ADD`s / `ASSIGN F` of the resolvents follow, then `START bwdsub` |
| `START asymm` / `END asymm` | `SimpSolver::asymmVar` whole function | asymmetric branching for one variable (only with `--asymm=1`) |
| `RESULT UNSAT` | driver, `--simp=1` and `!okay()` after `eliminate(true)` | upstream Main.cc does not call solve then |
| `MODEL ...` | driver | see Driver |

Not traced: `cancelUntil` (no BACKTRACK event, as in the old vocabulary), the clause
activity / variable activity values, `extendModel`, `rebuildOrderHeap`, the dummy decision
level of an already-true assumption, `CONFLICT` inside probing (`asymm`/`implied`; it is
visible as the following `STRENGTHEN`), the elimination candidates that are rejected.

Comparing with the old core vocabulary (`../minisat-c` and the earlier core-only Kotlin port):
keep only lines matching `^(DECIDE|ASSIGN|CONFLICT|RESTART|REDUCE|RESULT)` (and `reason=P`
occurs only with `--simp=1`). The full Kotlin port (`MiniSat` + `MiniSatSimp`) emits the
complete vocabulary and is compared line by line, live, by `MiniSatLiveShadowTest` (main repo,
`solver/minisat/src/jvmTest`); see `../../doc/minisat-full-port.md`.

## Results (2026-10-22, clang++ -O2, meelgroup 9a0382d)

Every trace is deterministic (two runs, same sha256; php_10_9 checked too).

| CNF | `--simp=0` lines | `--simp=1` lines |
|---|---|---|
| conflict_sat | 18 | 44 |
| conflict_small | 19 | 20 |
| hard_rand_unsat_60 | 1360 | 1365 |
| php_3_2 | 27 | 54 |
| php_4_3 | 110 | 181 |
| php_5_4 | 535 | 510 |
| php_6_5 | 6193 | 3024 |
| php_7_6 | 40764 | 20954 |
| php_8_7 | 241132 | 232411 |
| php_9_8 | 836750 | 1604138 |
| php_10_9 | 6491362 | 7168716 |
| rand3_20_phase | 115 | 128 |
| rand3_50_phase | 982 | 987 |
| sat_small | 21 | 33 |
| tiny_sat_chain | 14 | 21 |
| tiny_unsat_units | 3 | 5 |
| unsat_small | 6 | 8 |

With default options, `--simp=1` fires `START/END eliminate`, `START/END bwdsub`, `ELIM`
(conflict_sat, php_*, sat_small), `SUBSUME` (conflict_sat, php_4_3, rand3_20_phase),
`STRENGTHEN` (conflict_sat, conflict_small, php_3_2, php_4_3, rand3_20_phase,
tiny_sat_chain), `GC simp`, `TRIM`, `REDUCE` (sat_small: after elimination no clause is
left, `max_learnts` = 0, so `reduceDB` runs once with no learnts). `START asymm` and
`reason=P` need `--asymm=1` (or `--rcheck=1` for `implied`); checked on php_5_4,
conflict_sat, rand3_20_phase.

### Old reference vs upstream (`--simp=0`)

Core-vocabulary lines (the filter above) of this reference against `../minisat-c/minisat_trace`
(which the Kotlin port matches at L1, ShadowTraceFilesTest): identical on conflict_sat,
conflict_small, hard_rand_unsat_60, php_3_2, php_5_4, php_6_5, rand3_20_phase,
rand3_50_phase, tiny_sat_chain, tiny_unsat_units, unsat_small and all four
`../cnf-assume/` cases; different on sat_small, php_4_3, php_7_6, php_8_7, php_9_8 (php_10_9
not compared). sat_small and php_4_3: after a learnt unit at level 0 upstream skips
`simplify` (`simpDB_props > 0`), the old reference runs it (rebuildOrderHeap changes the
next decision). php_7_6: the old reference does a `REDUCE` where upstream does not yet; before that point
there is no level-0 unit and no extra `SIMPLIFY`, and the only difference in the condition
is the truncation (old: `(int)learnts.size() - nAssigns() >= (int)max_learnts`; upstream
compares the int difference against the `double` `max_learnts`). php_8_7 / php_9_8 not
analysed. So the earlier core-only Kotlin port (which followed the old reference) did not
match upstream on these five CNFs; the full port does (MiniSatLiveShadowTest).

## How trace.patch was made

`diff -ruN` (timestamps and `diff` lines stripped) between `upstream/minisat` and a copy
edited by the throwaway helper `scripts/probe/make_minisat_full_trace_patch.py` (top-level
repo; every edit inserts lines next to an exact anchor that must occur once). It adds the
new header `core/lstrace.h`, includes it from `core/Solver.h`, and adds only prints, plus
one read-only local (`lstrace_size` in `removeSatisfied`). Every added line ends in
`// LSTRACE`; the patch has no removed lines.
