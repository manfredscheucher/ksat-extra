#import "../lib/template.typ": note, warn, example, where

= Using a solver incrementally

Chapters 1–5 looked at one call: a formula goes in, SAT or UNSAT comes out. Programs that embed
a solver rarely ask just one question. A puzzle helper asks "can this cell be a mine?" for every
cell, a planner asks "is there a plan of length $k$?" for growing $k$, a model counter asks
"is there another solution?" until the answer is no. The questions share almost all of their
clauses. This chapter is about asking them on one solver instance that stays alive, and about
the interfaces (IPASIR, IPASIR-UP) that let a program talk to the solver while it searches.

== Incremental SAT and the IPASIR interface

The intuition: a solver that just finished a solve call has paid for a lot of knowledge. It has
learned clauses (chapter 1), variable scores and saved phases (chapter 2), a cleaned-up clause
database (chapter 3). All of that is still valid for the next question as long as the next
question only adds constraints or makes temporary ones. Throwing the instance away and
loading the formula again means paying for that knowledge again.

IPASIR is the small C interface the SAT competition's incremental track standardized, and every
incremental solver understands some version of it. Its core is five calls:

#table(
  columns: (auto, auto, 1fr),
  inset: 5pt,
  stroke: 0.4pt + rgb("#BBBBBB"),
  [*IPASIR*], [*ksat*], [*meaning*],
  [`ipasir_add`], [`addClause(lits)`], [add a clause (IPASIR: one literal per call, 0 closes it)],
  [`ipasir_assume`], [`solve(assumptions)`], [assume a literal for the next solve only],
  [`ipasir_solve`], [`solve(...)`], [10 = SAT, 20 = UNSAT (0 = interrupted)],
  [`ipasir_val`], [`valueOf(v)`], [value of a variable in the model, after SAT],
  [`ipasir_failed`], [`failed(lit)`], [was this assumption part of the reason for UNSAT?],
)

After a solve the program may add more clauses and solve again. Clauses stay forever;
assumptions are forgotten after each solve. That split is the whole design: permanent facts
go in as clauses, "what if" questions go in as assumptions.

#example(title: "Tie and shirt (the example from cadical.hpp)")[
  Let $a$ = "wear a tie", $b$ = "wear a shirt", with
  $C_1 = (overline(a) or b)$, $C_2 = (a or b)$, $C_3 = (overline(a) or overline(b))$.
  From $C_1$ and $C_2$ the shirt is forced, and then $C_3$ forbids the tie: the only model is
  $a = 0, b = 1$.

  Now ask "what if I wear a tie?" by assuming $a$: UNSAT, and `failed(a)` says the tie is to
  blame. Then ask "what if no shirt?" by assuming $overline(b)$: UNSAT again, and this time
  $overline(b)$ is the failed assumption. The clauses were loaded once; the two questions
  left no trace in the formula.

  ```kotlin
  val k = Ksat(Solver.CADICAL, numVars = 2)       // a = tie = 1, b = shirt = 2
  k.addClause(intArrayOf(-1, 2))
  k.addClause(intArrayOf(1, 2))
  k.addClause(intArrayOf(-1, -2))
  check(k.solve() == SatResult.SAT)
  check(!k.valueOf(1) && k.valueOf(2))            // no tie, shirt

  check(k.solve(assumptions = intArrayOf(1)) == SatResult.UNSAT)
  check(k.failed(1))                               // the tie is to blame

  check(k.solve(assumptions = intArrayOf(-2)) == SatResult.UNSAT)
  check(k.failed(-2))                              // "no shirt" is to blame
  ```
]

Why it matters: learned clauses are consequences of the clauses alone, so they help every later
question. On a sequence of similar queries the second and later solves are often much faster
than the first. IPASIR also has `ipasir_set_terminate` (stop a long solve) and
`ipasir_set_learn` (export learned clauses); ksat has neither.

#where[
  CaDiCaL: `ipasir.h`, `ipasir.cpp`, the IPASIR block of `cadical.hpp` · kissat: — (kissat 4.0
  refuses a second search: "incremental solving not supported") · MiniSat: `Solver.h`
  (`solve(assumps)`, `addClause`) · ksat: `SatSolver` (`addClause`, `solve(assumptions)`,
  `valueOf`, `failed`) behind the `Ksat` facade. kissat's incremental support is a port
  extension. MicroSat (ksat's minimal fourth solver, no incremental API) only does a plain
  single solve.
]

