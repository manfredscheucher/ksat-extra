#import "../lib/template.typ": note, warn, example, where

= The CDCL loop

Every solver in this tutorial (MiniSat, CaDiCaL, kissat, and the ksat ports) runs the same
basic algorithm: *conflict-driven clause learning* (CDCL). It guesses a value for a variable,
follows the consequences, and when the guesses lead to a contradiction it works out _why_,
writes the reason down as a new clause, and jumps back. Everything in later chapters (heuristics,
restarts, clause deletion, simplification) is built around this loop. This chapter walks through
it with one small formula, from the first decision to the final model.

== The loop at a glance

Here is the whole algorithm. Each line is explained in its own section below.

```text
level = 0
loop:
  conflict = propagate()             // unit propagation: extend the trail
  if conflict != none:
    if level == 0: return UNSAT      // contradiction without any guess
    learned, jump = analyze(conflict) // 1-UIP clause and its backjump level
    minimize(learned)                // drop redundant literals (+ shrink)
    backtrack(jump)                  // undo every level above 'jump'
    add(learned)                     // it is unit now: assign its UIP literal
  else:
    if every variable is assigned: return SAT
    maybe restart / reduce / simplify   // chapters 2 to 5
    level = level + 1
    decide()                         // pick an unassigned variable and a value
```

Three data structures carry the state: the _trail_ (the ordered list of assignments, each with
its decision level and its reason clause), the _clause database_ (original plus learned
clauses) and the _watch lists_ that make `propagate()` fast (last section of this chapter).

#where[
  CaDiCaL: `internal.cpp` (`Internal::cdcl_loop_with_inprocessing`) ·
  kissat: `search.c` (`kissat_search`) ·
  MiniSat: `Solver.cc` (`Solver::search`) ·
  ksat port: ported (all three cores)
]

== The running example

We use the following eight clauses over the variables $a, b, dots, k$ for the whole chapter.

#table(
  columns: (auto, auto, auto),
  inset: 5pt,
  stroke: 0.5pt + luma(180),
  [*Name*], [*Clause*], [*DIMACS*],
  [$C_1$], [$(overline(a) or b)$], [`-1 2 0`],
  [$C_2$], [$(overline(c) or d)$], [`-3 4 0`],
  [$C_3$], [$(overline(c) or e)$], [`-3 5 0`],
  [$C_4$], [$(overline(f) or g)$], [`-6 7 0`],
  [$C_5$], [$(overline(h) or i)$], [`-8 9 0`],
  [$C_6$], [$(overline(i) or j)$], [`-9 10 0`],
  [$C_7$], [$(overline(i) or overline(a) or overline(d) or k)$], [`-9 -1 -4 11 0`],
  [$C_8$], [$(overline(j) or overline(k) or overline(b) or overline(e))$], [`-10 -11 -2 -5 0`],
)

The formula is satisfiable, but not every guess works: $C_8$ forbids that $j$, $k$, $b$ and
$e$ are all true, and the binary clauses make it easy to force exactly that. To keep the walk
reproducible we use a deliberately dumb decision rule: _pick the alphabetically first unassigned
variable and set it to 1_. Real solvers choose much more cleverly (chapter 2), but the loop
itself does not care how the choice is made.

== Unit propagation and the trail

A clause is *unit* when all of its literals but one are false and the remaining one is
unassigned. Then that last literal must be true, otherwise the clause would be violated. Unit
propagation applies this rule over and over until nothing changes. It is the only kind of
reasoning the solver does between guesses, and it is where a CDCL solver spends most of its
time.

Every assignment goes onto the *trail* in the order it was made, together with two facts: the
decision level at which it happened and the clause that forced it (its _reason_). A guessed
assignment has no reason. The trail is both the current partial assignment and the record of
why each value is there, which conflict analysis needs later.

#example(title: "Propagating after the first guess")[
  Nothing is unit at the start (no clause has only one literal), so the solver has to guess.
  It sets $a = 1$ at level 1. Now $C_1 = (overline(a) or b)$ has its first literal false and $b$
  unassigned, so it is unit and forces $b = 1$. No other clause becomes unit. The trail is

  $ a@1, quad b@1 arrow.l C_1 $

  $C_7$ also contains $overline(a)$, which is now false, but it still has three unassigned
  literals, so it says nothing yet.
]

