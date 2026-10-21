#import "../lib/template.typ": note, warn, example, where

= Managing learned clauses

Chapter 1 showed that every conflict adds a learned clause. This chapter is about the other
half of that story: which learned clauses the solver throws away again, how it decides, and how
it cleans up memory afterwards. The techniques here do not change *what* the solver can prove.
They decide how fast it runs and whether it runs out of memory.

== Why learned clauses must be pruned

A learned clause is *redundant*: it follows from the original clauses, so deleting it never
changes whether the formula is SAT or UNSAT. That is what makes pruning safe. The original
clauses (CaDiCaL and kissat call them *irredundant*) are never deleted by this mechanism.

Pruning is also necessary. A CDCL solver learns one clause per conflict, and modern solvers
reach thousands of conflicts per second. Every stored clause costs memory, and every clause
that is watched costs time in unit propagation: when a watched literal becomes false, the
solver has to visit the clause. Most learned clauses are never useful again; a few are used
over and over. The job is to find the few.

#example(title: "Growth without pruning")[
  One clause per conflict means $10^6$ learned clauses after $10^6$ conflicts, usually far more
  than the original formula has. Each of them sits in two watch lists. Propagating a single
  literal may now have to visit thousands of clauses that will never become unit or conflicting,
  so each propagation gets slower while the search learns little from them.
]

All three solvers therefore run a *reduce* step from time to time: rank the learned clauses,
delete the less useful part, keep the rest. They differ in how they rank. CaDiCaL and kissat
use the clause's *glue* (next section); MiniSat uses a clause *activity*.

== LBD (glue): a quality score for learned clauses

Intuition: look at the decision levels of a clause's literals on the current trail. Literals
assigned at the same decision level are tied together: once the decision of that level is
made, propagation sets all of them. A clause whose literals sit on few distinct levels is
"almost unit" in many situations, because few decisions decide all of its literals. Such a
clause tends to propagate and to take part in conflicts often.

The *literal block distance* (LBD) of a clause is the number of distinct decision levels among
its literals. It was introduced by the Glucose solver; CaDiCaL and kissat call the same number
the *glue* (the literals of one level are "glued" together). Low glue means a good clause.

#example(title: "Computing the LBD on a trail")[
  Trail (decisions and propagations, see chapter 1):
  $a\@1$, $b\@1 arrow.l R_1$, $c\@2$, $d\@2 arrow.l R_2$, $e\@3$, $f\@3 arrow.l R_3$, $g\@4$
  ($R_1, R_2, R_3$ are some reason clauses, not shown).

  Two learned clauses of the same size:
  - $E_1 = (overline(b) or overline(c) or overline(d) or overline(f))$: levels
    $1, 2, 2, 3$, so three distinct levels, LBD $= 3$.
  - $E_2 = (overline(a) or overline(c) or overline(e) or overline(g))$: levels
    $1, 2, 3, 4$, so LBD $= 4$.

  This trail falsifies both clauses completely, so it is not a state the solver would continue
  from; we only use the trail to read off the levels of these clauses' literals.

  Both have four literals, but $E_1$ is the better clause: on this trail only three decisions
  matter for it, and $c$ and $d$ always come together.
]

The LBD is computed when the clause is learned. It can be recomputed later, when the clause is
used again on a different trail, and then it may be smaller (see "promotion" below). It is a
cheap measurement: one pass over the literals with a stamp per level.

#note(title: "Off by one in CaDiCaL and kissat")[
  The value both solvers *store* for a freshly learned clause is one less than the LBD above.
  CaDiCaL collects all levels seen in conflict analysis and stores
  `glue = levels.size () - 1` (`analyze.cpp`); kissat only collects the levels below the
  conflict level (`deduce.c`, `learn.c`). In both cases the level of the 1st UIP literal is not
  counted. For the learned clause $(overline(b) or overline(d) or overline(f))$ with UIP $f$ at
  level 3 on the trail above, the LBD is 3 and the stored glue is 2. A later recomputation
  (`recompute_glue`, `kissat_recompute_glue`) counts all levels. The thresholds below refer to
  the stored value.
]

#where[
  CaDiCaL: `analyze.cpp` (`analyze_literal`, `recompute_glue`) · kissat: `deduce.c`, `learn.c`,
  `promote.h` · MiniSat: — (activity instead) · ksat port: CaDiCaL and kissat ports
  compute and store the glue exactly like upstream (stored glue = levels $-$ 1).
]

