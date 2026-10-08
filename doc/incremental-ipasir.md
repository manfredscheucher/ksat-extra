# Incremental / IPASIR support in the ports

Status of the incremental (IPASIR-style) interface across the Kotlin solver ports.
Work lives on the `incremental` branch of each repo (main stays stable).

## What was asked

Port the incremental pieces that are interesting from a Ksat point of view:
- add clauses after a solve (IPASIR `add`), and have them take effect on the next solve
- assumptions (IPASIR `assume` + `solve`), already present before this work
- the failed-assumption core (IPASIR `failed`)

 Porting every CaDiCaL parameter / all of kissat's inprocessing was explicitly dropped:
a Kotlin port is ~1.3x slower than C/C++, so full feature parity is not worth it. The
value is a faithful, trace-verifiable core with the incremental API on top.

Hard rule throughout: translate existing upstream code 1:1, line by line. Do not invent.
Where an upstream branch has no counterpart in the core-only port (proof/LRAT, external
propagator, chrono, ILB, constraint API), it is omitted as vacuous — the same reduction the
ports already make elsewhere, confirmed by fresh review each time.

## add-clause-after-solve + post-solve unit (CaDiCaL + kissat)

Bug: a clause added after a `solve()` did not take effect; a unit added after a SAT re-solve
was re-decided (CaDiCaL) or crashed the decision-queue walk (kissat).

Root cause: upstream processes original clauses only at the root. CaDiCaL
`add_new_original_clause` (clause.cpp) does `if (level) backtrack();` before touching the
clause; kissat imports originals only while at level 0. The ports did not — a clause added
over a dirty level>0 trail (left by the previous solve) put a unit at the wrong trail/queue
position, so the next `backtrack(0)` unassigned it (CaDiCaL) or `decide()` walked off the
queue (kissat, `lit(-1) = -2` → out of bounds).

Fix (both solvers), faithful to upstream:
- restore to level 0 at (re-)solve entry (mirrors CaDiCaL `already_solved`; kissat enters
  search at level 0)
- restore to level 0 before importing an original clause (mirrors the two upstream import
  paths above), so a post-solve unit lands at level 0 and survives

kissat extra: upstream `decide.c` guards the queue walk with `assert(solver->unassigned)` and
`assert(!DISCONNECTED(res))`. The port had dropped these, so the broken invariant surfaced as
an opaque array-index crash instead of a clear failure. Restored as loud `check()`s.

Spec test: `ksat/src/commonTest/.../AddClauseAfterSolveTest.kt` (MiniSat/CaDiCaL/kissat):
block-and-re-solve enumeration, a non-trivial multi-model count against a MiniSat reference,
the post-solve unit case, and plain double-solve stability.

## failed-assumption core — `failed(lit)`

Interface: `SatSolver.failed(lit)` added (default throws `UnsupportedOperationException`;
facade `Ksat` delegates). After an UNSAT solve under assumptions, `failed(lit)` reports
whether the signed DIMACS assumption `lit` is in the core (the jointly-inconsistent subset),
as in IPASIR `ipasir_failed`.

CaDiCaL: ported 1:1 from `Internal::failing()` (assume.cpp), non-LRAT path only — the three
cases (root-falsified unit, clashing pair, min-level `first_failed` + BFS over the implication
graph collecting the full assumption core). Proof/LRAT, external-reason, and the constraint
branch are omitted as vacuous; the external→internal var map is the identity here (DIMACS var
N == internal idx N), so `e2i`/`externalize` are no-ops.

Adaptation forced by the port's architecture: upstream `failed()` is lazy, but the port's
`solve(assumptions)` backtracks to level 0 immediately after the solve returns (so the same
instance is reusable), which destroys the level/reason/trail state `failing()` needs. So the
port computes the core eagerly at the UNSAT exit, before the rollback, and stores the failed
bits; `failed(lit)` reads them. Root-level UNSAT that is independent of assumptions (empty
formula / root-propagation conflict) correctly yields an empty core (no assumption is
falsified on the trail), matching IPASIR.

kissat: NOT ported. kissat 4.0.x has no failed-assumption / UNSAT-core API upstream (it does
not support incremental solving at all — `kissat_require(!searches, ...)`). There is nothing
to translate 1:1, and inventing one is out of scope. kissat's `failed()` therefore throws the
interface default. (Decision made explicitly with the user.)

Spec test: `ksat/src/commonTest/.../FailedAssumptionsTest.kt` (CaDiCaL only): unit core,
clashing pair, multi-assumption core via implication, false-after-SAT, core-reset-between-solves.

## Verification per step

- facade tests green (add-after-solve × 3 solvers; failed-core × CaDiCaL cases)
- shadow L1 single-solve + assume traces still byte-for-byte for CaDiCaL and kissat (the
  incremental changes never fire on a single-solve run, so reference traces are unaffected)
- independent fresh reviewers on each change: all FAITHFUL / FAITHFUL-WITH-NITS, nits addressed

## Deferred

- IPASIR-UP (user propagators): large (`external_propagate.cpp`), needs e2i/i2e mapping
  infrastructure the core ports do not have. Not started.