Why it matters: propagation is cheap logical inference. One guess can fix dozens of variables
without any search. The cost is that it must be done after every single assignment, which is
why solvers spend so much engineering on the watch lists (see the last section).

#where[
  CaDiCaL: `propagate.cpp` · kissat: `propsearch.c`, `proplit.h` ·
  MiniSat: `Solver.cc` (`propagate`, `uncheckedEnqueue`) · ksat port: ported
]

== Decisions and decision levels

When propagation stops without a conflict and some variables are still open, the solver makes a
_decision_: it picks an unassigned variable and a value. Each decision opens a new *decision
level*. Level 0 holds only facts that follow from the formula alone (no guess involved); level
$n$ holds the $n$-th decision plus everything propagated from it. The level is what lets the
solver undo exactly one guess and its consequences: drop everything above a given level.

#example(title: "Four decisions")[
  Applying our rule (first unassigned variable, value 1) and propagating after each step:

  #table(
    columns: (auto, auto, 1fr),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Level*], [*Decision*], [*Trail after propagation (new part)*],
    [1], [$a = 1$], [$a@1, quad b@1 arrow.l C_1$],
    [2], [$c = 1$], [$c@2, quad d@2 arrow.l C_2, quad e@2 arrow.l C_3$],
    [3], [$f = 1$], [$f@3, quad g@3 arrow.l C_4$],
    [4], [$h = 1$], [$h@4, quad i@4 arrow.l C_5, quad j@4 arrow.l C_6, quad k@4 arrow.l C_7$],
  )

  At level 4, $h$ forces $i$ through $C_5$. Then $i$ forces $j$ through $C_6$, and
  $C_7 = (overline(i) or overline(a) or overline(d) or k)$ forces $k$, because $i$, $a$ and $d$
  are all true by now. The order matters here: the solver handles all clauses watching $i$
  first ($C_6$ gives $j$, $C_7$ gives $k$); only then does it process $j$ and find $C_8$ false
  (next section). Level 3 ($f$, $g$) has nothing to do with the rest; keep an eye on it,
  it matters for backjumping.
]

Why it matters: decisions are the only place where the solver searches. A good choice of
variable and value (chapter 2) can shorten the run by orders of magnitude. The decision level
costs one integer per variable and one "where does this level start on the trail" entry per
level.

#where[
  CaDiCaL: `decide.cpp` · kissat: `decide.c` · MiniSat: `Solver.cc` (`pickBranchLit`,
  `newDecisionLevel`) · ksat port: ported
]

== Conflicts

A *conflict* happens when propagation finds a clause whose literals are all false. Then the
current assignment cannot be extended to a model, and at least one of the decisions was wrong.
If the conflict happens at level 0, no decision is involved and the formula is unsatisfiable.
Otherwise the solver analyzes it.

#example(title: "The conflict at level 4")[
  After the clauses watching $i$ are done, the trail contains $j@4$, $k@4$, $b@1$ and $e@2$.
  The solver now processes $j$ and looks at
  $C_8 = (overline(j) or overline(k) or overline(b) or overline(e))$: all four literals are
  false. $C_8$ is the *conflict clause*. Two of its literals belong to level 4 ($j$, $k$), one to
  level 1 ($b$) and one to level 2 ($e$).
]

A naive solver would now flip the last decision ($h = 0$) and continue. That is plain
backtracking (DPLL). It is correct, but it forgets everything it just found out and happily
repeats the same mistake in another part of the search tree. CDCL instead asks which
assignments _together_ caused the conflict.

#where[
  CaDiCaL: `propagate.cpp` (sets `conflict`) · kissat: `proplit.h` (returns the conflict
  clause) · MiniSat: `Solver.cc` (`propagate` returns `confl`) · ksat port: ported
]

== The implication graph

The reasons on the trail form a directed graph. Each assigned literal is a node. For a
propagated literal $x$ with reason clause $C$, there is an edge from every _other_ variable of
$C$ to $x$: those assignments are what made $C$ unit. Decisions have no incoming edges. The
conflict gets an extra node, called $kappa$ here, with edges from every literal of the
conflict clause. The solver never builds this graph explicitly; the reason pointers on the
trail are the graph.