== Assumptions are decisions on the first levels

The intuition: an assumption is not a clause. The solver treats the assumptions as its first
decisions, one decision level per assumption, in the given order. Only when all of them are on
the trail does it start choosing decisions of its own. Everything else in CDCL stays the same:
unit propagation after each assumption, conflict analysis, backjumping.

Two cases need care. If an assumption is already true when its turn comes (it was propagated
by an earlier one), the solver opens an empty "pseudo" decision level, so that level $i$ still
belongs to assumption $i$. If an assumption is already false, the formula plus the assumptions
is UNSAT and the solver stops right there. That is "UNSAT under these assumptions", not UNSAT of
the formula.

#example(title: "Assumptions on the trail")[
  Take $C_1 = (overline(a) or c)$, $C_2 = (overline(b) or overline(c) or d)$,
  $C_3 = (overline(d) or e)$ and assume $a, b$. The trail is

  $ a@1, quad c@1 arrow.l C_1, quad b@2, quad d@2 arrow.l C_2, quad e@2 arrow.l C_3 $

  Level 1 is the assumption $a$ and its consequences, level 2 the assumption $b$ and its
  consequences. Here all five variables are already assigned, so the solve returns SAT with
  $a = b = c = d = e = 1$ (the only model with $a$ and $b$ true).

  - Assume $a, c, b$ instead: when $c$'s turn comes, $c$ is already true from level 1. The
    solver opens an empty level 2 and puts $b$ on level 3.
  - Assume $a, b, overline(e)$: after level 2, $e$ is true, so the third assumption is
    already false. Result: UNSAT under these assumptions. Without assumptions the formula is
    of course SAT.
]

Why it matters: a clause learned while assumptions are on the trail is derived by resolution
from the clauses only. The assumptions were decisions, and decisions never become part of a
learned clause's justification, they only steer the search. So everything learned under
assumptions $a, b$ remains valid when the next call assumes $overline(a)$. Had the program
added the units $(a)$ and $(b)$ instead, they would stay forever and the next question would be
answered for the wrong formula.

#where[
  CaDiCaL: `decide.cpp` (`decide`: next assumption, pseudo level if already true, 20 if
  false), `assume.cpp` · kissat: — (no assumptions upstream) · MiniSat: `Solver.cc`
  (`search`: "Perform user provided assumption", dummy decision level) · ksat:
  `solve(assumptions)` for MiniSat, CaDiCaL and kissat (kissat: port extension), not MicroSat.
  After each `solve(assumptions)` the ports backtrack to level 0, so the instance is ready for
  the next call.
]

== The failed-assumption core

The intuition: when the answer is UNSAT under assumptions, the program usually wants to know
*which* assumptions caused it. "Can this cell be a mine, given these five clues?" is more useful
with "no, because of clues 2 and 4". The solver can answer that cheaply from the trail it has at
the moment it stops: the falsified assumption was falsified by unit propagation, and following
the reasons backwards through the implication graph ends at decisions. All those decisions are
assumptions (the solver had not made its own decisions yet), so they form the core.

Both solvers do this walk, with the same idea:

- MiniSat's `analyzeFinal` starts from the falsified assumption, walks the trail backwards and
  marks the reason literals of every seen variable. Seen variables without a reason are
  decisions, that is assumptions, and go into the core.
- CaDiCaL's `failing()` first looks for three cases: (1) an assumption falsified at the root
  (then that one assumption is the core), (2) two clashing assumptions $x$ and $overline(x)$
  (both are the core), otherwise (3) the falsified assumption on the lowest decision level, from
  which it runs a BFS over the reasons, as MiniSat does.

