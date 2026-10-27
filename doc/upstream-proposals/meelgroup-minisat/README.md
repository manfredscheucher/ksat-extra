# Upstream proposals: meelgroup/minisat

Drafts only, nothing has been posted. Manfred decides whether any of this goes upstream.

Found while porting MiniSat to Kotlin (bug list and background:
`ksat-extra/doc/minisat-full-port.md`, section "Bug list"). All four bugs are in
`meelgroup/minisat` branch `master` at 664490d (2020-07-11).

## Branches (state of the local checkout `~/github/minisat-meelgroup`)

| Branch | Last commit | What it is |
|---|---|---|
| `csb` (default branch, per local origin/HEAD) | 9a0382d, 2026-03-14 | niklasso MiniSat 37dc6c6 + build/CI fixes. No DRUP, no rdb-at, no 333d3ef. Active (CI, releases). |
| `master` | 664490d, 2020-07-11 | 37dc6c6 + Arijit Shaw's DRUP/DRAT, show-info, rdb-at commits. Untouched since 2020. |
| `crystalball` | 96ce818, 2025-09-21 | Research branch forked from master at a19dbf7 (CrystalBall data generation, SQLite, ML reduceDB). |

`csb` has none of the affected code: no `drup_file`/`reducedb_last_confl` at all, and
`eliminateVar`/`substitute` still remove the old clauses before adding the new ones, so
`-rcheck` is sound there (checked: stock csb build answers UNSAT on the bug-04 repro). None of
the four applies to csb.

## Overview

| # | Bug | Affected | Already fixed elsewhere? | Proposal | Recommendation |
|---|---|---|---|---|---|
| 01 | `minisat_core` segfaults when clauses get trimmed without a proof file (needs > 1 MB of trimmed clauses with the default `BIN_DRUP`) | master | yes: crystalball 742f095 (2020-07-19), `if (drup_file && trimmed && ...)` | issue + PR: backport the crystalball one-liner | low value: master is dead since 2020; fixed on crystalball in 742f095 (2020-07-19), about 3 weeks after 6b0d7ff introduced it and 8 days after master's last commit. Only worth it bundled with 03/04. |
| 02 | `-rdb-at=k` reduces before every decision unless `-show-info=1` | master | yes: crystalball 3ae6935 + 6b4f821 (separate `last_conflicts` counter set in `search()`) | issue + PR: move one line (same behaviour as crystalball's fix) | same as 01: already known and fixed on the live research branch, skip or bundle. |
| 03 | Binary DRUP proof is just `a 0` when `eliminate()` proves UNSAT (buffer never flushed in simp/Main.cc) | master, crystalball (same code, not run there) | no | issue + PR: make `binDRUP_flush` public, call it before the final `a 0` (alternative, not chosen: flush in `SimpSolver::eliminate`/`Solver::solve_` instead, also covers API users; see ISSUE) | the most useful one for anyone using master's proofs; still a niche (master + binary proof + UNSAT by simplification). |
| 04 | `-rcheck` answers SAT on UNSAT formulas (resolvents dropped as "implied" while antecedents are still present) | master, crystalball (same code, patch needs a rebase) | no | issue + PR: skip the rcheck for resolvents/substituted clauses | real wrong answer, but `-rcheck` is off by default and "costly". Worth reporting together with 03. |

Honest overall view: the active branch (`csb`) is not affected by any of them. `master` looks
abandoned since 2020; its DRUP work continued on `crystalball`, where 01 and 02 are already
fixed. If anything gets sent, the suggestion is ONE issue (or one PR) against `master` that lists
03 and 04 with their repros, mentions that crystalball still has the same code, and asks whether
master should get 742f095 (01) and the rdb-at fix (02) too. Four separate issues on a dead branch
would most likely just sit there. Sending nothing is also a reasonable choice: the Kotlin port
already has all four fixes and documents them.

## Files

| Path | What |
|---|---|
| `00-combined/ISSUE.md` | the recommended single issue (03 + 04, question about 01/02). |
| `NN-*/ISSUE.md` | per-bug issue texts (building blocks, or to send separately). |
| `NN-*/fix.patch` | minimal fix against master 664490d, `git apply` on a clean `git archive origin/master` export. |
| `NN-*/repro.cnf` | the repro formula (02: pigeonhole 9 into 8, 03/04: pigeonhole 3 into 2). 01 generates its 2.4 MB input inline. |
| `reproduce.sh` | builds stock master and stock+each patch with upstream CMake in a temp dir, runs every repro, deletes the build. |
| `drup_check.py` | tiny forward DRUP checker (used for 03; no drat-trim installed here). |
| `macos-build.patch` | local macOS build fix only, not a proposal (see below). |

Relation to `ksat-extra/shadow/minisat-master/fixes.patch`: fixes 01 and 02 are the same lines.
04 is the same behaviour written differently (a `bool rcheck = true` parameter instead of
toggling `use_rcheck` around the calls). 03 was fixed only in the shadow driver there; the
proposal fixes simp/Main.cc itself.

## Reproduce (local, ~16 s, no network)

    bash ksat-extra/doc/upstream-proposals/meelgroup-minisat/reproduce.sh          # all four
    bash ksat-extra/doc/upstream-proposals/meelgroup-minisat/reproduce.sh 3 4      # some

It reads `~/github/minisat-meelgroup` with `git archive origin/master` (override with
`MINISAT_REPO=...`, `REF=...`), never writes to that checkout. Result of the last run
(2026-10-27, macOS, Apple clang, CMake 4.4):

| # | Stock master | Stock + fix.patch |
|---|---|---|
| 01 | `minisat_core trim.cnf`: exit 139 (SIGSEGV) | exit 10, SATISFIABLE |
| 02 | conflicts with `-rdb-at=2000`, show-info 0 / 1: 226823 / 43589 | 43589 / 43589 |
| 03 | `-drup-file` proof: 2 bytes, invalid (empty clause not RUP) | 93 bytes, 24 steps, valid |
| 04 | `-rcheck`: SATISFIABLE (exit 10), model breaks `-2 -4` | UNSATISFIABLE (exit 20) |

Manual equivalent for one build:

    mkdir -p /tmp/mm
    git -C ~/github/minisat-meelgroup archive origin/master | tar -x -C /tmp/mm
    cd /tmp/mm && git apply <path>/macos-build.patch          # macOS only
    git apply <path>/04-rcheck-elim-unsound/fix.patch          # fixed build only
    mkdir b && cd b
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
             -DSTATIC_BINARIES=OFF -DCMAKE_CXX_FLAGS=-Dfwrite_unlocked=fwrite
    make minisat_core minisat_simp                             # binaries: minisat_core, minisat

Build notes (none of them changes solver logic):

- `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`: CMake 4 refuses master's old `cmake_minimum_required`
  (any OS with a current CMake).
- macOS only: `fwrite_unlocked` (called by `binDRUP_flush`) is glibc-only, hence
  `-Dfwrite_unlocked=fwrite`; master's non-Linux `memUsedPeak()` definitions in
  `utils/System.cc` don't match the `memUsedPeak(bool)` declaration (`macos-build.patch`;
  csb has this fixed, stock csb builds on macOS); no static libc, hence `-DSTATIC_BINARIES=OFF`.
- On Linux stock master should build without these (glibc has `fwrite_unlocked`, the Linux
  `memUsedPeak(bool)` matches); not tested here.

These build breaks could be one more small upstream note, but they are not proposed here.
