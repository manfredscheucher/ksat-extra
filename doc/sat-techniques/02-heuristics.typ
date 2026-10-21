#import "../lib/template.typ": note, warn, example, where

= Search heuristics

Chapter 1 left two questions open. When the solver has to make a decision, _which variable_
does it pick, and _which value_ does it give it? And when the search seems stuck, when should
it give up on the current trail and start over? The CDCL loop is correct for any answer, but
its speed depends almost entirely on these choices. This chapter goes through the heuristics
that answer them, from the classic ones every solver has (VSIDS, phase saving, restarts) to
the extra machinery in CaDiCaL and kissat (two search modes, rephasing, local search).

Two words are used throughout. A variable is _bumped_ when it takes part in conflict analysis
(it occurs in the learned clause or was resolved away while deriving it). The _glue_ (also
called LBD) of a learned clause is the number of different decision levels among its
literals; small glue means "this clause connects few decisions", which is a sign of a useful
clause.

A short preview of one more idea, because many sections below depend on it. CaDiCaL and kissat
switch back and forth between two _search modes_. In _focused_ mode they restart very often and
follow the latest conflicts closely (good for proving UNSAT). In _stable_ mode they restart
rarely and change direction slowly (good for finding models). Several heuristics below are used
in only one of the two modes; the section "Stable and focused mode" explains the modes in full.
MiniSat has only one mode.

== Choosing the next variable: VSIDS and EVSIDS

*Intuition.* Variables that showed up in recent conflicts are probably the ones that matter
right now. So every variable gets an activity score; conflict analysis adds to the score of
each bumped variable, and the next decision takes the unassigned variable with the highest
score. To make "recent" count more than "long ago", old score contributions must fade.

The original VSIDS (Chaff) divided all scores periodically. MiniSat introduced the trick that
everyone uses today, called EVSIDS (exponential VSIDS): instead of shrinking every score after
each conflict, grow the _increment_. After every conflict the increment is multiplied by
$1 / 0.95 approx 1.0526$. A bump from the current conflict is then worth $1/0.95$ times a bump
from the previous conflict, which is the same ranking as "multiply all scores by 0.95, then add
1", but costs one multiplication instead of touching every variable.

#example(title: "EVSIDS scores over three conflicts")[
  Four variables $a, b, c, d$ start with score 0, increment 1, factor $f = 1/0.95$.

  #table(
    columns: 4,
    align: (left, left, left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*conflict*], [*bumped*], [*scores after bumping*], [*new increment*]),
    [1], [$a, b$], [$a = 1, b = 1$], [$1.0526$],
    [2], [$b, c$], [$b = 2.0526, c = 1.0526$], [$1.1080$],
    [3], [$a, c$], [$a = 2.1080, c = 2.1607, b = 2.0526$], [$1.1664$],
  )

  Final ranking: $c > a > b > d$. Both $a$ and $c$ were bumped twice, but $c$'s bumps are more
  recent, so it wins. $b$ was also bumped twice and loses to both because its last bump was in
  conflict 2. The "decay everything" view gives $a = 1.9025$, $b = 1.8525$, $c = 1.95$, which
  is exactly the table divided by $f^2$: same order, as promised.
]

The scores grow without bound, so solvers rescale before they overflow a `double`: MiniSat
multiplies all activities (and the increment) by $10^(-100)$ when one exceeds $10^100$;
CaDiCaL and kissat use the limit $10^150$ and divide everything by the largest score (or by
the increment, if that is larger).

The unassigned variable with the highest score is found with a binary _max-heap_ keyed on the
score. Bumping a variable moves it up in the heap. Assigned variables are not removed eagerly:
when the top of the heap is already assigned it is popped and the next one is tried, and
unassigned variables are pushed back into the heap when backtracking unassigns them.

*Why it helps / cost.* VSIDS concentrates the search on the part of the formula that currently
produces conflicts, so learned clauses build on each other. The cost is $O(log n)$ per bump and
per pop, which is noticeable when conflicts involve hundreds of variables; that is one reason
for VMTF below.

#where[
  CaDiCaL: `analyze.cpp` (`bump_variable_score`, `scorefactor` = 950 per mille), `score.cpp`,
  `heap.hpp`; EVSIDS is used only in stable mode · kissat: `bump.c` (`decay` = 50 per mille,
  `MAX_SCORE` = 1e150), `heap.c`, `decide.c`; stable mode only · MiniSat: `Solver.h`
  (`varBumpActivity`, `varDecayActivity`), `Solver.cc` (`var-decay` = 0.95), used always ·
  ksat port: ported in all three (reason-side bumping, `bumpreason`/`bumpreasons`, is not)
]

== VMTF: the move-to-front queue

*Intuition.* VSIDS keeps a precise score; VMTF (variable move-to-front) keeps only an order.
All variables sit in a doubly linked list. When a variable is bumped it is moved to the front.
The next decision is the first unassigned variable from the front. There is no decay because
there is no score: whoever was bumped most recently is first, period.