#example(title: "A core that is not minimal")[
  $C_1 = (overline(a) or overline(b) or c)$, $C_2 = (overline(a) or d or c)$,
  $C_3 = (overline(a) or overline(d) or c)$, assumptions $a, b, overline(c)$.

  - Level 1: $a@1$. Nothing propagates: $C_2$ and $C_3$ each still have two open literals.
  - Level 2: $b@2$, then $c@2 arrow.l C_1$.
  - Level 3: the assumption $overline(c)$ is already false. UNSAT under the assumptions.

  The walk starts at $c$. Its reason $C_1$ points at $a$ and $b$; both have no reason, so both
  are assumptions. The core is ${a, b, overline(c)}$: `failed` is true for all three. Both the
  MiniSat and the CaDiCaL port report exactly this.

  The core is correct (those three assumptions alone are UNSAT) but not minimal. $C_2$ and
  $C_3$ resolve on $d$ to $(overline(a) or c)$, so $a$ and $overline(c)$ alone already
  clash. Unit propagation cannot see that without a case split on $d$, so the solver used the
  path via $C_1$ and blamed $b$ as well. Assuming only $b, overline(c)$ is SAT, so $b$ really
  is innocent.

  ```kotlin
  val k = Ksat(Solver.MINISAT, numVars = 4)         // a=1, b=2, c=3, d=4
  k.addClause(intArrayOf(-1, -2, 3))                // C1
  k.addClause(intArrayOf(-1, 4, 3))                 // C2
  k.addClause(intArrayOf(-1, -4, 3))                // C3
  val assumptions = intArrayOf(1, 2, -3)
  check(k.solve(assumptions) == SatResult.UNSAT)
  val core = assumptions.filter { k.failed(it) }    // [1, 2, -3]
  ```

  The answer also depends on what the solver has learned. Solve once more under only
  $a, overline(c)$: that is UNSAT too, and to find out the solver learns $(overline(a) or c)$.
  Ask the first question again and the trail becomes $a@1, c@1$, so the core is now
  ${a, overline(c)}$ (both ports).
]

Why it matters: cores are what make many applications work (explanations, MaxSAT, diagnosis,
finding which constraints of a configuration conflict). `cadical.hpp` says it plainly:
"the core does not have to be minimal". If the program needs a
minimal core, it shrinks it itself: drop one assumption from the core, solve under the rest,
and keep it dropped if the answer is still UNSAT. Each step is a cheap incremental call. A
practical detail: CaDiCaL only allows `failed` in the UNSAT state. After a SAT result, or once
a clause is added, upstream CaDiCaL aborts with an API contract violation (`REQUIRE`), and the
ksat port throws an `IllegalStateException`. MiniSat simply answers false.

#where[
  CaDiCaL: `assume.cpp` (`failing`, `failed`) · kissat: — (no failed-assumption API upstream)
  · MiniSat: `Solver.cc` (`analyzeFinal`, the `conflict` vector) · ksat: `failed(lit)` for
  CaDiCaL and MiniSat. The CaDiCaL port computes the core at the UNSAT exit, before its
  backtrack to level 0 (upstream computes it lazily).
]

== Adding clauses after a solve

The intuition: after a SAT answer, the trail is full. Every variable is assigned, many on high
decision levels. A new clause may already be falsified by that trail, or be unit, or be
satisfied by a decision that will be undone soon. None of this says anything about the new
clause in general; it only reflects the last model. So before a new original clause goes in,
the solver goes back to the root (level 0). There the clause is checked against the root
assignment only: root-false literals are dropped, a root-satisfied clause is ignored, and a
clause that becomes unit is assigned at level 0, where it belongs.

#example(title: "A unit after a solve")[
  $F = (a or b)$. The first solve may return $a = 1, b = 1$ (both decisions:
  $a@1, b@2$). Now the program learns that $a$ must be false and adds $(overline(a))$.

  On the old trail, $(overline(a))$ would be falsified at level 1, and a unit at level 1 is
  undone by the next backtrack. Going back to level 0 first gives the right picture:
  $overline(a)@0$, then $b@0 arrow.l (a or b)$. The next solve returns $a = 0, b = 1$, the
  only model left.

  ```kotlin
  val k = Ksat(Solver.CADICAL, numVars = 2)
  k.addClause(intArrayOf(1, 2))
  k.solve()                        // SAT, e.g. a = 1, b = 1
  k.addClause(intArrayOf(-1))      // new fact: a is false
  k.solve()                        // SAT, a = 0, b = 1
  ```
]