== Tiers: keep, keep while used, reducible

Glue alone is not enough. A clause with glue 9 that was used in the last few conflicts is still
worth keeping; a clause with glue 3 that has not been touched for a long time may not be.
Modern solvers combine both signals in three *tiers*:

- *tier 1*, very low glue: kept (practically) forever.
- *tier 2*, medium glue: kept as long as it was used recently.
- *tier 3*, everything else: a candidate for deletion at every reduce.

"Used" means: the clause took part in conflict analysis (it was the conflicting clause or the
reason of a literal that analysis resolved on). Each clause carries a small `used` counter for
this. Using the clause sets the counter, and every reduce decrements it. So the counter answers
"was this clause used in the last one or two reduce intervals?".

In CaDiCaL the tier limits are fixed options: `reducetier1glue` $= 2$ and
`reducetier2glue` $= 6$ (`options.hpp`). Tier-1 membership is a flag on the clause, `keep`,
set when the clause is created with glue $<= 2$ (`clause.cpp`). A new learned clause starts
with `used` $= 2$ if its glue is $<= 6$ (tier 2) and `used` $= 1$ otherwise
(`analyze.cpp`: `res->used = 1 + (glue <= opts.reducetier2glue)`).

kissat computes its tier limits dynamically; that is the subject of the kissat section below.

#where[
  CaDiCaL: `options.hpp` (`reducetier1glue`, `reducetier2glue`), `clause.cpp` (`keep`),
  `clause.hpp` (tier comment) · kissat: `tiers.c`, `options.h` (`tier1`, `tier2`) ·
  MiniSat: — · ksat port: CaDiCaL port uses the limits 2 and 6; kissat port has
  dynamic tiers.
]

== The reduce step in CaDiCaL

A reduce is triggered by the conflict counter. The first one happens after `reduceint` $= 300$
conflicts; after the $k$-th reduce the next one comes $300 dot (k+1)$ conflicts later, so the
intervals grow (scaled up further by $log_(10)(n \/ 10^4)$ when there are more than $10^5$
irredundant clauses, `reduce.cpp`). Growing intervals mean the solver keeps more and more
learned clauses over time.

The reduce itself (`mark_useless_redundant_clauses_as_garbage`) works like this:

+ Skip irredundant clauses, clauses already marked as garbage, and reason clauses.
+ Read `used`, then decrement it. If it was non-zero, keep the clause (recently used).
+ If the clause has the `keep` flag (tier 1), keep it.
+ All remaining clauses are *candidates*. Sort them from least to most useful: larger glue
  first, and for equal glue larger size first (a stable sort, so among equal clauses the older
  one comes first and goes first).
+ Mark the first `reducetarget` $= 75$% of the candidates as garbage.

Marking as garbage does not free memory yet; garbage collection (later in this chapter) does.

#example(title: "One CaDiCaL reduce, by hand")[
  Nine learned clauses (glue is the stored value):

  #table(
    columns: 7,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*clause*], [*glue*], [*size*], [*used*], [*keep*], [*reason?*], [*outcome*],
    [$D_1$], [2], [3], [0], [yes], [no], [kept (tier 1)],
    [$D_2$], [5], [7], [2], [no], [no], [kept (used), used $arrow.r$ 1],
    [$D_3$], [5], [6], [0], [no], [no], [candidate],
    [$D_4$], [9], [11], [1], [no], [no], [kept (used), used $arrow.r$ 0],
    [$D_5$], [9], [10], [0], [no], [yes], [kept (reason)],
    [$D_6$], [9], [12], [0], [no], [no], [candidate],
    [$D_7$], [7], [8], [0], [no], [no], [candidate],
    [$D_8$], [12], [15], [0], [no], [no], [candidate],
    [$D_9$], [7], [10], [0], [no], [no], [candidate],
  )

  Five candidates, sorted least useful first: $D_8$ (glue 12), $D_6$ (glue 9), $D_9$ (glue 7,
  size 10), $D_7$ (glue 7, size 8), $D_3$ (glue 5). The target is
  $floor(0.75 dot 5) = 3$, so $D_8$, $D_6$ and $D_9$ are deleted; $D_7$ and $D_3$ survive this
  round.

  Next reduce, assuming none of the clauses is used in between and $D_5$ is still a reason:
  $D_2$ reads `used` $= 1$ and is kept one more time (then 0); $D_4$ now reads 0 and becomes a
  candidate. Candidates $D_4$, $D_7$, $D_3$; target $floor(0.75 dot 3) = 2$; $D_4$ and $D_7$
  are deleted. This is how a tier-2 clause ($D_2$, glue 5) gets two reduce rounds of grace
  while a tier-3 clause ($D_4$) gets one.
]