Each variable carries a time stamp (`btab` in CaDiCaL, `stamp` in kissat) that increases with
every move to the front, so "in front of" is just "has a larger stamp". When one conflict bumps
several variables, both solvers first sort them by their _old_ stamp and then move them in that
order, so their relative order is kept.

#example(title: "Bumping two variables in a VMTF queue")[
  Queue from front to back, with stamps: $a (5), b (4), c (3), d (2), e (1)$.

  A conflict bumps $b$ and $d$. Sorted by old stamp: $d (2)$ first, then $b (4)$. Move $d$ to
  the front (stamp 6), then $b$ (stamp 7). New queue: $b (7), d (6), a (5), c (3), e (1)$.

  $b$ was in front of $d$ before and still is. If $a$ and $b$ are assigned, the next decision is
  $d$.
]

To avoid scanning assigned variables at the front over and over, the queue keeps a pointer to
the last place where an unassigned variable was found (`queue.unassigned` in CaDiCaL,
`queue.search` in kissat). When backtracking unassigns a variable with a larger stamp than the
pointer's variable, the pointer moves forward to it.

*Why it helps / cost.* A bump is $O(1)$ list surgery instead of a heap update, and the search
follows recent conflicts very aggressively. That aggressiveness suits "focused" search with
frequent restarts; the smoother VSIDS ranking suits long "stable" runs. This is why CaDiCaL
and kissat use both, one per mode (see stable and focused mode below).

#where[
  CaDiCaL: `queue.hpp`, `queue.cpp`, `analyze.cpp` (`bump_queue`), `decide.cpp`
  (`next_decision_variable_on_queue`); focused mode only · kissat: `queue.c`, `inlinequeue.h`,
  `bump.c` (`move_analyzed_variables_to_front_of_queue`), `decide.c`; focused mode only ·
  MiniSat: — · ksat port: ported (CaDiCaL and kissat)
]

== Phase saving

*Intuition.* VSIDS picks the variable; something must pick the value. Backjumping often throws
away large parts of the trail that were perfectly fine, only because they sat above the level
the solver jumps back to. Phase saving remembers, for each variable, the value it had the last
time it was assigned, and the next decision on that variable uses that value again. The solver
then quickly rebuilds the good parts of the old assignment instead of exploring the opposite
value.

#example(title: "Rebuilding a trail with saved phases")[
  Clauses $C_1 = (a or overline(b))$, $C_2 = (b or c)$, plus others not shown. The trail is
  $ overline(a)@1, quad overline(b)@1 arrow.l C_1, quad c@1 arrow.l C_2, quad dots $
  Later a conflict at level 5 produces a learned clause that sends the solver back to level 0,
  erasing all of this. The saved phases are now $a = 0, b = 0, c = 1$.

  When $a$ is decided again, it gets value 0 (saved), and propagation rebuilds
  $overline(b)$ and $c$ exactly as before. Without phase saving, CaDiCaL and kissat would give
  $a$ their default value, true (option `phase` = 1). With $a = 1$, $C_1$ is satisfied and
  nothing is forced, so the solver would wander into a different part of the search space.
  MiniSat's default value is false (it starts every variable with `polarity` = true, which in
  MiniSat means "use the negative literal"), so for MiniSat this particular decision would come
  out the same; with a saved value of 1 it would be the other way round.
]

When the phase is saved differs slightly: MiniSat saves it when a variable is unassigned
(`cancelUntil`, full phase saving `phase-saving` = 2 by default), CaDiCaL and kissat save it at
assignment time.

*Why it helps / cost.* Restarts and long backjumps become cheap, because the solver does not
lose the partial solution it had built. It costs one byte per variable and one store per
assignment. The risk is getting stuck: if the saved assignment is in a bad region, phase
saving keeps steering back into it. Rephasing (below) is the remedy.

#where[
  CaDiCaL: `propagate.cpp` (`phases.saved[idx] = tmp`), `decide.cpp` (`decide_phase`) ·
  kissat: `inlineassign.h` (`SAVED (idx)`), `decide.c` (`kissat_decide_phase`), option
  `phasesaving` · MiniSat: `Solver.cc` (`cancelUntil`, `pickBranchLit`) · ksat port: ported
]

== Target and best phases

*Intuition.* Phase saving remembers the _last_ value of every variable, including values from
a trail that was about to run into a conflict. A better memory is: "the assignment from the
longest trail that propagated without a conflict". That trail is the closest the solver has
come to a full model. CaDiCaL and kissat keep two such snapshots:

- the _target_ phases: a copy of the saved phases taken whenever the conflict-free trail is
  longer than the current target height. The target height is reset to 0 at every rephase,
  so the target follows recent progress;
- the _best_ phases: the same, but compared against the longest conflict-free trail ever seen
  (reset only when a rephase installs the best phases).

The snapshot is taken on backtrack. After a conflict, the trail of the conflicting level is
not conflict-free, so CaDiCaL measures up to `no_conflict_until` (the trail position reached
by the last conflict-free propagation), and kissat first undoes the conflict level and then
measures.