Why it matters: this is the "add" half of incremental solving, and it is easy to get subtly
wrong. The CaDiCaL and kissat ports once got exactly this example wrong: the unit landed on a
dirty level above 0, so the next backtrack removed it again (CaDiCaL) or the decision queue
walk crashed (kissat). Upstream avoids it in the same simple way: CaDiCaL's
`add_new_original_clause` starts with
`if (!from_propagator && level && !opts.ilb) backtrack ();`, so it backtracks to level 0 first
(unless the `ilb` option is set, default off). MiniSat's `addClause_`
asserts decision level 0 and `solve_` ends with `cancelUntil(0)`.

#where[
  CaDiCaL: `clause.cpp` (`add_new_original_clause`) · kissat: — (no second solve upstream;
  the port goes back to level 0 before importing a clause) · MiniSat: `Solver.cc`
  (`addClause_`, `solve_`) · ksat: `addClause` after `solve` for MiniSat, CaDiCaL and kissat.
  Not MicroSat.
]

== Model enumeration with blocking clauses

The intuition: to list all models, find one, forbid exactly that one, and ask again. The clause
that forbids a model $M$ is the OR of the negations of $M$'s literals; it is false under $M$ and
true under every other assignment. When the answer becomes UNSAT, every model has been seen
once. With an incremental solver each round is one `addClause` plus one `solve`, and learned
clauses carry over.

#example(title: "Enumerating XOR")[
  $a xor b$ in CNF is $(a or b) and (overline(a) or overline(b))$, with the two models
  ${a = 0, b = 1}$ and ${a = 1, b = 0}$.

  + Solve: $a = 0, b = 1$. Block it with $(a or overline(b))$.
  + Solve: $a = 1, b = 0$. Block it with $(overline(a) or b)$.
  + Solve: UNSAT. The four clauses rule out all four assignments. Done, two models.

  ```kotlin
  val xor = listOf(intArrayOf(1, 2), intArrayOf(-1, -2))
  val models = enumerateModels(Solver.CADICAL, numVars = 2, cnf = xor,
                               incremental = true).toList()
  // [[false, true], [true, false]]
  ```
]

Each model is a full assignment over the variables $1, dots, n$, with $n$ = `numVars`. A variable no clause
constrains doubles the count: $(a or b)$ with `numVars = 3` has $3 dot 2 = 6$ models. That is
correct, but it surprises people. If only some variables matter (a projection), block only
their literals; then one blocking clause removes a whole group of models. `enumerateModels`
does not do that, it always blocks all of $1, dots, n$.

Why it matters: blocking clauses are the simplest all-SAT method and need nothing but
add-after-solve. They get slow for many models: every model adds a clause of length $n$. For
counting large model sets, dedicated model counters are the better tool.

#where[
  CaDiCaL / kissat / MiniSat: — (a technique on top of the API, not inside the solver) · ksat:
  `Enumerate.kt` (`enumerateModels`). `incremental = false` (default) builds a fresh solver per
  round and works with every solver; `incremental = true` keeps one solver and needs
  add-after-solve (MiniSat, CaDiCaL, kissat; throws for MicroSat).
]

== Frozen variables and elimination

The intuition: chapter 4 showed bounded variable elimination: a variable $x$ is removed by
replacing its clauses with all their resolvents on $x$. That keeps the formula
*equisatisfiable*, not equivalent. It is safe for a single solve. It breaks incremental use if
the program later mentions $x$ again, in a new clause or an assumption, because the solver no
longer has the clauses that constrained $x$.

Chapter 4 (section "Frozen variables", example "A spurious model after elimination") shows
the failure: after $x$ is eliminated, a later call that assumes $x = 0$ and $a = 0$ gets a
model, although the original clauses make that combination UNSAT. The same happens when the
program adds new clauses $(overline(x))$ and $(overline(a))$ instead of assuming them: the
solver no longer has $(x or a)$, so nothing stops it.

There are two fixes. The old one is *freezing*: the program declares up front which variables
it will use again (MiniSat's `setFrozen`, CaDiCaL's `freeze`/`melt`), and frozen variables are
never eliminated. MiniSat's `SimpSolver` also freezes the assumption variables during a solve.
The newer one is restoring: CaDiCaL notices when an eliminated variable shows up again and
puts the removed clauses back from the extension stack, so the program does not need to
freeze anything. Variables observed by an IPASIR-UP propagator (below) are frozen internally.