#example(title: "The graph of our conflict")[
  #table(
    columns: (auto, auto, auto, 1fr),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Node*], [*Level*], [*Reason*], [*Incoming edges from*],
    [$a$], [1], [decision], [none],
    [$b$], [1], [$C_1$], [$a$],
    [$c$], [2], [decision], [none],
    [$d$], [2], [$C_2$], [$c$],
    [$e$], [2], [$C_3$], [$c$],
    [$f$], [3], [decision], [none],
    [$g$], [3], [$C_4$], [$f$],
    [$h$], [4], [decision], [none],
    [$i$], [4], [$C_5$], [$h$],
    [$j$], [4], [$C_6$], [$i$],
    [$k$], [4], [$C_7$], [$i$, $a$, $d$],
    [$kappa$], [], [$C_8$], [$j$, $k$, $b$, $e$],
  )

  The level-4 part, drawn out:

  ```text
                  +--C6--> j --+
     h --C5--> i -+            +--C8--> CONFLICT
                  +--C7--> k --+
                           ^            ^
               a@1, d@2 ---+            +--- b@1, e@2
  ```

  Nodes $f$ and $g$ (level 3) have no path to $kappa$: they played no part in the conflict.
]

Why it matters: any set of nodes that separates the decisions from $kappa$ (a *cut*) is a
reason for the conflict, and the negation of a cut is a clause the formula implies. Conflict
analysis is the art of picking a good cut.

#where[
  CaDiCaL: `var.hpp` (`Var::reason`, `Var::level`) · kissat: `assign.h` (`assigned`, `reason`)
  · MiniSat: `Solver.h` (`VarData { reason, level }`) · ksat port: ported
]

== Conflict analysis and the first UIP

The solver walks backwards from the conflict clause, using *resolution*: if a clause contains
$overline(x)$ and the reason of $x$ contains $x$, then the two clauses together imply the clause
with all their other literals. Resolving the current clause with the reason of one of its
literals replaces that literal by "the things that caused it". This is the same as moving the
cut one step towards the decisions.

The walk handles only literals of the conflict level (level 4 here), always the one assigned
last on the trail, and stops as soon as exactly one conflict-level literal is left. That
literal is the *first unique implication point* (1-UIP): a node on the conflict level that every
path from the level's decision to $kappa$ passes through, and the one closest to the conflict.
The decision itself is always a UIP (the last resort), but usually there is one earlier.

#example(title: "Deriving the 1-UIP clause")[
  Start from $C_8 = (overline(j) or overline(k) or overline(b) or overline(e))$. Level-4
  literals: $overline(j)$, $overline(k)$, so two are open.

  #table(
    columns: (auto, auto, 1fr, auto),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Step*], [*Resolve on*], [*Resulting clause*], [*Level-4 lits*],
    [start], [], [$(overline(j) or overline(k) or overline(b) or overline(e))$], [$j, k$],
    [1], [$k$ with $C_7$],
      [$(overline(j) or overline(b) or overline(e) or overline(i) or overline(a) or overline(d))$],
      [$j, i$],
    [2], [$j$ with $C_6$],
      [$(overline(i) or overline(a) or overline(b) or overline(d) or overline(e))$], [$i$],
  )

  Step 1 takes $k$ first because it was assigned after $j$. After step 2 only $overline(i)$ is
  left on level 4, so $i$ is the first UIP. The learned clause is

  $ L_1 = (overline(i) or overline(a) or overline(b) or overline(d) or overline(e)) $

  Read it as: "$i$, $a$, $b$, $d$ and $e$ cannot all be true". In the graph, ${i, a, b, d, e}$
  is the cut: every path into $kappa$ passes through one of them. Other cuts give other
  implied clauses. The decision $h$ is also a UIP of level 4; cutting there (one more
  resolution, with $C_5$) gives $(overline(h) or overline(a) or overline(b) or overline(d) or
  overline(e))$. Cutting right behind all decisions gives the "decision clause"
  $(overline(h) or overline(a) or overline(c))$, which talks only about the guesses rather than
  about what went wrong.
]

Why it helps: the learned clause is implied by the formula (each step is a resolution), so
adding it never removes a model. It blocks not just this exact combination of guesses but every
future assignment that makes $i$, $a$, $b$, $d$, $e$ true, wherever in the search it appears.
Having exactly one literal from the conflict level is what makes the clause *asserting*: after
the jump back it is unit (section "Backjumping" below). Among the possible cuts, 1-UIP has been the empirical
winner since Chaff (2001). Cost: one backwards pass over the conflict level of the trail, with
a "seen" flag per variable.