In stable mode, decisions use the target phase if one is set, otherwise the saved phase. The
best phases are not used directly; rephasing copies them into the saved phases.

#example(title: "Target and best heights")[
  A formula with 10 variables, in stable mode. Successive backtracks see conflict-free trails
  of length 4, 7, 5, 6:

  #table(
    columns: 4,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*conflict-free trail*], [*target height*], [*best height*], [*effect*]),
    [4], [4], [4], [copy to target and best],
    [7], [7], [7], [copy to target and best],
    [(rephase)], [0], [7], [target height reset],
    [5], [5], [7], [copy to target only],
    [6], [6], [7], [copy to target only],
  )

  After the rephase the target follows the new region of the search, while best still holds
  the 7-variable assignment, the best one so far.
]

*Why it helps / cost.* On satisfiable formulas the solver keeps steering back to its most
complete partial model, which is where solutions tend to be found. The cost is copying the phase array (one byte per
variable) whenever a new maximum is reached.

#where[
  CaDiCaL: `backtrack.cpp` (`update_target_and_best`), `phases.cpp`, `decide.cpp`; option
  `target` = 1 (use target phases in stable mode only) · kissat: `backtrack.c`
  (`kissat_update_target_and_best_phases`, stable mode only), `phases.c`, `decide.c`;
  `target` = 1 · MiniSat: — · ksat port: ported (CaDiCaL and kissat)
]

== Rephasing

*Intuition.* Phase saving and target phases make the search stubborn. Every so often, the
solver deliberately overwrites the saved phases to try a different region: all false, all
true, the best phases, a local search result, a random assignment. This is _rephasing_. Each
rephase is cheap (one pass over the phase array), and the schedule mixes "explore" steps
(original, inverted, flipped, random, walk) with "exploit" steps (best).

The rephase kinds, with the letter both solvers print in their log:

#table(
  columns: 2,
  inset: 5pt,
  stroke: 0.5pt + luma(180),
  table.header([*kind*], [*new saved phases*]),
  [O (original)], [the initial phase for every variable (option `phase`, default true)],
  [I (inverted)], [the opposite of the initial phase for every variable],
  [F (flipping)], [every saved phase negated (CaDiCaL only)],
  [\# (random)], [a random value per variable (CaDiCaL only)],
  [B (best)], [the best phases, where set],
  [W (walk)], [run local search starting from the current phases, keep its best assignment],
)

#example(title: "CaDiCaL rephase schedule and intervals")[
  CaDiCaL picks the schedule by mode. In stable mode with local search enabled (the default)
  it is
  $ O, I, (B, W, O, B, W, I)^omega $
  and in focused mode it is $F, (\#, B, W, F, B, W)^omega$ ($omega$ means "repeat forever").
  So the first stable-mode rephases install all-true, then all-false, then the best phases,
  then run a walk, and so on.

  The interval grows arithmetically: after the $k$-th rephase the next one is due
  $1000 dot (k + 1)$ conflicts later (`rephaseint` = 1000). If every rephase happens exactly
  on time, they occur after about 1000, 3000, 6000 and 10000 conflicts.
]

kissat rephases only in stable mode, with the fixed cycle $B, W, I, B, W, O$, and spaces them
by $1000 dot n dot (log_10(n + 9))^3$ conflicts after the $n$-th rephase (about 1000, 2258, 3770,
5529 for $n = 1, 2, 3, 4$). After each rephase kissat copies the new saved phases into the target
phases. In focused mode kissat has a lighter variant built into `kissat_decide_phase`: in
2 out of every 8 focused-mode episodes, every decision uses the original phase (episodes 2, 10,
18, ...) or the inverted phase (episodes 4, 12, 20, ...).

*Why it helps / cost.* Rephasing is mainly a win on satisfiable instances: it shakes the solver
out of a region it keeps returning to, and the B steps bring it back to the best region if the
exploration did not pay off. Except for walk, each step costs one pass over the variables.

#where[
  CaDiCaL: `rephase.cpp` (`rephase`, `rephase_best`, ...), options `rephase`, `rephaseint` =
  1000 · kissat: `rephase.c` (`rephase_schedule`), `decide.c` (focused-mode phases), options
  `rephase`, `rephaseinit` = `rephaseint` = 1000 · MiniSat: — · ksat port: not ported
  (neither the rephase schedules nor kissat's focused-mode forced phases)
]

== Stable and focused mode

*Intuition.* Two kinds of search work well on different formulas. _Focused_ search restarts
very often and follows the most recent conflicts closely (VMTF, Glucose-style restarts); it is
good at proving unsatisfiability. _Stable_ search restarts rarely and moves slowly (EVSIDS,
target phases, reluctant doubling restarts); it is good at finding models. Since the solver
cannot know in advance which kind of formula it has, CaDiCaL and kissat alternate between the
two modes, with growing time slices.

What switches together with the mode:

#table(
  columns: 3,
  inset: 5pt,
  stroke: 0.5pt + luma(180),
  table.header([], [*focused*], [*stable*]),
  [variable choice], [VMTF queue], [EVSIDS heap],
  [phase], [saved phase], [target phase, then saved],
  [restarts], [Glucose EMA, very frequent], [reluctant doubling (Luby), rare],
  [glue averages], [own set], [own set (swapped on switch)],
)

CaDiCaL calls focused mode "unstable" (the flag `stable` is false). Each mode has its own
glue averages, so a switch does not mix the statistics of the two kinds of search.

#example(title: "When CaDiCaL switches")[
  CaDiCaL starts in focused mode. The first switch happens after `stabilizeint` = 1000
  conflicts. Each later phase is twice as long as the previous one (`stabilizefactor` =
  200%):

  #table(
    columns: 3,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*conflicts*], [*mode*], [*length*]),
    [0 to 1000], [focused], [1000],
    [1000 to 3000], [stable], [2000],
    [3000 to 7000], [focused], [4000],
    [7000 to 15000], [stable], [8000],
  )
]

kissat also starts in focused mode for `modeinit` = 1000 conflicts, but measures the stable
phase differently: a stable phase lasts as many _ticks_ (a measure of propagation work) as the
preceding focused phase used. The next focused phase gets $1000 dot n dot (log_10(n + 9))^4$
conflicts, where $n$ counts the focused/stable pairs so far. Measuring stable mode in ticks
keeps the propagation work spent in the two modes roughly balanced.

*Why it helps / cost.* One configuration does well on both satisfiable and unsatisfiable
formulas, without the user having to choose. The cost is keeping both the VMTF queue and the
heap around (bumping only updates the one in use; kissat refills its heap with the unassigned
variables when it enters stable mode).

#where[
  CaDiCaL: `restart.cpp` (`stabilizing`), `internal.cpp` (initial limits), options
  `stabilize`, `stabilizeint` = 1000, `stabilizefactor` = 200 · kissat: `mode.c`
  (`kissat_switching_search_mode`, `update_mode_limit`), options `stable` = 1, `modeinit` =
  `modeint` = 1000 · MiniSat: — (one mode) · ksat port: ported (CaDiCaL and kissat)
]

== Restarts

*Intuition.* A restart backtracks to level 0 (or close to it, see trail reuse) while keeping
all learned clauses, scores and saved phases. With phase saving, the solver rebuilds most of
the old trail quickly, but in a new order determined by the current scores, so early decisions
that no longer look important get replaced. The question is _when_ to restart. Three schemes
are in use.

=== Luby restarts and reluctant doubling

The Luby sequence is $1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, dots$: each block repeats
everything before it and then doubles the last value. It comes from a classic result
(Luby, Sinclair and Zuckerman) on restarting randomized algorithms whose run-time
distribution is unknown. The solver multiplies it by a
base interval and restarts after that many conflicts.

#example(title: "Luby intervals in MiniSat and CaDiCaL")[
  MiniSat (`rfirst` = 100, `rinc` = 2, Luby on by default) restarts after
  $ 100, 100, 200, 100, 100, 200, 400, 100, dots $
  conflicts. The cumulative restart points are 100, 200, 400, 500, 600, 800, 1200.

  CaDiCaL and kissat compute the same sequence incrementally with Knuth's "reluctant doubling"
  bit trick: keep a pair $(u, v)$, starting with $(1, 1)$; at each step, if `(u & -u) == v`
  (the lowest set bit of $u$ equals $v$) then $(u, v) arrow.l (u + 1, 1)$, else
  $v arrow.l 2 v$. The successive values of $v$ are exactly the Luby sequence. With base
  period 1024 (`reluctant` in CaDiCaL, `reluctantint` in kissat), stable mode restarts after
  1024, 1024, 2048, 1024, 1024, 2048, 4096, ... conflicts. When $v$ reaches $2^20 = 1048576$
  (`reluctantmax` / `reluctantlim`), the sequence starts over.
]

MiniSat uses Luby restarts all the time. CaDiCaL and kissat use reluctant doubling only in
stable mode, which gives long quiet stretches between restarts.

=== Glucose-style EMA restarts

The Glucose solver observed: when recently learned clauses have much higher glue than usual,
the current trail is probably in a bad place, so restart. CaDiCaL and kissat implement this
with two exponential moving averages (EMAs) of the glue of learned clauses:

- a _fast_ average with window 33 (smoothing factor $alpha = 1/33$),
- a _slow_ average with window $10^5$ ($alpha = 10^(-5)$).

Each new glue $g$ updates an average by $x arrow.l x + alpha (g - x)$. A restart is triggered
when $"fast" >= 1.1 dot "slow"$ (`restartmargin` = 10%), and at least a minimum number of
conflicts have passed since the last restart (`restartint` = 2 in CaDiCaL; kissat uses 1, plus
a small logarithmic term that grows with the number of restarts).

Starting an EMA at 0 would bias it towards 0 for a long time (the slow one for about $10^5$
conflicts). Both solvers use the bias correction from the ADAM optimizer: they also track
$beta^t$ with $beta = 1 - alpha$ and report $x / (1 - beta^t)$. With this correction, the
first value is exactly the first glue.