Why it matters: preprocessing and incremental use pull in opposite directions. Elimination
wants to remove variables, the program wants to keep talking about them. Freezing, restoring or
not eliminating at all are the three ways out.

#where[
  CaDiCaL: `cadical.hpp` (`freeze`, `melt`, `frozen`), `restore.cpp`, `elim.cpp` · kissat:
  — (single solve) · MiniSat: `simp/SimpSolver.h` and `SimpSolver.cc` (`setFrozen`,
  `extra_frozen`) · ksat: no port has elimination (MiniSat is ported without `SimpSolver`,
  CaDiCaL without `elim`), so there is nothing to freeze and no freeze API.
]

== IPASIR-UP: user propagators

The intuition: some constraints are awkward as clauses. They need too many clauses (an
at-most-one over thousands of variables, a graph property, an arithmetic check), or the
program only knows them as code. IPASIR-UP lets the program take part in the search instead.
It plugs a *propagator* object into the solver, tells it which variables it cares about
(the observed variables), and from then on the solver calls the propagator during CDCL:

#table(
  columns: (auto, 1fr),
  inset: 5pt,
  stroke: 0.4pt + rgb("#BBBBBB"),
  [*callback (CaDiCaL name)*], [*what it is for*],
  [`notify_assignment`, `notify_new_decision_level`, `notify_backtrack`],
  [the solver reports assignments to observed variables and level changes, so the propagator
   can keep its own copy of the trail. Not necessarily eager: usually delivered right before
   the next question to the propagator.],
  [`cb_propagate`],
  ["do you imply a literal under the current assignment?" Returns a literal or 0.],
  [`cb_add_reason_clause_lit`],
  [the reason clause for a literal returned by `cb_propagate`, one literal per call, closed by
   0. It must contain the propagated literal. Asked only when the solver needs it.],
  [`cb_has_external_clause`, `cb_add_external_clause_lit`],
  [hand the solver a new clause during search, one literal per call. Added as an
   irredundant clause unless marked forgettable.],
  [`cb_check_found_model`],
  [the solver has a complete model. Return false to reject it; the propagator must then give
   a clause (or observe new variables) that explains why.],
  [`cb_decide`], [suggest the next decision literal, or 0 to let the solver choose.],
)

Two ideas make this efficient. First, *lazy reasons*: `cb_propagate` only says "this literal
is implied". The solver puts it on the trail with a placeholder reason and asks for the actual
clause later. With the default option `exteagerreasons`, CaDiCaL asks, before each conflict
analysis, for the reasons of all external propagations the conflict depends on. A literal
propagated at level 0 has its reason asked for right away. Many propagated literals are
undone before anybody asks. Second, every clause the propagator ever hands over
is a normal clause from then on. The solver propagates it itself and learns from it, so the
propagator is not asked the same thing twice.

The propagator must be honest: every literal it propagates must follow from its reason clause
under the current assignment, and every clause it adds must be implied by its constraint.
Otherwise the solver's answers are wrong. In Kotlin the callbacks have camelCase names
(`cbPropagate`, `notifyAssignment`, ...), and `Ksat` hosts the propagator
(`connectExternalPropagator`, `addObservedVar`, `isDecision`, `forceBacktrack`).