Why it helps: the glue ranking deletes the clauses that are least likely to propagate, and the
`used` counter rescues clauses that are bad on paper but useful right now. Cost: one pass over
all learned clauses plus a sort, a small fraction of the run time.

CaDiCaL also has a *flush* mode (option `flush`, off by default) that deletes every unused
learned clause regardless of glue.

#where[
  CaDiCaL: `reduce.cpp` (`reducing`, `mark_useless_redundant_clauses_as_garbage`, `reduce`),
  `options.hpp` (`reduceint` 300, `reducetarget` 75) · ksat port: `CaDiCaL.kt` `reduce()`.
  The port follows its shadow reference `ksat-extra/shadow/cadical-c/cadical_trace.cc`, which
  differs from upstream 2.1.3 here: no `keep` flag, a kissat-style used test (glue $<= 2$ kept
  only while `used` $> 0$, glue $<= 6$ kept while `used` $>= 1$; a use sets `used` to 2, a new
  learned clause starts at 1), and the next reduce after $25 dot sqrt("conflicts")$ conflicts
  (constant `OPT_reduceint = 25` in the reference). The glue/size ranking and the 75% target are
  as upstream.
]

== Dynamic tiers and reduce in kissat

kissat asks: which glues do the clauses that actually get used have? It keeps a histogram
`used[glue]`, incremented every time conflict analysis uses a learned clause of that glue
(`deduce.c`, separately for stable and focused mode). `tiers.c` picks the limits from this
histogram:

- tier1 = the smallest glue $g$ such that clauses with glue $<= g$ account for at least
  `tier1relative` $= 50$% of all uses;
- tier2 = the smallest glue $g$ such that clauses with glue $<= g$ account for at least
  `tier2relative` $= 90$% of all uses.

If the histogram is empty, the static defaults `tier1` $= 2$ and `tier2` $= 6$ are used.

The limits are recomputed at every reduce, and in addition on a separate conflict interval
(`update_tier_limits` in `analyze.c`): that interval starts at 2 conflicts and doubles after
each recomputation, up to $2^16 = 65536$ conflicts. So early in the run the limits follow the
histogram closely. (In kissat 4.0.4 the interval is checked in the branch of `kissat_analyze`
that restarts analysis after on-the-fly strengthening, chapter 1, so upstream it only fires on
such conflicts. The ksat port, following its shadow reference, checks it after every
conflict.)

Either way the tiers adapt to the instance: on a problem where good clauses naturally have
glue 10, tier 1 moves up instead of declaring everything "bad".

#example(title: "kissat tier limits from a use histogram")[
  Suppose learned clauses were used 100 times in total, distributed by glue:

  #table(
    columns: 10,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*glue*], [1], [2], [3], [4], [5], [6], [7], [8], [9],
    [*uses*], [10], [25], [20], [15], [10], [8], [5], [4], [3],
    [*accumulated*], [10], [35], [55], [70], [80], [88], [93], [97], [100],
  )

  50% of 100 is reached first at glue 3 (55), so tier1 $= 3$. 90% is reached first at glue 7
  (93), so tier2 $= 7$.
]

The reduce rule (`collect_reducibles` in `reduce.c`) then reads each learned clause's `used`
counter (5 bits, set to `MAX_USED` $= 31$ whenever the clause is used, decremented at every
reduce) and decides:

- reason clauses are skipped;
- glue $<= $ tier1 and `used` $> 0$: keep;
- glue $<= $ tier2 and `used` $>= 30$: keep (used since the last or the one before last reduce);
- everything else is a candidate, sorted by glue then size, largest first.

The fraction deleted is not fixed. With `reducelow` $= 50$% and `reducehigh` $= 90$% it is
$90 - 40 \/ log_(10)("reductions" + 9)$ percent: 50% at the first reduce, 70% at the 91st,
slowly approaching 90%. The interval between reduces is
`reduceint` $dot sqrt("reductions")$ conflicts with `reduceint` $= 1000$.