#example(title: "A burst of high-glue clauses triggers a restart")[
  Toy version first, with $alpha = 1/2$ and no bias correction: glues 4, 4, 8 move the average
  $0 arrow 2 arrow 3 arrow 5.5$.

  Now the real parameters. The solver learns 1000 clauses of glue 4, then a run of clauses of
  glue 8. Both bias-corrected averages are exactly 4.000 after the first 1000 conflicts. Then:

  #table(
    columns: 5,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*conflict*], [*glue*], [*fast*], [*slow*], [*$1.1 dot "slow"$*]),
    [1001], [8], [4.121], [4.004], [4.404],
    [1002], [8], [4.239], [4.008], [4.409],
    [1003], [8], [4.353], [4.012], [4.413],
    [1004], [8], [4.463], [4.016], [4.418],
  )

  At conflict 1004 the fast average passes the limit and the solver restarts. The slow average
  barely noticed the burst; that is its job.
]

*Why it helps / cost.* Frequent restarts let the solver throw away bad early decisions while
the learned clauses keep the progress; the EMA rule restarts exactly when the clause quality
drops. In stable mode the opposite is wanted, long runs that can reach a model, hence the
reluctant doubling there. The cost of a restart itself is rebuilding the trail, which trail
reuse reduces.

#where[
  CaDiCaL: `restart.cpp` (`restarting`, `restart`), `reluctant.hpp`, `ema.hpp`, `ema.cpp`;
  options `restartint` = 2, `restartmargin` = 10, `emagluefast` = 33, `emaglueslow` = 1e5,
  `reluctant` = 1024, `reluctantmax` = 1048576 · kissat: `restart.c`, `reluctant.c`,
  `averages.c`, `smooth.c`; options `restartint` = 1, `restartmargin` = 10, `emafast` = 33,
  `emaslow` = 1e5, `reluctantint` = 1024, `reluctantlim` = 1048576 · MiniSat: `Solver.cc`
  (`luby`, `solve_`; `rfirst` = 100, `rinc` = 2) · ksat port: ported (Luby in MiniSat;
  Glucose EMA and reluctant doubling in CaDiCaL and kissat)
]

== Trail reuse on restart

*Intuition.* Right after a restart, the solver makes decisions in score order. If the first
few decisions on the old trail are exactly the variables it would pick again anyway, undoing
and redoing them is wasted work. Trail reuse (CaDiCaL's source credits Marijn Heule) asks:
"what is the next decision variable $x$ right now?" Every decision on the old trail with a
higher score (or newer VMTF stamp) than $x$ would be picked again before $x$, so those levels
are kept and the solver backtracks only to the first level whose decision ranks below $x$.

#example(title: "Reusing two levels")[
  Stable mode. The trail has four decision levels with decisions $a$ (score 9), $b$ (score 7),
  $c$ (score 4), $d$ (score 2). After the restart the best unassigned variable is $e$ with
  score 5.

  Levels 1 and 2 ($a$, $b$) have scores above 5, so a full restart would pick them again
  before $e$ anyway. Level 3 ($c$, score 4) ranks below $e$. The solver backtracks to level 2
  instead of level 0 and keeps the assignments of levels 1 and 2.
]

*Why it helps / cost.* It saves propagation work on every restart, which matters most in
focused mode where restarts happen every few conflicts. The search itself is almost the same
as with a full restart. The cost is one scan over the decision levels.

#where[
  CaDiCaL: `restart.cpp` (`reuse_trail`), option `restartreusetrail` = 1 · kissat:
  `restart.c` (`reuse_stable_trail`, `reuse_focused_trail`), option `restartreusetrail` = 1 ·
  MiniSat: — · ksat port: ported in kissat; the CaDiCaL port always restarts to level 0
]

== Reorder

*Intuition.* VSIDS and VMTF only learn from conflicts. Every so often kissat adds a static
opinion from the formula itself: a literal that occurs in many short clauses is important,
because assigning it false quickly forces other literals. `reorder` computes a weight per
variable from the irredundant (original, not learned) clauses and uses it to reshuffle the decision order.

The weight of a clause with $s$ unassigned literals is $2^(-(s - 2))$: 1 for a binary clause,
1/2 for a ternary clause, 1/4 for size 4, and so on (sizes are capped at `reordermaxsize` =
100). Each literal sums the weights of the clauses it occurs in; already satisfied clauses
are skipped. A variable's weight is $max(p, n) + 2 dot min(p, n)$ where $p$ and $n$ are the
weights of its positive and negative literal, so variables that occur in both polarities
count more.