#where[
  CaDiCaL: `analyze.cpp` (`Internal::analyze`, `analyze_reason`) · kissat: `analyze.c`,
  `deduce.c` (`kissat_deduce_first_uip_clause`), `learn.c` · MiniSat: `Solver.cc`
  (`Solver::analyze`) · ksat port: ported
]

== Recursive clause minimization

The 1-UIP clause often contains literals that are implied by other literals of the same clause.
Such a literal is *redundant*: removing it still gives a clause the formula implies. The test is
recursive. A false literal $overline(x)$ in the learned clause can be dropped if $x$ was
propagated (not decided) and every other literal of $x$'s reason is either already in the
learned clause, assigned at level 0, or itself redundant by the same test. Decisions are never
redundant, because they have no reason to look into.

Removing $overline(x)$ this way is just more resolution: resolve the learned clause with the
reason of $x$. Since all the reason's other literals are already in the clause, nothing new
comes in and $overline(x)$ disappears.

#example(title: "Removing the redundant literal from the learned clause")[
  $L_1 = (overline(i) or overline(a) or overline(b) or overline(d) or overline(e))$. Check every
  literal except the UIP literal $overline(i)$:

  - $overline(a)$: $a$ is a decision. Keep.
  - $overline(b)$: $b$ was forced by $C_1 = (overline(a) or b)$. Its only other literal is
    $overline(a)$, which is in $L_1$. Redundant, remove.
  - $overline(d)$: forced by $C_2 = (overline(c) or d)$. $overline(c)$ is not in $L_1$ and $c$ is a
    decision. Keep.
  - $overline(e)$: forced by $C_3 = (overline(c) or e)$. Same as $d$. Keep.

  Result: $L_2 = (overline(i) or overline(a) or overline(d) or overline(e))$. It is the resolvent
  of $L_1$ and $C_1$ on $b$. Intuitively: if $a$ is true then $b$ is true anyway, so mentioning
  $b$ adds nothing.
]

Here the recursion stops after one step. In general the check follows reasons several levels
deep, which is why it is "recursive" (MiniSat's `ccmin_mode = 2`, also called deep
minimization; mode 1 only looks one step). MiniSat speeds it up with an _abstract level_
bitmask: if a reason contains a literal from a decision level that does not occur in the learned
clause at all, the literal cannot be redundant and the search stops early. CaDiCaL and kissat
cache the outcome per variable with "poison" (known not removable) and "removable" flags, and
cap the depth (`minimizedepth`, default 1000).

Why it helps: shorter clauses propagate earlier, take less memory and make later conflict
analysis cheaper. Cost: a depth-first
search over reasons, bounded by the caching.

#where[
  CaDiCaL: `minimize.cpp` (`minimize_literal`, `minimize_clause`) · kissat: `minimize.c` ·
  MiniSat: `Solver.cc` (`litRedundant`, called from `analyze` with `ccmin_mode = 2`) ·
  ksat port: ported
]

== Shrinking

Minimization only deletes literals. *Shrinking* (Fleury and Biere) goes further: it
looks at the learned clause one decision level at a time, and if a level contributes two or more
literals, it tries to replace all of them by a single literal from that level. It does the same
backwards walk as 1-UIP analysis, but restricted to one level: resolve away the latest literal of
that level until only one is left. That literal is a UIP of the block, and its negation replaces
the block. If the walk reaches a literal from a _lower_ level that is not already in the clause
and not removable by minimization, shrinking fails for this block and leaves it as it was.

#example(title: "Shrinking the level-2 block")[
  Sort the literals of $L_2 = (overline(i) or overline(a) or overline(d) or overline(e))$ by
  level: level 4: $overline(i)$ (the UIP), level 2: $overline(d)$, $overline(e)$, level 1:
  $overline(a)$. Only level 2 has more than one literal.

  Walk back on level 2: $e$ came from $C_3 = (overline(c) or e)$, giving $c$; $d$ came from
  $C_2 = (overline(c) or d)$, giving $c$ again. Only $c$ is left, so $c$ is the UIP of level 2,
  and the block ${overline(d), overline(e)}$ is replaced by $overline(c)$:

  $ L_3 = (overline(i) or overline(a) or overline(c)) $

  Shrinking the unminimized $L_1$ gives the same result: its level-1 block
  ${overline(a), overline(b)}$ shrinks to $overline(a)$ ($b$ was forced by $a$).

  Shrinking never changes which levels occur in the clause, because each block is replaced by a
  literal of its own level. So $L_1$, $L_2$ and $L_3$ all have literals on levels 4, 2 and 1.
  This matters for the jump back in the next section.
]