#example(title: "One kissat reduce with tier1 = 3, tier2 = 7")[
  #table(
    columns: 6,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*clause*], [*glue*], [*size*], [*used*], [*reason?*], [*outcome*],
    [$K_1$], [2], [4], [31], [no], [kept (tier 1, used)],
    [$K_2$], [3], [5], [0], [no], [candidate (tier 1 but unused)],
    [$K_3$], [6], [9], [31], [no], [kept (tier 2, recently used)],
    [$K_4$], [6], [8], [29], [no], [candidate (tier 2, not recent)],
    [$K_5$], [9], [14], [31], [no], [candidate (tier 3)],
    [$K_6$], [12], [20], [0], [yes], [kept (reason)],
  )

  Candidates sorted: $K_5$, $K_4$, $K_2$. At the first reduce the fraction is 50%, so
  $floor(3 dot 0.5) = 1$ clause is deleted: $K_5$. Note that $K_5$ was used recently and is
  still the first to go: in kissat, tier 3 gets no protection from `used` at all.
]

Two consequences of the counter: a tier-1 clause survives 31 reduces without being used, a
tier-2 clause survives 2. So kissat's tier 1 is "keep for a very long time", not "forever".

Binary learned clauses never take part: kissat stores them only in the watch lists, not in the
clause arena, and `collect_reducibles` only scans the arena.

#note(title: "Which tier limit is used")[
  kissat keeps separate limits for stable and focused mode, but in 4.0.x the macros in
  `internal.h` read `TIER1` from the focused-mode slot and `TIER2` from the stable-mode slot
  (the per-mode variant sits in an `#if 0` block). The ksat port reproduces this.
]

#where[
  kissat: `tiers.c` (`compute_tier_limits`), `reduce.c` (`collect_reducibles`,
  `mark_less_useful_clauses_as_garbage`), `deduce.c` (`mark_clause_as_used`), `options.h`
  (`tier1relative` 500, `tier2relative` 900, `reducelow` 500, `reducehigh` 900, `reduceint`
  1000, per mille where applicable) · ksat port: `Kissat.kt` `computeTierLimits`, `reduce()`,
  same rules and fractions.
]

== Activity-based reduceDB in MiniSat

MiniSat 2.2.0 predates LBD. It ranks learned clauses by *activity*, the same idea as VSIDS for
variables (chapter 2): every time a learned clause takes part in conflict analysis, its activity
grows by `cla_inc`, and `cla_inc` itself grows by a factor $1 \/ 0.999$ after every conflict
(`clause_decay` $= 0.999$). So recent use counts more than old use. Activities are rescaled by
$10^(-20)$ when one exceeds $10^20$.

`reduceDB` is called when the number of learned clauses (minus the number of assigned
literals) reaches `max_learnts`. That limit starts at one third of the number of original
clauses and grows by a factor 1.1 at increasingly spaced conflict counts.

The rule (`Solver.cc`):

+ Sort the learned clauses: non-binary clauses by increasing activity, binary clauses last.
+ Let $n$ be the number of learned clauses and `extra_lim` $= $ `cla_inc` $\/ n$.
+ Walk the sorted list. Delete clause $i$ if it has more than 2 literals, is not *locked* (the
  reason of a current assignment), and either lies in the first half ($i < n\/2$) or has an
  activity below `extra_lim`.

#example(title: "One MiniSat reduceDB")[
  Eight learned clauses, `cla_inc` $= 8$, so `extra_lim` $= 8 \/ 8 = 1.0$:

  #table(
    columns: 5,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*sorted pos.*], [*clause*], [*size*], [*activity*], [*outcome*],
    [0], [$M_7$], [4], [0.3], [kept (locked)],
    [1], [$M_1$], [3], [0.5], [deleted (first half)],
    [2], [$M_4$], [4], [0.9], [deleted (first half)],
    [3], [$M_8$], [5], [0.95], [deleted (first half)],
    [4], [$M_5$], [6], [0.97], [deleted (activity $< 1.0$)],
    [5], [$M_3$], [5], [4.0], [kept],
    [6], [$M_6$], [3], [7.0], [kept],
    [7], [$M_2$], [2], [0.1], [kept (binary)],
  )

  $M_2$ has the lowest activity of all but is binary, so it is sorted last and never deleted.
  $M_5$ is in the second half but its activity is below `extra_lim`.
]