#example(title: "Reorder weights")[
  Clauses $C_1 = (a or b)$, $C_2 = (overline(a) or c)$, $C_3 = (a or overline(b) or c)$,
  $C_4 = (overline(a) or overline(b) or overline(c))$.

  #table(
    columns: 4,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*variable*], [*$p$ (positive)*], [*$n$ (negative)*], [*weight*]),
    [$a$], [$1 + 0.5 = 1.5$ ($C_1, C_3$)], [$1 + 0.5 = 1.5$ ($C_2, C_4$)],
    [$1.5 + 2 dot 1.5 = 4.5$],
    [$b$], [$1$ ($C_1$)], [$0.5 + 0.5 = 1$ ($C_3, C_4$)], [$1 + 2 dot 1 = 3$],
    [$c$], [$1 + 0.5 = 1.5$ ($C_2, C_3$)], [$0.5$ ($C_4$)], [$1.5 + 2 dot 0.5 = 2.5$],
  )

  New preferred order: $a, b, c$. In focused mode kissat sorts the variables by increasing
  weight (ties broken by the old stamp) and moves each to the front of the VMTF queue, so
  $a$ ends up in front. In stable mode it first rescales all scores to at most 1 and then adds
  the weight to each score.
]

*Why it helps / cost.* It corrects the decision order when the conflict-driven scores have
drifted away from the structure of the formula. The cost is one pass over all irredundant
clauses plus a sort, done at level 0 every `reorderint` $times n$ conflicts (linear growth,
base 10000).

#where[
  CaDiCaL: — · kissat: `reorder.c` (`compute_weights`, `reorder_focused`, `reorder_stable`),
  options `reorder` = 2 (both modes), `reorderinit` = `reorderint` = 10000, `reordermaxsize` =
  100 · MiniSat: — · ksat port: not ported
]

== Warmup

*Intuition.* Local search (walk, below) starts from a full assignment, usually the current
decision phases. But those phases can be inconsistent with simple implications: $a = 1$ and
$c = 0$ while a binary clause $(overline(a) or c)$ says that $a$ implies $c$. kissat's
_warmup_ fixes the obvious problems before walking: it runs the normal decision procedure
(same variable order, same phases) and unit propagation over the whole formula, but it
ignores conflicts and keeps going until every variable is assigned. Each assignment updates the
saved phase. Then it backtracks to level 0 without touching target or best phases.

#example(title: "Warmup repairs an implied value")[
  Clauses $C_1 = (overline(a) or c)$ and $C_2 = (b or overline(c) or d)$. Assume the decision
  order is $a, b, c, d$ and no target phases are set, so decisions use the saved phases $a = 1, b = 0, c = 0, d = 1$. These
  falsify $C_1$.

  Warmup decides $a@1$ (saved value 1), and $C_1$ forces $c@1 arrow.l C_1$. Next it decides
  $overline(b)@2$; now $C_2$ has $b$ and $overline(c)$ false, so $d@2 arrow.l C_2$. All
  variables are assigned: $a = 1, b = 0, c = 1, d = 1$, which satisfies both clauses. The
  walker starts from this assignment instead of one with a falsified clause.
]

*Why it helps / cost.* The walker starts from fewer falsified clauses, so its flips go into
real conflicts instead of repairing implications. The cost is one full round of propagation,
much less than the walk itself.

#where[
  CaDiCaL: — · kissat: `warmup.c` (`kissat_warmup`), `propbeyond.c` (propagation that
  continues after conflicts), called from `walk.c`; option `warmup` = 1 · MiniSat: — · ksat
  port: not ported
]

== Random decisions

*Intuition.* Every heuristic so far is deterministic and self-reinforcing. A bit of randomness
can break a loop where the solver keeps making the same early decisions.

MiniSat has a simple version: with probability `rnd-freq` it picks a random variable from the
heap instead of the top one. The default is 0, so MiniSat makes no random decisions unless
asked.

kissat uses random decision _sequences_. In focused mode (by default not in stable mode),
once enough conflicts have passed, the next decision at level 1 (right after a restart or mode
switch) starts a sequence: for the next few conflicts every decision picks a random unassigned
variable. Phases still come from `kissat_decide_phase`. Switching into focused mode also
starts (or continues) a sequence.

#example(title: "kissat random decision sequences")[
  The first sequence may start after `randecinit` = 500 conflicts. The $n$-th sequence lasts
  $floor(10 dot log_10(n + 9))$ conflicts (`randeclength` = 10), which is 10 conflicts for
  $n = 1, 2, 3$. After the $n$-th sequence starts, the next may start
  $500 dot log_10(n + 9)$ conflicts later: 500, then 520, then 539.

  So in a typical focused run, about every 500 conflicts the solver spends 10 conflicts with
  random variable choices, then returns to VMTF.
]

*Why it helps / cost.* It diversifies the early decisions in focused mode. The cost is
negligible, but it makes runs depend on the random seed (`seed`), which matters if one wants
to compare traces.

#where[
  CaDiCaL: — (2.1.3 has no random decisions; randomness enters only via rephasing, walk and
  the optional `shuffle`) · kissat: `decide.c` (`next_random_decision`,
  `kissat_start_random_sequence`), `propsearch.c`, `mode.c`; options `randec` = 1,
  `randecfocused` = 1, `randecstable` = 0 · MiniSat: `Solver.cc` (`pickBranchLit`,
  `rnd-freq` = 0) · ksat port: not ported (the MiniSat port has no `rnd-freq` code; upstream
  default 0 behaves the same)
]

