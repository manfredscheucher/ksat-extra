# Incremental / IPASIR support in the ports

Status of the incremental (IPASIR-style) interface across the Kotlin solver ports.
Work lives on the `incremental` branch of each repo (main stays stable).

> **Update 2026-10-22:** the facade's `Solver.CADICAL` runs the FULL CaDiCaL 2.1.3 port
> (class `CaDiCaL`, see `cadical-full-port.md`). It behaves exactly like upstream: assumptions are
> reset and the trail restored lazily, `failed()` runs upstream's lazy `failing()`, lucky phases /
> local search / inprocessing are on by default. The facade tests pass on the full port; the two
> forced-phase tests now only check what upstream guarantees (Manfred, 2026-10-22: "cadical 1:1
> übernehmen so wies original is"). The earlier CaDiCaL core port (CDCL core only, all
> inprocessing off), for which the CaDiCaL work below was first done, was removed the same day
> ("Alten CaDiCaL-Kernport löschen"). The CaDiCaL parts below describe the full port; what only
> applied to the core port is kept as notes marked *historical (core port)*.

## What was asked

Port the incremental pieces that are interesting from a Ksat point of view:
- add clauses after a solve (IPASIR `add`), and have them take effect on the next solve
- assumptions (IPASIR `assume` + `solve`), already present before this work
- the failed-assumption core (IPASIR `failed`)

 Porting every CaDiCaL parameter / all of kissat's inprocessing was explicitly dropped:
a Kotlin port is ~1.3x slower than C/C++, so full feature parity is not worth it. The
value is a faithful, trace-verifiable core with the incremental API on top.
(Superseded for CaDiCaL on 2026-10-21: "alles portieren für cadical", see `cadical-full-port.md`.)

Hard rule throughout: translate existing upstream code 1:1, line by line. Do not invent.
Where an upstream branch has no counterpart in a core-only port (kissat; historically the
CaDiCaL core port: proof/LRAT, chrono, ILB, constraint API), it is omitted as vacuous, the same
reduction the ports already make elsewhere, confirmed by fresh review each time. The full
CaDiCaL port has every branch.

## add-clause-after-solve + post-solve unit (CaDiCaL + kissat)

Bug: a clause added after a `solve()` did not take effect; a unit added after a SAT re-solve
was re-decided (CaDiCaL) or crashed the decision-queue walk (kissat).

Root cause: upstream processes original clauses only at the root. CaDiCaL
`add_new_original_clause` (clause.cpp) does `if (level) backtrack();` before touching the
clause; kissat imports originals only while at level 0. The ports did not — a clause added
over a dirty level>0 trail (left by the previous solve) put a unit at the wrong trail/queue
position, so the next `backtrack(0)` unassigned it (CaDiCaL) or `decide()` walked off the
queue (kissat, `lit(-1) = -2` → out of bounds).

Fix (kissat, and the removed CaDiCaL core port), faithful to upstream:
- restore to level 0 at (re-)solve entry (mirrors CaDiCaL `already_solved`; kissat enters
  search at level 0)
- restore to level 0 before importing an original clause (mirrors the two upstream import
  paths above), so a post-solve unit lands at level 0 and survives

CaDiCaL today: the full port translates `add_new_original_clause` and the solve entry 1:1, so
it has upstream's own lazy backtrack; no port-specific fix is involved.

kissat extra: upstream `decide.c` guards the queue walk with `assert(solver->unassigned)` and
`assert(!DISCONNECTED(res))`. The port had dropped these, so the broken invariant surfaced as
an opaque array-index crash instead of a clear failure. Restored as loud `check()`s.

Spec test: `ksat/src/commonTest/.../AddClauseAfterSolveTest.kt` (MiniSat/CaDiCaL/kissat):
block-and-re-solve enumeration, a non-trivial multi-model count against a MiniSat reference,
the post-solve unit case, and plain double-solve stability.

## failed-assumption core — `failed(lit)`

Interface: `SatSolver.failed(lit)` (default throws `UnsupportedOperationException`; facade `Ksat`
delegates). After an UNSAT solve under assumptions, `failed(lit)` reports whether the signed
DIMACS assumption `lit` is in the core, as in IPASIR `ipasir_failed`. After SAT, or when the
UNSAT does not depend on any assumption, it returns false.

CaDiCaL: the full port translates `Internal::failing()` (assume.cpp) completely, including the
LRAT and constraint branches, and `failed()` calls it lazily exactly as upstream (only in the
unsatisfied state, guarded by `marked_failed`). A root UNSAT found during search under
assumptions gives an empty core, as upstream.

*Historical (core port):* the core port translated only the non-LRAT path (proof/LRAT and the
constraint branch omitted as vacuous) and computed the core eagerly at the UNSAT exit, because
it backtracked to level 0 right after the solve, which destroys the state `failing()` needs.

MiniSat: ported 1:1 from `Solver::analyzeFinal` and the `conflict` vector (Solver.cc 2.2.0),
called where upstream calls it (falsified assumption in `search`), `conflict.clear()` at solve
start and `ok = false` on an assumption-free UNSAT, as in `solve_()`. `conflict` holds the
negations of the failed assumptions, so `failed(lit)` is true iff `~lit` is in it.