Compared with the glue-based reduce: activity measures "used recently", which CaDiCaL and
kissat cover with the `used` counter, but it has no notion of how close to unit a clause
typically is. Glucose showed that LBD is the better predictor, which is why later solvers
switched.

#where[
  MiniSat: `Solver.cc` (`reduceDB`, `reduceDB_lt`, `search` for the trigger), `Solver.h`
  (`claBumpActivity`, `locked`) · ksat port: `MiniSat.kt` `reduceDB()`, same rule, with a
  stable insertion sort using the same comparator; clause activity precision is a knob
  (32-bit float like upstream by default).
]

== The used flag and promotion

When conflict analysis resolves on a learned clause, CaDiCaL and kissat do two things with it:
mark it as used, and recompute its glue on the *current* trail. The trail has changed since the
clause was learned, and the clause's literals may now sit on fewer levels. If the new glue is
smaller, the clause gets the new glue; this is called *promotion*, because it can move the clause
into a better tier.

In CaDiCaL (`bump_clause` in `analyze.cpp`, `promote_clause` in `clause.cpp`):

- `used` is set to 1;
- clauses already marked `keep` are left alone;
- if the recomputed glue is smaller: new glue $<= 2$ sets `keep` (promoted to tier 1); a move
  from above 6 to $<= 6$ sets `used` $= 2$ (promoted to tier 2);
- otherwise, a tier-2 clause that was already used gets `used` $= 2$.

In kissat (`mark_clause_as_used` in `deduce.c`, `kissat_promote_clause` in `promote.c`) `used`
is set to 31, and promotion only lowers the stored glue. Since tiers are derived from the glue at
each reduce, that is enough. The use is also counted in the histogram that drives the dynamic
tiers.

#example(title: "A clause promoted from tier 2 to tier 1 (CaDiCaL)")[
  $D = (overline(a) or overline(b) or overline(c) or overline(d))$ was learned on a trail with
  $a\@1$, $b\@2$, $c\@3$ and the UIP $d$ at level 4. Four distinct levels, stored glue
  $4 - 1 = 3$: tier 2, no `keep`, `used` $= 2$.

  Much later the trail is $a\@1$, $b\@1 arrow.l R_4$, $c\@2$, $overline(d)\@2 arrow.l D$
  ($R_4$ some reason clause),
  and a conflict analysis resolves on $d$, so it uses $D$. Recomputed glue: levels
  $1, 1, 2, 2$, so 2. Since $2 < 3$ and $2 <= 2$, $D$ gets glue 2 and the `keep` flag. From now
  on no reduce will delete it.
]

Why it helps: the glue measured at learning time is a single sample. A clause that keeps showing
up in conflicts with a low glue is evidence that it is a good clause, and promotion makes the
ranking reflect that. Cost: one pass over the clause per use, with a stamp per level.

#where[
  CaDiCaL: `analyze.cpp` (`bump_clause`, `recompute_glue`), `clause.cpp` (`promote_clause`) ·
  kissat: `deduce.c`, `promote.c`, `promote.h` · MiniSat: `claBumpActivity` plays the "used"
  role, no promotion · ksat port: CaDiCaL and kissat ports recompute the glue and promote; in the
  CaDiCaL port every use sets `used` to 2, and promotion only lowers the glue (no `keep` flag,
  see the reduce section).
]

== Protecting reason clauses

A learned clause can be the reason of a literal that is currently on the trail. Conflict
analysis may need that reason later: it walks backwards through the trail and resolves with the
reason of each literal it meets. If the clause had been deleted, the reason pointer would point
to freed memory.

So before a reduce marks anything as garbage, CaDiCaL walks the trail and sets a `reason` flag on
every clause that is the reason of an assigned literal (`protect_reasons` in `collect.cpp`);
kissat does the same with `kissat_mark_reason_clauses` (`trail.c`). The reduce skips flagged
clauses, and the flags are cleared again after garbage collection. MiniSat does not keep a flag;
it checks `locked(c)`: clause $c$ is locked if its first literal is true and its variable's
reason is $c$ (the propagated literal always sits at position 0).

