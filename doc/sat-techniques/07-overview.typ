#import "../lib/template.typ": note, warn, example, where

= Overview: who has what

One page to look things up. "Upstream" columns say whether the original solver has the
technique (checked against the source trees: CaDiCaL 2.1.3, kissat 4.0.x, MiniSat 2.2.0, with
the file that implements it). The last column says whether the ksat Kotlin ports have it.
"core" means MiniSat's `core/Solver.cc`, "simp" its optional `simp/SimpSolver.cc` layer.
"all three" in the last column means the MiniSat, CaDiCaL and kissat ports (MicroSAT has none of
these techniques beyond plain CDCL).

#let y = sym.checkmark
#let n = [–]

== The CDCL loop and heuristics (chapters 1–3)

#table(
  columns: (auto, auto, auto, auto, auto),
  align: (left, center, center, center, left),
  [*Technique*], [*MiniSat*], [*CaDiCaL*], [*kissat*], [*ksat ports*],
  [Unit propagation, watched literals], [#y core], [#y `propagate.cpp`], [#y `propsearch.c`, `proplit.h`], [all three],
  [1-UIP conflict analysis], [#y core], [#y `analyze.cpp`], [#y `analyze.c`], [all three],
  [Recursive minimization], [#y core], [#y `minimize.cpp`], [#y `minimize.c`], [all three],
  [Shrinking], [#n], [#y `shrink.cpp`], [#y `shrink.c`], [CaDiCaL],
  [Chronological backtracking], [#n], [#y (allowed by default)], [#y (allowed by default)], [CaDiCaL],
  [On-the-fly strengthening (OTFS)], [#n], [#y `analyze.cpp`], [#y `deduce.c`, `strengthen.c`], [CaDiCaL],
  [VSIDS / EVSIDS], [#y core], [#y `score.cpp`], [#y heap], [all three],
  [VMTF queue], [#n], [#y `queue.cpp`], [#y queue], [CaDiCaL, kissat],
  [Phase saving], [#y core], [#y `phases.cpp`], [#y `phases.c`], [all three],
  [Target / best phases], [#n], [#y], [#y], [CaDiCaL, kissat],
  [Stable / focused modes], [#n], [#y `restart.cpp`], [#y `mode.c`], [CaDiCaL, kissat],
  [Luby / reluctant restarts], [#y core], [#y], [#y `restart.c`], [all three],
  [Glucose-style EMA restarts], [#n], [#y `ema.cpp`], [#y], [CaDiCaL, kissat],
  [Trail reuse on restart], [#n], [#y], [#y], [CaDiCaL, kissat],
  [Rephasing], [#n], [#y `rephase.cpp`], [#y `rephase.c`], [CaDiCaL],
  [Reorder], [#n], [#n], [#y `reorder.c`], [not ported],
  [Warmup], [#n], [#n], [#y `warmup.c`], [not ported],
  [Lucky phases], [#n], [#y `lucky.cpp`], [#y `lucky.c`], [CaDiCaL],
  [Local search (walk)], [#n], [#y `walk.cpp`], [#y `walk.c`], [CaDiCaL],
  [Lookahead / cubing], [#n], [#y `lookahead.cpp`], [#n], [CaDiCaL],
  [LBD / glue tiers + reduce], [activity-based], [#y `reduce.cpp`], [#y `reduce.c`, `tiers.c`], [all three (CaDiCaL as upstream; MiniSat, kissat own variant)],
  [Garbage collection], [#y core], [#y `collect.cpp`], [#y `collect.c`], [MiniSat, CaDiCaL (upstream layout); kissat own layout],
  [Variable compaction], [#n], [#y `compact.cpp`], [#y `compact.c`], [CaDiCaL],
)

== Simplifying the formula (chapters 4–5)

#table(
  columns: (auto, auto, auto, auto, auto),
  align: (left, center, center, center, left),
  [*Technique*], [*MiniSat*], [*CaDiCaL*], [*kissat*], [*ksat ports*],
  [Subsumption, strengthening], [#y simp], [#y `subsume.cpp`], [#y `forward.c`], [MiniSat (simp), CaDiCaL],
  [Bounded variable elimination], [#y simp], [#y `elim.cpp`], [#y `eliminate.c`], [MiniSat (simp), CaDiCaL],
  [Fast elimination (fastel)], [#n], [#n], [#y `fastel.c` (off by default, preprocessing only)], [not ported],
  [Gate / definition detection], [#n], [#y `gates.cpp`], [#y `gates.c`, `ands.c`, `ifthenelse.c`, `definition.c`, `equivalences.c`], [CaDiCaL],
  [Blocked clause elimination], [#n], [#y `block.cpp` (off by default)], [#n], [CaDiCaL],
  [Covered clause elimination], [#n], [#y `cover.cpp` (off by default)], [#n], [CaDiCaL],
  [Conditioning (globally blocked)], [#n], [#y `condition.cpp` (off by default)], [#n], [CaDiCaL],
  [Instantiation], [#n], [#y `instantiate.cpp` (off by default)], [#n], [CaDiCaL],
  [Factorization (BVA)], [#n], [#n], [#y `factor.c`], [not ported],
  [Model reconstruction], [#y simp], [#y `extend.cpp`], [#y `extend.c`], [MiniSat (simp), CaDiCaL],
  [Failed literal probing (+ hyper-binary resolution)], [#n], [#y `probe.cpp`], [binary only, `backbone.c` (see below)], [CaDiCaL],
  [Vivification], [#n], [#y `vivify.cpp`], [#y `vivify.c`], [CaDiCaL],
  [Equivalent literal substitution], [#n], [#y `decompose.cpp`], [#y `substitute.c`], [CaDiCaL],
  [Transitive reduction], [#n], [#y `transred.cpp`], [#y `transitive.c`], [CaDiCaL],
  [Ternary resolution], [#n], [#y `ternary.cpp`], [#n], [CaDiCaL],
  [Backbone], [#n], [#n], [#y `backbone.c`], [not ported],
  [Congruence closure], [#n], [#n], [#y `congruence.c`], [not ported],
  [SAT sweeping (with kitten)], [#n], [#n], [#y `sweep.c`, `kitten.c`], [not ported],
)

kissat's `probe.c` only schedules other passes (congruence, substitute, vivify, sweep, …); failed
literals over binary clauses are found by `backbone.c`, and kissat has no hyper-binary resolution.

== Incremental use (chapter 6)

#table(
  columns: (auto, auto, auto, auto, auto),
  align: (left, center, center, center, left),
  [*Feature*], [*MiniSat*], [*CaDiCaL*], [*kissat*], [*ksat ports*],
  [Assumptions], [#y core], [#y `assume.cpp`], [#n], [MiniSat, CaDiCaL, kissat (kissat: port extension)],
  [Add clauses after a solve], [#y], [#y], [#n], [MiniSat, CaDiCaL, kissat],
  [Failed-assumption core], [#y `analyzeFinal`], [#y `failing()`], [#n], [MiniSat, CaDiCaL],
  [IPASIR-UP user propagators], [#n], [#y `external_propagate.cpp`], [#n], [CaDiCaL],
  [Forced phases (phase/unphase)], [polarity only], [#y `phases.cpp`], [#n], [CaDiCaL],
  [Fixed-assignment listener], [#n], [#y], [#n], [CaDiCaL],
  [Proofs (DRAT / LRAT)], [#n], [#y `proof.cpp`, …], [#y `proof.c`], [CaDiCaL],
)

#note(title: "Why the ports stop where they do")[
  The ksat ports translate the search core line by line and check it step by step against
  instrumented C references. Every simplification technique changes the formula and the search
  trace, so each one would need its counterpart in the C reference before it could be verified
  the same way. The core plus the incremental API is what the Kotlin side needs; the rest is
  where the original solvers get their speed on hard instances. Exception: MiniSat's `simp`
  layer (`SimpSolver`) is ported in full and checked step by step against the instrumented
  upstream (meelgroup/minisat), like the core. CaDiCaL is ported in full (all techniques,
  checked against the instrumented real upstream 2.1.3), so for CaDiCaL every technique in the
  tables is present.
]