kissat: not ported. kissat 4.0.x has no failed-assumption API upstream (no incremental solving at
all, `kissat_require(!searches, ...)`); there is nothing to translate. microsat has no
assumptions. Both keep the throwing default.

Spec test: `ksat/src/commonTest/.../FailedAssumptionsTest.kt` (CaDiCaL + MiniSat).

## IPASIR-UP — external user propagators (CaDiCaL only)

Interface (ksat-common `ExternalPropagator.kt`): `ExternalPropagator` is a transcription of
cadical.hpp's class (camelCase names, signed DIMACS lits; `std::vector<int>` -> `IntArray`, the
`bool &is_forgettable` out-parameter -> `OutBoolean`). `ExternalPropagation` is the optional
host capability with the Solver IPASIR-UP block: connect/disconnect, add/remove/reset observed
vars, `isDecision`, `forceBacktrack`. The facade `Ksat` implements it and throws for solvers that
don't host propagators.

CaDiCaL: the full port translates external_propagate.cpp and every IPASIR-UP hook upstream has,
including `private_steps` (lucky/local search/lookahead), ILB/tainted literals, `renotify_*`,
elimination/extend and the LRAT/proof branches, with upstream default options (chrono on).

*Historical (core port):* the core port only had the hooks in the functions it ported (cdcl loop,
decide/ask_decision, backtrack/notify_backtrack, analyze, minimize, failing, reduce, the
`from_propagator` path of add_new_original_clause, external_check_solution), with chrono off.

Upstream behaviour kept on purpose (decision with Manfred, 2026-10-20: follow upstream; only
deviate for an upstream bug that can be isolated and reproduced):
- `addObservedVar` without a connected propagator is a no-op, as in external.cpp: there is no
  propagator to observe for, and connect starts with no observed vars. Not a bug.
- `failed()` is only allowed in the unsatisfied state (solver.cpp REQUIREs it): after SAT, or
  after an `addClause` following the UNSAT, CaDiCaL's `failed()` throws. MiniSat has no such guard
  upstream and returns false there.
- API calls from inside a propagator callback (`addClause`, `solve`, `failed`, removing observed
  vars, connect/disconnect) throw, mirroring upstream's REQUIRE_VALID/READY_STATE.

*Historical (core port):* its eager `backtrack(0)` after `solve(assumptions)` delivered
`notifyBacktrack(0)` at the end of that solve. The full port backtracks lazily at the next
solve/add, as upstream.

MiniSat, kissat, microsat: no IPASIR-UP upstream, nothing to translate.

Spec test: `ksat/src/commonTest/.../ExternalPropagatorTest.kt`, written independently of the
implementation from cadical.hpp and mobical's `MockPropagator`: lazy clause provider via model
rejection, eager propagation with reason clauses, notification/trail-mirror consistency,
`cbDecide` + `isDecision`, lazy propagators, disconnect, misuse, incremental reuse with
assumptions. Expected verdicts come from brute force.

## Incremental enumeration

`enumerateModels(..., incremental = true)` was MINISAT-only because CaDiCaL/kissat could not add
clauses after a solve. That is fixed, so it is now allowed for MINISAT, CADICAL and KISSAT;
MICROSAT still throws (see TODO.md).

## Verification per step

- facade tests green (add-after-solve × 3 solvers; failed-core × CaDiCaL cases)
- shadow L1 single-solve + assume traces byte-for-byte for MiniSat, CaDiCaL and kissat (the
  incremental code never fires without a propagator / post-solve add). Historical for CaDiCaL:
  those were the core port's golden suites; the full port is checked by `FullShadowTraceTest`,
  `FullLiveShadowTest` (incl. `cnf-assume/`) and `FullProofTest` (see `cadical-full-port.md`)
- found on the way: the MiniSat shadow suite and the CaDiCaL/kissat assume suites had been
  skipping silently (their reference-trace dirs were never generated). Regenerated with the
  existing `shadow/tools/regen_golden_*` scripts; all now pass at L1.
- independent fresh reviewers on each change: all FAITHFUL / FAITHFUL-WITH-NITS, nits addressed

## Forced phases and fixed-assignment listener (CaDiCaL only)

Not IPASIR-UP, but the remaining small pieces of CaDiCaL's incremental API, ported the same way:
- `phase(lit)` / `unphase(lit)` (ksat-common `ForcedPhases`): `phases.forced`, consulted first in
  `decide_phase` (decide.cpp). The full port also has `opts.forcephase` and `force_saved_phase`
  (lucky/walk), which the core port left out.
- `FixedAssignmentListener` + `connectFixedListener` / `disconnectFixedListener`
  (ksat-common `FixedListening`): `mark_fixed` notifies the listener from every upstream call
  site. Units fixed before connecting are not replayed, as upstream.

Spec test: `ksat/src/commonTest/.../PhaseAndFixedListenerTest.kt`. With the full port it only checks
upstream guarantees (verdict unchanged, model valid, `phase` creates the variable); the exact
model is not pinned because upstream's lucky phases may find another one first.

## Shadow tests without ksat-extra

ksat-extra is optional, so the main repo's tests must pass without it (Manfred, 2026-10-20). When
ksat-extra or its generated reference traces are missing, the shadow suites are reported as
skipped (visible in the normal Gradle output, with how to enable them). Only an inconsistent,
half-generated state (some traces present, others missing) fails.
