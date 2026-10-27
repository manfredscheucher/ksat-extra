# minisat-master: instrumented MiniSat master (DRUP/DRAT, rdb-at), default reference

Reference for the Kotlin MiniSat port's default target (since 2026-10-27): `meelgroup/minisat`
branch `master` (664490d, 2020) with four upstream bugs fixed (`fixes.patch` + `-DMASTER_FIXES`
in the driver; bug list in `../../doc/minisat-full-port.md`). The raw master builds are kept for
the bug repros. `../minisat-full/` (csb 9a0382d) is the reference for the port's
`csbCompat = true` switch and is not touched by this directory.

| File | What |
|---|---|
| `upstream/` | verbatim export of master 664490d (`minisat/` + `LICENSE`), never edited; commit, relation to csb and sha256 per file in `upstream/README.md` |
| `trace.patch` | the trace prints of `../minisat-full/trace.patch` (same events, same text), re-anchored for the clang-formatted master sources; only adds lines. Made with `scripts/probe/make_minisat_master_trace_patch.py` (main repo; reuses the csb helper's edit list, 6 anchors adapted) |
| `fixes.patch` | the upstream bug fixes 1, 2 and 4 (every changed line marked `// FIX n`), applied after `trace.patch` for the fixed builds |
| `ascii.patch` | removes master's `#define BIN_DRUP` from `core/Solver.h` (only for the ASCII builds) |
| `driver.cpp` | `../minisat-full/driver.cpp` + `--drup`, `--show-info` (see below); bug fix 3 (proof buffer flush at the end) with `-DMASTER_FIXES` |
| `build_and_trace.sh` | builds both binaries; `--trace`, `--proof bin|ascii`, determinism summary |
| `build/` | build directory (gitignored) |

The zlib shim is shared: `../minisat-full/zlib-shim/`. No golden traces or proofs are written.

## Build

    bash ksat-extra/shadow/minisat-master/build_and_trace.sh --build-only
    bash ksat-extra/shadow/minisat-master/build_and_trace.sh --trace --simp=0 --rdb-at=7 x.cnf
    bash ksat-extra/shadow/minisat-master/build_and_trace.sh --proof bin --simp=1 x.cnf | xxd | head
    bash ksat-extra/shadow/minisat-master/build_and_trace.sh     # determinism summary over ../cnf

Four binaries from the same sources: `build/minisat_master_trace` (fixed; as master `BIN_DRUP`
defined in Solver.h, binary proofs), `build/minisat_master_trace_ascii` (fixed, with
`ascii.patch`: the upstream `#else` branches, ASCII proofs), and the same two without the fixes,
`build/minisat_master_raw_trace` / `build/minisat_master_raw_trace_ascii`. `--trace` / `--proof`
and the summary use the fixed builds. Compiled files: `core/Solver.cc`, `simp/SimpSolver.cc`,
`utils/Options.cc`, `driver.cpp`. Flags as `../minisat-full` plus one define:

    clang++ -O2 -std=c++98 -ffp-contract=off -DNDEBUG -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS -Dfwrite_unlocked=fwrite

Why the deviations from the csb build (master itself compiles with clang otherwise):

- `-Dfwrite_unlocked=fwrite`: `binDRUP_flush` calls `fwrite_unlocked`, a glibc extension that
  macOS does not have (compile error). Same signature, same bytes (single-threaded driver).
- `utils/System.cc` is not compiled: master's version has the old `memUsedPeak()` /
  `memUsedPeak(bool)` mismatch (meelgroup fixed it only on the csb line), which clang rejects on
  macOS. The only reference from the linked code is `Solver::printStats()` (never called by the
  driver); `driver.cpp` defines `memUsedPeak(bool)` as a stub that fails loudly.

No upstream source is patched for the build itself; `trace.patch` only adds prints,
`ascii.patch` only removes the `BIN_DRUP` define, `fixes.patch` holds the bug fixes (fixed builds
only).

## Driver

    build/minisat_master_trace [--simp=0|1] [--drup=0|1|devnull] [--show-info=0|1] [--strict=0|1]
                               [--<option>=<value> ...] <file.cnf> [<file.assume>]
    build/minisat_master_trace [--simp=0|1] [--show-info=0|1] [--<option>=<value> ...] --script=<file.ops>

Everything of `../minisat-full/README.md` ("Driver") holds; `--rdb-at=k` is an ordinary upstream
core option, and so do `--strict` and the incremental `--script` mode (shared code:
`../minisat-full/driver_script.h`; `--script` refuses `--drup`). New:

- `--drup=1`: `drup_file = stdout`, as master's `simp/Main.cc -drup`. The proof is the only thing
  on stdout (LSTRACE must be unset, the verdict goes to stderr, Main.cc's `c DRUP proof
  generation` message is not printed). As in simp/Main.cc: `SimpSolver::parsing = true` while the
  CNF (and assumptions) are read, `false` before `eliminate(true)`; after an UNSAT result
  (eliminate made the solver inconsistent, or solve returned `l_False`) the final empty clause is
  written (`fputc('a'); fputc(0)` binary, `"0\n"` ASCII). master's core/Main.cc has no proof
  option; `--simp=0` does the same as simp/Main.cc.
- `--drup=devnull`: proof generation on, written to `/dev/null` (traces with proof code active).
- `--show-info=1`: `S.show_info = 1` (simp/Main.cc `-show-info`). Upstream then prints a
  `c [reduceDB] ...` line per reduceDB call to stdout; `--trace` drops these lines.

## Observations

- Raw master: binary proofs go through a static 2 MB buffer, written only when more than 1 MB is
  pending after a clause or at the end of `solve_` with `l_False`; simp/Main.cc never flushes, so
  when `eliminate` proves UNSAT the proof is just the final `a 0` (php_3_2 `--simp=1`), and SAT
  runs write nothing (bug 3). The raw ASCII build crashes (SIGSEGV, exit 139) without `--drup` at
  the first trimmed clause (bug 1). `--rdb-at=k` without `--show-info=1` runs reduceDB before every
  decision once `conflicts >= k` (bug 2). `--rcheck=1 --simp=1` answers SAT on UNSAT instances
  (bug 4).
- Master's default behaviour (no proof, rdb-at 0) differs from csb only with `--simp=1`: 333d3ef
  deletes the eliminated variable's clauses after adding the resolvents, which changes the
  elimination order (traces of conflict_sat and php_3_2 .. php_8_7 differ from `../minisat-full`;
  `--simp=0` traces are identical on every `../cnf` CNF up to php_8_7).