#example(title: "A reason clause that must survive")[
  Trail $a\@1$, $c\@2$, $overline(d)\@2 arrow.l D'$ with the learned clause
  $D' = (overline(d) or overline(a) or overline(c))$. Even if $D'$ has the worst glue and has
  never been used, it is not deleted while $overline(d)$ stays on the trail: a conflict at level
  2 that involves $d$ would resolve with $D'$. After a backtrack below level 2 it is an
  ordinary candidate again. In the CaDiCaL example above, $D_5$ is such a clause.
]

Root-level literals are the exception. Conflict analysis skips literals assigned at level 0
(they are facts), so their reasons are not needed. That is why MiniSat's `removeClause` may
delete a locked clause at level 0: it simply clears the variable's reason first.

#where[
  CaDiCaL: `collect.cpp` (`protect_reasons`, `unprotect_reasons`) · kissat: `trail.c`
  (`kissat_mark_reason_clauses`, `kissat_unmark_reason_clauses`) · MiniSat: `Solver.h`
  (`locked`), `Solver.cc` (`removeClause`) · ksat port: all three ports protect reasons.
]

== Root-level simplification

Assignments at decision level 0 are permanent: they follow from the formula without any
decision (units, see chapter 1). Every clause can be simplified against them:

- a clause containing a literal that is true at level 0 is *satisfied forever* and can be
  deleted;
- a literal that is false at level 0 can be removed from its clause.

Both are safe: the formula stays equivalent under the permanent assignments.

#example(title: "Simplifying with the root units a = 1, b = 0")[
  - $(a or c or d)$: $a$ is true, the clause is deleted.
  - $(b or c or overline(e))$: $b$ is false, the clause becomes $(c or overline(e))$.
  - $(overline(a) or d or e or f)$: $overline(a)$ is false, it becomes $(d or e or f)$.
  - $(overline(b) or g)$: $overline(b)$ is true, the clause is deleted.
  - $(c or d)$: unchanged.

  Two clauses fewer, two clauses shorter. Each deleted clause also leaves two watch lists, so
  propagation gets cheaper.
]

The three solvers do this at different moments:

- CaDiCaL: `mark_satisfied_clauses_as_garbage` (`collect.cpp`), run at the start of every
  reduce and garbage collection, but only if new root units appeared since the last time. It
  marks satisfied clauses as garbage and removes falsified literals (`remove_falsified_literals`).
  This covers original and learned clauses.
- kissat: the sparse garbage collection (next section) does it while it copies clauses: a
  clause with a root-true literal is dropped, root-false literals are not copied.
- MiniSat 2.2.0: `simplify()` runs at level 0 when there are new root assignments and enough
  propagations have happened since the last call (`simpDB_props`). It only deletes satisfied
  clauses (learned ones always, original ones if `remove_satisfied` is on); falsified literals
  stay in their clauses.

#where[
  CaDiCaL: `collect.cpp` (`mark_satisfied_clauses_as_garbage`, `remove_falsified_literals`) ·
  kissat: `collect.c` (`sparse_sweep_garbage_clauses`) · MiniSat: `Solver.cc` (`simplify`,
  `removeSatisfied`) · ksat port: MiniSat port has `simplify`/`removeSatisfied` (it runs on every
  new root assignment, the `simpDB_props` throttle is not ported, and following its shadow
  reference it also trims root-false literals beyond the two watched positions). The CaDiCaL and
  kissat ports drop root-satisfied clauses and root-false literals only when a clause is added,
  not during search.
]

== Garbage collection and arena compaction

Marking a clause as garbage only flags it. *Garbage collection* actually removes it: take the
clause out of the watch lists, free its memory, and fix everything that refers to clauses.

The solvers keep clauses in an *arena*: one big array, where each clause is a header followed by
its literals, and a clause reference is just an offset into that array. This is compact and
cache friendly, and offsets are smaller than pointers. The price: deleting clauses leaves holes.
Collection *compacts* the arena by sliding the surviving clauses together, which changes their
offsets, so every watch and every reason reference must be updated.

#example(title: "Compacting an arena (illustrative layout: 1 header word + 1 word per literal)")[
  #table(
    columns: 5,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*clause*], [*literals*], [*garbage?*], [*offset before*], [*offset after*],
    [$A_1$], [3], [no], [0], [0],
    [$A_2$], [4], [yes], [4], [–],
    [$A_3$], [2], [no], [9], [4],
    [$A_4$], [5], [yes], [12], [–],
    [$A_5$], [3], [no], [18], [7],
  )

  The arena shrinks from 22 to 11 words. A watch entry that said "clause at offset 18" must now
  say 7; the same for a reason pointer of a literal propagated by $A_5$.
]