Why it helps: shorter clauses again, and literals that sit closer to the decisions, which tend
to be more general. Upstream it runs as one pass together with minimization (CaDiCaL
`shrink_and_minimize_clause`). Cost: one extra walk per level block, bounded in CaDiCaL by a
priority queue over trail positions (`shrinkreap`). Both CaDiCaL and kissat default to the full
variant (`shrink = 3`), which also calls minimization for lower-level literals met during the
walk.

#where[
  CaDiCaL: `shrink.cpp` (option `shrink`, default 3) · kissat: `shrink.c` (option `shrink`,
  default 3) · MiniSat: — · ksat port: not ported (the ports stop after recursive
  minimization)
]

== Backjumping

Now the solver undoes assignments. It does not just go back one level. It jumps to the
second-highest level among the learned clause's literals, the *backjump level*. At that level
all literals of the learned clause are false except the UIP literal, which is unassigned. So the
learned clause is unit and immediately forces the opposite of the UIP. The solver jumps as far
back as possible while keeping that property.

#example(title: "Jumping from level 4 to level 2")[
  Take the minimized clause $L_2 = (overline(i) or overline(a) or overline(d) or overline(e))$.
  Its literals live on these levels: $overline(i)$ on 4, $overline(d)$ and $overline(e)$ on 2,
  $overline(a)$ on 1. The second-highest level is 2, so the solver removes everything above
  level 2: $f, g$ (level 3) and $h, i, j, k$ (level 4). The trail is

  $ a@1, quad b@1 arrow.l C_1, quad c@2, quad d@2 arrow.l C_2, quad e@2 arrow.l C_3 $

  In $L_2$, $overline(a)$, $overline(d)$, $overline(e)$ are false and $i$ is unassigned, so
  $L_2$ is unit and forces $overline(i)@2$. Then $C_5 = (overline(h) or i)$ is unit too and
  forces $overline(h)@2$:

  $ dots, quad e@2 arrow.l C_3, quad overline(i)@2 arrow.l L_2, quad overline(h)@2 arrow.l C_5 $

  Which clause is actually added depends on the solver. The ksat ports minimize but do not
  shrink, so they add $L_2$. CaDiCaL and kissat shrink by default and would add
  $L_3 = (overline(i) or overline(a) or overline(c))$ instead (then $overline(i)@2 arrow.l L_3$).
  The backjump level is 2 in all cases, also for the unminimized $L_1$, and the forced literal
  is the same.

  The solver continues. It decides $f = 1$ (level 3, forcing $g$), then $j = 1$ (level 4).
  Now $C_8$ has $overline(j)$, $overline(b)$, $overline(e)$ false and forces
  $overline(k)@4 arrow.l C_8$. All variables are assigned and no clause is false: the model is
  $a = b = c = d = e = f = g = j = 1$, $h = i = k = 0$.
]

Why it helps: level 3 was not involved in the conflict. If every choice at level 4 failed,
plain backtracking would next flip $f$ at level 3, although $f$ had nothing to do with the
conflict; backjumping skips that. Note the price: the work spent on level 3 ($f$, $g$) is thrown
away and has to be redone. In this example it is two assignments; in real instances it can be
thousands, which is what chronological backtracking (below) addresses.

#where[
  CaDiCaL: `backtrack.cpp` (`Internal::backtrack`), `analyze.cpp` (`find_conflict_level`,
  `determine_actual_backtrack_level`) · kissat: `backtrack.c`, `learn.c` · MiniSat: `Solver.cc`
  (`cancelUntil`; the backjump level comes out of `analyze`) · ksat port: ported
]

== On-the-fly strengthening (OTFS)

During conflict analysis the solver resolves the current clause with reason clauses. Sometimes
the result is exactly the reason clause minus the literal just resolved on. Then the reason
clause itself can be made shorter: the formula implies the reason without that literal, so the
solver deletes the literal from the reason clause in place. This is *on-the-fly
self-subsumption*, or on-the-fly strengthening. The test is cheap because analysis already
counts sizes: if the resolvent is strictly smaller than the reason (counting only literals not
fixed at level 0), it must be the reason minus the pivot. The strengthened clause has all
literals false, so it becomes the new conflict clause and analysis restarts from it. If it has
only one literal on the conflict level, it is already asserting: the solver backjumps and uses
it as the reason directly, without adding any new clause.