#example(title: "A lazy at-most-one, step by step")[
  The solver gets $C_1 = (a or b or c)$, $C_2 = (b or d)$, $C_3 = (b or overline(d))$. The
  propagator knows the constraint "at most one of $a, b, c$", which as clauses would be
  $(overline(a) or overline(b))$, $(overline(a) or overline(c))$,
  $(overline(b) or overline(c))$. The solver never sees those three clauses up front.
  Observed variables: $a, b, c$. The models of the whole problem are $a = 0, b = 1, c = 0$
  with $d$ free.

  This is the real callback sequence of the CaDiCaL port, with `cb_decide` suggesting $a$ first
  so that the run is reproducible:

  + `cb_decide` returns $a$. Trail $a@1$. The propagator gets
    `notify_new_decision_level` and `notify_assignment([a])`.
  + `cb_propagate`: $a$ is true, so $b$ must be false. It returns $overline(b)$ and only
    remembers the reason $(overline(a) or overline(b))$. Trail
    $overline(b)@1 arrow.l "ext"$.
  + The solver propagates its own clauses: $d@1 arrow.l C_2$, and then
    $C_3 = (b or overline(d))$ is false. Conflict.
  + The conflict depends on the external propagation $overline(b)$. With the default
    `exteagerreasons`, CaDiCaL asks for the reasons of all external propagations the conflict
    depends on, here $overline(b)$. It calls `cb_add_reason_clause_lit` with the literal
    $overline(b)$ three times and gets $overline(a), overline(b), 0$.
  + Resolving $C_3$ with $C_2$ on $d$ gives the learned unit $(b)$. Backtrack to level 0
    (`notify_backtrack(0)`), $b@0$.
  + The solver now owns $(overline(a) or overline(b))$, so it propagates
    $overline(a)@0$ by itself. The propagator is only notified, it is never asked for
    $overline(a)$.
  + `cb_propagate` returns $overline(c)$. At level 0 the solver asks for the reason
    immediately and gets $(overline(b) or overline(c))$.
  + `cb_propagate` returns 0. The solver decides $d$ (not observed, so the notification is
    empty), the model is complete, and `cb_check_found_model([-a, b, -c])` accepts it. SAT.

  Without the `cb_decide` hint, the port's first decision level already makes $b$ true. Then
  $overline(a)$ and $overline(c)$ are propagated, nothing conflicts, and
  `cb_add_reason_clause_lit` is never called at all: those reasons were never needed.

  If the propagator never propagated (`cb_propagate` always 0), it would only see complete
  models: the run gets $a, b, c$ all true, rejects that model and adds
  $(overline(a) or overline(b))$, later rejects $overline(a), b, c$ and adds
  $(overline(b) or overline(c))$, and then accepts $overline(a), b, overline(c)$. Same
  answer, more search.
]

#example(title: "The at-most-one propagator in Kotlin")[
  ```kotlin
  import org.bytefred.ksat.ExternalPropagator
  import org.bytefred.ksat.OutBoolean
  import org.bytefred.ksat.SatResult
  import org.bytefred.ksat.facade.Ksat
  import org.bytefred.ksat.facade.Solver
  import kotlin.math.abs

  /** At most one of [vars] is true. Eager propagation, lazy reasons. */
  class AtMostOne(private val vars: IntArray, firstDecision: Int = 0) :
      ExternalPropagator {
      private val trail = mutableListOf(mutableListOf<Int>()) // lits per level
      private val value = HashMap<Int, Int>()          // var -> assigned literal
      private val reasons = HashMap<Int, IntArray>()   // propagated lit -> reason
      private var pending: ArrayDeque<Int>? = null    // reason being handed out
      private val toAdd = ArrayDeque<IntArray>()       // clauses for the solver
      private var addPos = 0
      private var suggestion = firstDecision

      override fun notifyAssignment(lits: IntArray) {
          for (lit in lits) { value[abs(lit)] = lit; trail.last().add(lit) }
      }

      override fun notifyNewDecisionLevel() { trail.add(mutableListOf()) }

      override fun notifyBacktrack(newLevel: Int) {
          while (trail.size - 1 > newLevel)
              for (lit in trail.removeAt(trail.lastIndex)) value.remove(abs(lit))
      }

      override fun cbDecide(): Int = suggestion.also { suggestion = 0 }

      override fun cbPropagate(): Int {
          val t = vars.firstOrNull { value[it] == it } ?: return 0 // a true var?
          val u = vars.firstOrNull { it != t && value[it] != -it } ?: return 0
          reasons[-u] = intArrayOf(-t, -u)        // keep the reason, do not send
          return -u
      }

      override fun cbAddReasonClauseLit(propagatedLit: Int): Int {
          val q = pending ?: ArrayDeque(reasons.getValue(propagatedLit).toList())
          pending = q
          if (q.isEmpty()) { pending = null; return 0 }
          return q.removeFirst()
      }

      override fun cbCheckFoundModel(model: IntArray): Boolean {
          val trueVars = model.filter { it > 0 && it in vars }
          if (trueVars.size <= 1) return true
          toAdd.addLast(intArrayOf(-trueVars[0], -trueVars[1])) // reject, explain
          return false
      }

      override fun cbHasExternalClause(isForgettable: OutBoolean) =
          toAdd.isNotEmpty()

      override fun cbAddExternalClauseLit(): Int {
          val c = toAdd.first()
          if (addPos < c.size) return c[addPos++]
          toAdd.removeFirst(); addPos = 0
          return 0
      }
  }

  val k = Ksat(Solver.CADICAL, numVars = 4)     // a=1, b=2, c=3, d=4
  k.addClause(intArrayOf(1, 2, 3))              // C1
  k.addClause(intArrayOf(2, 4))                 // C2
  k.addClause(intArrayOf(2, -4))                // C3
  k.connectExternalPropagator(AtMostOne(intArrayOf(1, 2, 3), firstDecision = 1))
  for (v in 1..3) k.addObservedVar(v)
  check(k.solve() == SatResult.SAT)             // a = 0, b = 1, c = 0
  ```

  If two variables are true at once, `cbPropagate` returns the negation of a true literal.
  The solver then gets a reason clause that is false under the trail and treats it as a
  conflict. `cbCheckFoundModel` is the safety net: even if a propagation was missed, a bad
  model is rejected with a clause.
]