== Lucky phases

*Intuition.* Some formulas, even in competitions, are satisfied by trivial assignments: all
variables false, all true, or "set each variable to false and propagate". Before the real
search, CaDiCaL and kissat try a handful of such _lucky_ assignments. Each attempt is one pass
of decisions plus propagation; if it reaches a full assignment without conflict, the formula
is solved.

The CaDiCaL order is:
+ all false, if every clause contains a negative literal;
+ all true, if every clause contains a positive literal;
+ forward true: for $x_1, x_2, dots$ in index order, decide $x_i = 1$ if still unassigned,
  propagate, give up on a conflict;
+ forward false, backward false, backward true (same, other value or reverse order);
+ positive Horn: for each clause not yet satisfied, set its first positive literal true and
  propagate, then set the remaining variables false; negative Horn symmetrically. (The name
  comes from Horn clauses: clauses with at most one positive literal.)

kissat does the same constant checks, then forward false, forward true, backward false,
backward true (no Horn variants). Its forward/backward passes are a bit more forgiving: if a
decision fails, they try the opposite value, and a failure at level 1 becomes a learned unit.

#example(title: "Lucky forward assignment")[
  $C_1 = (a or b)$, $C_2 = (overline(a) or overline(b))$, $C_3 = (b or overline(c))$.

  All false fails ($C_1$ has no negative literal), all true fails ($C_2$ has no positive
  literal). CaDiCaL's forward true: decide $a@1$; $C_2$ forces
  $overline(b)@1 arrow.l C_2$; then $C_3$ forces $overline(c)@1 arrow.l C_3$. Every variable
  is assigned, no conflict: the model is $a = 1, b = 0, c = 0$.

  kissat's first non-constant attempt is forward false: $overline(a)@1$, then
  $b@1 arrow.l C_1$, then decide $overline(c)@2$. Also a model: $a = 0, b = 1, c = 0$.
]

*Why it helps / cost.* On the formulas where it works, it solves them instantly. On all others
it costs a few propagation passes over the formula, which is small compared to the search.

#where[
  CaDiCaL: `lucky.cpp` (`lucky_phases`, `forward_true_satisfiable`,
  `positive_horn_satisfiable`, ...), option `lucky` = 1 · kissat: `lucky.c` (`kissat_lucky`),
  options `lucky`, `luckyearly`, `luckylate` = 1 · MiniSat: — · ksat port: not ported
]

== Local search (walk) and how it feeds phases

*Intuition.* CDCL extends a partial assignment and never violates a clause. Local search does
the opposite: it starts with a full assignment that violates some clauses and repairs it by
flipping single variables. It cannot prove UNSAT, but it is very fast at finding models of
some satisfiable formulas. Modern CDCL solvers use it as a phase generator: run a short local
search, and copy the best assignment it found (fewest violated clauses) into the saved phases.

Both CaDiCaL and kissat implement ProbSAT, using the constants from Adrian Balint's thesis:

+ Start from the current decision phases (target, else saved).
+ Pick a falsified ("broken") clause. CaDiCaL picks one at random; kissat cycles through the
  list of broken clauses.
+ For each literal in it, compute the _break value_: how many currently satisfied clauses
  would become falsified if this literal were made true (clauses where the variable's current
  literal is the only true one).
+ Pick a literal at random, with probability proportional to $"cb"^(-"break")$, and flip it.
+ Whenever the number of broken clauses reaches a new minimum, remember the assignment.
  Stop at zero (a model) or when the effort limit is used up.

The constant cb is either 2 or a value fitted to the average clause length (2.5 at length 3,
2.85 at length 4, up to 7.4 at length 7, interpolated linearly); both solvers alternate
between the two on successive walks.

#example(title: "One ProbSAT step")[
  $C_1 = (a or b)$, $C_2 = (overline(a) or c)$, $C_3 = (overline(b) or overline(c))$,
  $C_4 = (overline(a) or overline(b) or c)$. Start: $a = b = c = 1$. Only $C_3$ is broken.

  Candidates in $C_3$: flip $b$ to 0 or flip $c$ to 0.
  - Flip $b$: $C_1$ is still satisfied by $a$, $C_4$ by $c$. Break value 0.
  - Flip $c$: $C_2$ and $C_4$ lose their only true literal. Break value 2.

  With cb = 2: weights $2^0 = 1$ and $2^(-2) = 0.25$, so $b$ is flipped with probability
  $1 / 1.25 = 0.8$ and $c$ with $0.2$. (With the fitted cb for average length 2.25, which is
  2.375, it is 0.849 versus 0.151.) Flipping $b$ gives $a = 1, b = 0, c = 1$, which satisfies
  all four clauses: the walk stops with a model. Flipping $c$ would have broken $C_2$ and
  $C_4$ and the walk would continue.
]