Our running example does not trigger it (step 1 resolves with $C_7$, giving a resolvent of six
literals against a reason of four; step 2 uses the binary $C_6$, and the test requires more than
two literals). So here is a separate three-clause formula.

#example(title: "Strengthening a reason clause (separate toy formula)")[
  $D_1 = (overline(b) or c)$, $D_2 = (overline(a) or overline(c) or d)$,
  $D_3 = (overline(c) or overline(d))$.

  Decide $a@1$; nothing propagates. Decide $b@2$: $D_1$ forces $c@2$. Both $D_2$ and $D_3$
  watch $overline(c)$; assume the solver visits $D_2$ before $D_3$. Then $D_2$ forces $d@2$,
  and $D_3$ is false. Conflict. (The order matters: visiting $D_3$ first would force
  $overline(d)@2 arrow.l D_3$ and make $D_2$ the conflict. The reason resolved with would then
  be the binary $D_3$, and the test needs more than two literals, so no OTFS.)

  Resolve $D_3$ with the reason of $d$, which is $D_2$, on $d$: the result is
  $(overline(c) or overline(a))$, two literals, while $D_2$ has three. So
  $(overline(a) or overline(c))$ is exactly $D_2$ minus $d$, and $D_2$ is strengthened in place
  to $(overline(a) or overline(c))$. It has one level-2 literal ($overline(c)$), so the solver
  jumps back to level 1 and assigns $overline(c)@1 arrow.l D_2$.

  Plain 1-UIP would learn the same $(overline(a) or overline(c))$ as a _new_ clause and keep the
  old $D_2$, which is now subsumed (a superset of a known clause) and only wastes memory.
]

Why it helps: it shrinks original and learned clauses for free during analysis and avoids
storing redundant copies. Cost: the strengthened clause has to be re-watched (its watched literal
may be the one removed), and with proof output (a DRAT/LRAT certificate, chapter 6) the change
must be logged. If this happens on the first resolution step (CaDiCaL `analyze.cpp`:
`resolved == 1`, the same test in kissat's `deduce.c`) and the strengthened clause is also
smaller than the conflict clause, both clauses come straight from the clause database and the
strengthened one subsumes the conflict clause, so CaDiCaL and kissat delete the conflict clause.

#where[
  CaDiCaL: `analyze.cpp` (`on_the_fly_strengthen`, `otfs_strengthen_clause`; option `otfs`,
  default 1) · kissat: `deduce.c` (the test), `strengthen.c` (`kissat_on_the_fly_strengthen`,
  `kissat_on_the_fly_subsume`; option `otfs`) · MiniSat: — · ksat port: not ported
]

== Chronological backtracking

Backjumping throws away all levels above the backjump level, even the ones that had nothing to
do with the conflict. On large instances that can be thousands of assignments, which the solver
will often just recreate. *Chronological backtracking* (Nadel and Ryvchin) undoes only the
_last_ level and keeps the rest. The learned clause is still unit, but the forced literal now gets
the level it would have had after a backjump (the highest level of the clause's other
literals), even though it sits higher up on the trail.

#example(title: "Keeping level 3")[
  Instead of jumping to level 2, the solver backtracks only to level 3. The learned clause
  $L_2$ is unit as before and forces $overline(i)$, then $C_5$ forces $overline(h)$. Both get
  level 2, because all other literals of their reasons are on level 2 or below:

  $ a@1, quad b@1, quad c@2, quad d@2, quad e@2, quad f@3, quad g@3,
    quad overline(i)@2 arrow.l L_2, quad overline(h)@2 arrow.l C_5 $

  $f$ and $g$ survive. But the trail is no longer sorted by level: two level-2 literals come after
  level-3 ones. If the solver later backtracks to level 2, it must keep $overline(i)$ and
  $overline(h)$ and remove $f$, $g$ from the middle of the trail.
]

When is it used? Both CaDiCaL and kissat backjump by default and fall back to chronological
backtracking when the jump would skip more than 100 levels (CaDiCaL `chronolevelim`, kissat
`chronolevels`). CaDiCaL additionally has a trail-reuse rule (`chronoreusetrail`, on by default):
it keeps the levels up to the one that holds the best-scored variable among those it would undo,
capped at the last level. In our example that cap is level 3, so CaDiCaL 2.1.3 with default
options would actually keep level 3 here, while kissat (skipping only one level, well below 100)
jumps to level 2. MiniSat always backjumps.