A few more pieces of the interface. `is_lazy` (Kotlin: `isLazy`) declares a propagator that
only checks complete models and is never asked to propagate. `are_reasons_forgettable` lets
the solver delete reason clauses again during clause database reduction. `is_decision(lit)`
tells whether an observed literal was a decision. `force_backtrack(level)`, only effective
inside `cb_decide`, makes the solver jump back. Observed variables can be added during the
search, but removed only between solves. And API calls from inside a callback (adding a
clause, solving) are not allowed: upstream CaDiCaL aborts with an API contract violation
(`REQUIRE`), the ksat port throws an exception.

Why it matters: IPASIR-UP turns the SAT solver into the search engine of a bigger system:
SMT-style theory reasoning, symmetry breaking, graph constraints, or simply constraints too
large to write down. The lazy design keeps the price low: the propagator explains only the
inferences that end up in a conflict.

#where[
  CaDiCaL: `cadical.hpp` (`ExternalPropagator`, IPASIR-UP block of `Solver`),
  `external_propagate.cpp` (`external_propagate`, `external_check_solution`, `ask_decision`,
  `explain_external_propagations`, which `analyze.cpp` calls on conflicts when option
  `exteagerreasons` is set) ·
  kissat: — · MiniSat: — · ksat: CaDiCaL only; `ExternalPropagator.kt` in ksat-common,
  `Ksat.connectExternalPropagator`, `addObservedVar`, `isDecision`, `forceBacktrack`. Other
  solvers throw `UnsupportedOperationException`.
]

== Forced phases and the fixed-assignment listener

Two small CaDiCaL extras that are not IPASIR-UP but help a program steer and watch the solver.

*Forced phases.* Chapter 2 explained phase saving: when the solver decides a variable, it uses
the value the variable had last time. `phase(lit)` overrides that: whenever the solver decides
this variable, it takes the sign of `lit`. `unphase` removes the override. It is a preference,
not a constraint. If propagation already assigned the variable, the phase is never consulted.

*Fixed-assignment listener.* A variable is fixed when it is assigned at level 0, that is, it
is implied by the formula and will never change again (until the end of the instance). A
connected listener gets `notify_fixed_assignment(lit)` for every newly fixed literal: original
units, their root propagation, learned units. Listeners are real-time: literals fixed before
connecting are not replayed.

#example(title: "A phase is only a preference")[
  $F = (overline(a) or overline(b))$ with `phase(a)` and `phase(b)`: the program would like
  both to be true, which $F$ forbids. The solver decides one of them with its forced phase,
  and the other one is then propagated false. In the CaDiCaL port the answer is
  $a = 0, b = 1$ ($b$ is decided first). With `phase(-a)` and `phase(b)` the wish is a model,
  and the port returns exactly it.

  ```kotlin
  val k = Ksat(Solver.CADICAL, numVars = 2)
  k.addClause(intArrayOf(-1, -2))
  k.phase(1); k.phase(2)
  k.solve()                        // SAT, a = 0, b = 1
  ```
]