How each solver does it:

- MiniSat: deleting a clause only adds its size to a "wasted" counter. When wasted memory exceeds
  `garbage_frac` $= 20$% of the arena (`checkGarbage`), `garbageCollect` allocates a fresh
  arena and `relocAll` copies every live clause over, rewriting watches, reasons, the learned
  list and the original list.
- CaDiCaL: allocates new clauses individually and, from the second collection on (`arenaing`),
  copies all surviving clauses into a fresh arena (`copy_non_garbage_clauses`). The copy order is
  chosen for locality (`arenatype` $= 3$: clauses watched by the same literal end up next to
  each other, in variable queue order), which makes propagation faster. Otherwise garbage is
  deleted in place (`delete_garbage_clauses`).
- kissat: one arena for all large clauses. The sparse collection slides clauses down in place,
  dropping garbage and root-satisfied clauses and root-false literals in the same pass, then
  rebuilds the watches. Learned clauses are kept at the end of the arena, so a reduce only sweeps
  from the first reducible clause onwards.

Why it helps: memory is returned, and the surviving clauses are packed together so propagation
touches fewer cache lines. Cost: a pass over all clauses and all watch lists, which is why it is
only done after a reduce or when enough memory is wasted.

#where[
  CaDiCaL: `collect.cpp` (`garbage_collection`, `copy_non_garbage_clauses`,
  `delete_garbage_clauses`), `arena.hpp` · kissat: `collect.c` (`kissat_sparse_collect`,
  `sparse_sweep_garbage_clauses`) · MiniSat: `Solver.cc` (`garbageCollect`, `relocAll`),
  `Solver.h` (`checkGarbage`) · ksat port: not ported as such; each port uses its own memory
  layout (parallel arrays indexed by clause handle). Deleted clauses are unwatched and dropped
  from the clause lists (CaDiCaL, MiniSat) or just left marked (kissat), and handles never move.
]

== Variable compaction

Over time many variables become *inactive*: fixed at the root, eliminated by preprocessing
(chapter 4), or replaced by an equivalent variable (chapter 5). They no longer appear in any
clause, but every per-variable array (values, levels, reasons, scores, watch lists, the decision
heap or queue) still has a slot for them. *Compaction* renumbers the active variables into a
contiguous range $1 dots n'$ and shrinks all those arrays.

Fixed variables get a special treatment in both CaDiCaL and kissat: the first fixed variable
keeps one slot, and every other fixed variable is mapped onto it, positively if it has the same
value and negated otherwise. The external variable numbers the user sees do not change; only the
internal map from external to internal variables is rewritten.

#example(title: "Compacting 8 variables")[
  Variables $1 dots 8$; variable 3 is fixed true, 6 is fixed false, 5 is eliminated.

  #table(
    columns: 9,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*old*], [1], [2], [3], [4], [5], [6], [7], [8],
    [*new*], [1], [2], [3], [4], [–], [$overline(3)$], [5], [6],
  )

  Six internal variables instead of eight. Variable 6 maps to the negation of the new variable 3:
  new 3 is true, so $overline(3)$ is false, which is exactly 6's value.
]

When it runs: CaDiCaL checks `compacting()` at level 0 and compacts when at least `compactmin`
$= 100$ variables and at least `compactlim` $= 100$ per mille (10%) of all variables are
inactive, at most every `compactint` $= 2000$ conflicts. kissat decides at each reduce: if more
than `compactlim` $= 10$% of the variables are inactive, the sparse collection also maps all
literals while it copies the clauses.

Why it helps: smaller arrays, better cache use, and the heap or queue no longer carries dead
entries. It matters most after heavy preprocessing, which can remove a large share of the
variables.

#where[
  CaDiCaL: `compact.cpp` (`compacting`, `compact`, `Mapper`), `options.hpp` (`compact`,
  `compactint`, `compactlim`, `compactmin`) · kissat: `compact.c`
  (`kissat_compact_literals`), `collect.c` (`kissat_compacting`), `options.h` (`compactlim`) ·
  MiniSat: — · ksat port: not ported (the ports run without inprocessing, so few
  variables become inactive).
]