How the result is used: CaDiCaL writes every new minimum straight into the saved phases
(`walk_save_minimum`). kissat keeps the best assignment and, if it is better than the
starting one, copies it into the saved phases at the end (`export_best_values`), then rephase
copies saved into target. Either way, the next CDCL decisions follow the local search result,
and if it was a model, propagation will usually confirm it quickly. Walk is triggered as one of
the rephase steps (W).

*Why it helps / cost.* On satisfiable formulas, a few thousand flips can produce phases much
better than anything CDCL found. The effort is bounded relative to the search: CaDiCaL allows
`walkreleff` = 20 per mille of the search propagations (between `walkmineff` = $10^5$ and
`walkmaxeff` = $10^7$), kissat `walkeffort` = 50 per mille of the search ticks. Learned clauses
are ignored by default; the walk only looks at irredundant (original, not learned) clauses.

#where[
  CaDiCaL: `walk.cpp` (`walk`, `walk_round`, `walk_pick_lit`, `walk_break_value`,
  `walk_save_minimum`), options `walk` = 1, `walkreleff` = 20 · kissat: `walk.c`
  (`kissat_walk`, `pick_literal`, `export_best_values`), option `walkeffort` = 50 · MiniSat: —
  · ksat port: not ported
]

== Lookahead and cubing

*Intuition.* Lookahead solvers choose each decision by trying it out: for a candidate literal
$l$, assign it, propagate, measure how much got simplified, undo. The literal whose propagation
does the most work is likely a good split point. This is far too slow to run at every
decision of a CDCL solver, but it is the classic way to split a hard formula into many
independent sub-problems (_cube and conquer_): pick a split literal $l$, then split both
$l$ and $overline(l)$ again, down to some depth. Each leaf is a _cube_ (a conjunction of
literals), and each cube can be solved separately, for example in parallel, by passing it as
assumptions (temporary decisions forced by the caller, chapter 6) to a CDCL solver.

CaDiCaL's `lookahead` measures a probe by the trail size after propagating it. As probes it
takes literals $l$ whose negation $overline(l)$ occurs in a binary clause, because only those
trigger binary implications. A probe that propagates to a conflict is a _failed literal_:
$overline(l)$ is learned as a unit. Ties are broken by the VMTF stamp.

#example(title: "Choosing a split literal")[
  $C_1 = (overline(a) or b)$, $C_2 = (overline(a) or c)$, $C_3 = (overline(b) or d)$,
  $C_4 = (overline(c) or overline(e))$, $C_5 = (d or e or f)$.

  Probes (negation occurs in a binary clause) and their trail sizes after propagation:

  #table(
    columns: 3,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    table.header([*probe*], [*propagates*], [*trail size*]),
    [$a$], [$b, c$, then $d$ ($C_3$), $overline(e)$ ($C_4$)], [5],
    [$overline(d)$], [$overline(b)$ ($C_3$), then $overline(a)$ ($C_1$)], [3],
    [$e$], [$overline(c)$ ($C_4$), then $overline(a)$ ($C_2$)], [3],
    [$b$, $overline(b)$, $c$, $overline(c)$], [one more literal each], [2],
  )

  $a$ wins. Cubing to depth 1 gives the two cubes $(a)$ and $(overline(a))$; depth 2 would run
  lookahead again under each cube and split each of them once more.
]

*Why it helps / cost.* Lookahead gives well-balanced splits for parallel or distributed
solving, and failed literals found on the way simplify the formula. Each round propagates
every probe, so it is expensive; CaDiCaL runs it only on request (`Solver::lookahead`,
`Solver::generate_cubes`), never inside its normal search.

#where[
  CaDiCaL: `lookahead.cpp` (`lookahead_probing`, `lookahead_generate_probes`,
  `generate_cubes`) · kissat: — · MiniSat: — · ksat port: not ported
]

== The chapter at a glance

#table(
  columns: 5,
  inset: 5pt,
  stroke: 0.5pt + luma(180),
  table.header([*technique*], [*CaDiCaL*], [*kissat*], [*MiniSat*], [*ksat port*]),
  [EVSIDS heap], [stable mode], [stable mode], [always], [ported],
  [VMTF queue], [focused mode], [focused mode], [—], [ported],
  [phase saving], [yes], [yes], [yes], [ported],
  [target / best phases], [yes], [yes (stable)], [—], [ported],
  [rephasing], [yes], [stable only], [—], [not ported],
  [stable / focused switching], [yes], [yes], [—], [ported],
  [Luby / reluctant restarts], [stable], [stable], [always], [ported],
  [Glucose EMA restarts], [focused], [focused], [—], [ported],
  [trail reuse], [yes], [yes], [—], [kissat only],
  [reorder], [—], [yes], [—], [not ported],
  [warmup], [—], [yes], [—], [not ported],
  [random decisions], [—], [focused], [off by default], [not ported],
  [lucky phases], [yes], [yes], [—], [not ported],
  [walk], [yes], [yes], [—], [not ported],
  [lookahead / cubing], [on request], [—], [—], [not ported],
)