Why it helps / cost: it saves re-propagating the skipped levels, which pays off on instances
with very deep trails. The price is complexity everywhere: propagation must compute the real
level of each forced literal, conflict analysis must first find the actual conflict level
(it may be below the current level), and backtracking must handle out-of-order literals.

#where[
  CaDiCaL: `analyze.cpp` (`determine_actual_backtrack_level`, `find_conflict_level`),
  `propagate.cpp` (`assignment_level`), `backtrack.cpp` (options `chrono`, `chronolevelim`,
  `chronoreusetrail`) · kissat: `learn.c` (`kissat_determine_new_level`; options `chrono`,
  `chronolevels`) · MiniSat: — · ksat port: not ported (the ports always backjump)
]

== Watched literals and blocking literals

Unit propagation has to notice the moment a clause becomes unit. Checking every clause after
every assignment would be far too slow. The *two-watched-literal* scheme (Chaff, 2001) uses one
observation: a clause can only become unit or false when one of its last two non-false literals
becomes false. So the solver watches two non-false literals per clause. For each literal $x$ it
keeps a watch list of the clauses that watch $overline(x)$. When $x$ becomes true it visits only
those clauses. For each visited clause:

+ If the other watched literal is true, the clause is satisfied; nothing to do.
+ Otherwise look for another literal that is not false. If there is one, watch it instead
  (move the clause to that literal's watch list).
+ If there is none, the clause is unit (the other watched literal is forced) or, if the other
  watched literal is false too, a conflict.

A nice property: on backtracking nothing has to be updated. Undoing assignments only turns false
literals back into unassigned ones, so two watched literals that were fine stay fine.

A *blocking literal* (Chu, Harwood and Stuckey) is a further shortcut. Each watch-list
entry stores, next to the clause reference, one other literal of the clause. If that literal is
true, the clause is satisfied and the solver skips it without loading the clause from memory at
all. Since memory access is the real cost of propagation, this saves a lot.

#example(title: "Watches on clause C7 during the run")[
  Assume the solver watches the first two literals of
  $C_7 = (overline(i) or overline(a) or overline(d) or k)$ as written, i.e. $overline(i)$ and
  $overline(a)$ (MiniSat actually sorts a clause's literals when adding it; the idea is the
  same).

  #table(
    columns: (auto, auto, 1fr),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Assignment*], [*Watched after*], [*What happens to $C_7$*],
    [$a@1$], [$overline(i)$, $overline(d)$],
      [$overline(a)$ became false. $overline(d)$ is unassigned, so the watch moves there.],
    [$b@1$, $c@2$], [unchanged], [Not in the watch lists of $b$ or $c$: not visited.],
    [$d@2$], [$overline(i)$, $k$],
      [$overline(d)$ became false. $overline(a)$ is false, $k$ is unassigned: the watch moves to $k$.],
    [$e$, $f$, $g$, $h$], [unchanged], [Not visited.],
    [$i@4$], [$overline(i)$, $k$],
      [$overline(i)$ became false. No replacement ($overline(a)$, $overline(d)$ false). The other
       watch $k$ is unassigned: unit, $k@4 arrow.l C_7$.],
  )

  Over nine assignments $C_7$ was opened three times. When $i$ became true, the watch entry's
  blocking literal was $overline(a)$ (the other watch at the time the entry was created), which
  is false, so the clause had to be loaded. MiniSat then stores $k$ as the new blocking literal
  of that entry, so a later visit while $k$ is true skips $C_7$ without touching it.
]

Why it helps: propagation cost depends on the number of clause visits, not the number of
clauses. An assignment only touches the one watch list of the literal that became false. Cost: two
watch entries per clause (plus the blocking literal), and the clause's literal order changes as
watches move. Binary clauses are special: both literals are always watched, and kissat stores
them only in the watch lists, with no separate clause in memory.

#where[
  CaDiCaL: `propagate.cpp`, `watch.hpp` (`Watch { clause, blit, size }`) · kissat: `proplit.h`,
  `watch.h` (binary clauses are watch-only) · MiniSat: `Solver.cc` (`propagate`), `Solver.h`
  (`Watcher { cref, blocker }`) · ksat port: ported, including blocking literals (the CaDiCaL
  port also has the saved-position replacement search)
]