#example(title: "Watching variables become fixed")[
  $C_1 = (a or b)$, $C_2 = (overline(b) or overline(c))$, $C_3 = (c or d)$, then the unit
  $(overline(a))$. The unit fixes $overline(a)@0$, and root propagation fixes
  $b@0 arrow.l C_1$, $overline(c)@0 arrow.l C_2$, $d@0 arrow.l C_3$. The listener hears
  $-1, 2, -3, 4$, already while the unit is added (CaDiCaL propagates new units right away).

  ```kotlin
  val k = Ksat(Solver.CADICAL, numVars = 4)
  k.connectFixedListener(object : FixedAssignmentListener {
      override fun notifyFixedAssignment(lit: Int) = println("fixed $lit")
  })
  k.addClause(intArrayOf(1, 2))
  k.addClause(intArrayOf(-2, -3))
  k.addClause(intArrayOf(3, 4))
  k.addClause(intArrayOf(-1))      // prints: fixed -1, fixed 2, fixed -3, fixed 4
  ```
]

Why it matters: forced phases let a program say "I expect roughly this solution" (for example
the previous solution in a sequence of similar queries) and get it back when it is still a
model. Not always exactly: CaDiCaL (upstream and the ksat port, which behaves the same) may
try lucky phases or local search first and return another model. The fixed listener lets
the program learn facts that hold in every model while the solver runs, for example to prune
its own search space or to stop asking questions whose answer is already fixed.

#where[
  CaDiCaL: `decide.cpp` (`decide_phase` reads `phases.forced` first), `phases.cpp` (`phase`,
  `unphase`), `cadical.hpp` (`FixedAssignmentListener`), `flags.cpp` (`mark_fixed`) · kissat:
  — · MiniSat: — (only `setPolarity`, not exposed in ksat) · ksat: CaDiCaL only; `ForcedPhases` and
  `FixedListening` in ksat-common, `Ksat.phase`, `unphase`, `connectFixedListener`,
  `disconnectFixedListener`.
]

== Proofs of unsatisfiability: DRAT and LRAT

The intuition: a SAT answer comes with a model that anybody can check in linear time. An UNSAT
answer has nothing like that, unless the solver writes down how it got there. A clausal proof
is the list of clauses the solver learned, in order, ending with the empty clause. A checker
verifies that each clause follows from the earlier ones by unit propagation alone (RUP: assume
the clause false, propagate, get a conflict).

- *DRAT* lists the learned clauses (and deleted ones, marked `d`). Each added clause must be
  RUP or RAT. RAT ("resolution asymmetric tautology") also admits a clause that is blocked-like
  on its first literal: every resolvent on that literal is RUP. That is what justifies the
  steps of chapter 4 that are not plain consequences, such as BVE and BCE. The checker has to
  find the propagation for each clause itself, which can take longer than solving.
- *LRAT* adds clause IDs and, for each clause, the IDs of the clauses that become unit in its
  propagation (the hints). The checker only replays them, which is simple and fast enough to
  be done by a formally verified checker.

#example(title: "A two-step proof")[
  $C_1 = (a or b)$, $C_2 = (a or overline(b))$, $C_3 = (overline(a) or c)$,
  $C_4 = (overline(a) or overline(c))$ is UNSAT.

  - Clause 5 = $(a)$: assume $overline(a)$; $C_1$ gives $b$, then $C_2$ is false.
  - Clause 6 = empty: clause 5 gives $a$, $C_3$ gives $c$, then $C_4$ is false.

  As DRAT that is the two lines `1 0` and `0`. As LRAT it is `5 1 0 1 2 0` and `6 0 5 3 4 0`
  (ID, literals, 0, hint IDs in propagation order, 0).
]

Why it matters: solvers have bugs, and proofs make UNSAT answers trustworthy without trusting
the solver. In the incremental setting it gets harder: assumptions, clauses added later and
propagator clauses all need a place in the proof, which is why CaDiCaL has incremental proof
formats as well. None of this is ported to ksat. The ports were checked differently, by
shadowing the C solvers trace step by step (see `shadowing-methodology`).

#where[
  CaDiCaL: `proof.cpp`, `drattracer.cpp`, `lrattracer.cpp` (plus FRAT, IDRUP and LIDRUP
  tracers), `cadical.hpp` (`trace_proof`) · kissat: `proof.c` (DRAT, text or binary) ·
  MiniSat: — (2.2.0 writes no proofs) · ksat: not ported in any solver.
]
