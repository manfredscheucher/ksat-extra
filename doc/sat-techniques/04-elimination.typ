#import "../lib/template.typ": note, warn, example, where

= Simplifying the formula I: removing clauses and variables

Chapters 1–3 took the formula as given and made the search fast. This chapter changes the
formula itself: it deletes clauses that are not needed, shortens clauses, and removes whole
variables. A smaller formula means fewer watches to visit, fewer clauses to propagate and fewer
variables to decide on. All techniques here are built from one operation, resolution, plus
some bookkeeping so the solver can still report a correct model at the end.

== Preprocessing and inprocessing

*Preprocessing* means simplifying the formula once, before the first decision. _Inprocessing_
means stopping the CDCL search from time to time (at decision level 0), simplifying the current
formula including what was learned so far, and then continuing the search.

- MiniSat 2.2.0 only preprocesses. `SimpSolver::solve_` calls `eliminate()` before the CDCL
  search starts (the core solver from chapter 1 never simplifies on its own).
- CaDiCaL mostly inprocesses. Its main loop in `internal.cpp` checks `subsuming ()`,
  `eliminating ()` and `conditioning ()` between conflicts, exactly like it checks
  `restarting ()` or `reducing ()`. Optional preprocessing rounds (`preprocess_round`) run
  `probe`, `elim` and `condition` before the search.
- kissat 4.0.x does both. `preprocess.c` runs initial rounds of probing (in `probe.c` this
  includes factorization from this chapter and several techniques from chapter 5) and the
  optional fast elimination of this chapter. `eliminate.c` is scheduled as inprocessing during
  search.

Inprocessing is more powerful than preprocessing because units and binary clauses learned
during search make more simplifications possible. It is also harder to get right, because the
learned clauses, the watches and the trail all have to stay consistent with a formula that
keeps changing.

Two words we need throughout:

- Two formulas are *equivalent* if they have exactly the same models. Removing a subsumed clause
  (below) keeps the formula equivalent.
- Two formulas are *equisatisfiable* if one is satisfiable exactly when the other one is.
  Removing a variable or a blocked clause only keeps the formula equisatisfiable: the
  simplified formula may have models that are not models of the original. Those models are
  repaired at the end (section "Model reconstruction"), which is why every technique below
  that is only equisatisfiable writes something onto a reconstruction stack.

== Resolution, the basic step

Take two clauses that contain the same variable with opposite signs, one with $a$ and one with
$overline(a)$. If $a = 1$, the second clause needs one of its other literals; if $a = 0$, the
first clause does. Either way, one of the "other" literals of the two clauses must be true. That
new clause is the *resolvent* on $a$ (also written $C_1 ⊗ C_2$ on $a$), and $a$ is
called the _pivot_.

#example(title: "Resolving two clauses")[
  $C_1 = (a or b)$ and $C_2 = (overline(a) or c)$. The resolvent on $a$ is $(b or c)$.
  Check: if $b = 0$ then $C_1$ forces $a = 1$, then $C_2$ forces $c = 1$. So $b or c$ holds in
  every model of $C_1 and C_2$.

  Resolving $C_1 = (a or b)$ with $C_3 = (overline(a) or overline(b))$ on $a$ gives
  $(b or overline(b))$, which is always true. Such a resolvent is *tautological*: it carries no
  information and is thrown away.
]

You already met resolution in chapter 1: conflict analysis is a chain of resolutions along the
trail. Here it is used the other way around, not to learn one clause but to rewrite the formula.
A resolvent is always implied by its two parents, so adding it never changes the models.

== Subsumption and strengthening

Clause $C$ *subsumes* clause $D$ if every literal of $C$ also appears in $D$. Then $D$ is
useless: whenever $C$ is satisfied, so is $D$. Deleting $D$ keeps the formula equivalent.

A close relative is *self-subsuming resolution* (also called _strengthening_): if $C$ and $D$
clash on exactly one literal, and the rest of $C$ is contained in $D$, then the resolvent of $C$
and $D$ is $D$ minus one literal. That resolvent subsumes $D$, so we can simply drop the literal
from $D$.

#example(title: "Subsumption and self-subsuming resolution")[
  $C_1 = (a or b)$, $C_2 = (a or b or c)$, $C_3 = (overline(a) or b or c)$,
  $C_4 = (overline(b) or d)$.

  - $C_1$ subsumes $C_2$ (both $a$ and $b$ are in $C_2$). Delete $C_2$.
  - $C_1$ and $C_3$ clash only on $a$, and the rest of $C_1$ (just $b$) is in $C_3$. The
    resolvent on $a$ is $(b or c)$, which is $C_3$ without $overline(a)$. So $C_3$ is
    strengthened to $(b or c)$.

  The result $(a or b), (b or c), (overline(b) or d)$ has exactly the same models as the
  original four clauses.
]

There are two directions to search:

- *Forward* subsumption starts from a clause $D$ and asks "is $D$ subsumed (or strengthened) by
  some other clause?". It walks the _occurrence lists_ of all literals of $D$ looking for
  smaller clauses. The occurrence list of a literal is the list of all clauses containing it;
  unlike watches (chapter 1), every literal of every clause is indexed.
- *Backward* subsumption starts from a (usually new or short) clause $C$ and asks "which other
  clauses does $C$ subsume?". It only needs the occurrence list of one literal of $C$, the one
  with the fewest occurrences, because any subsumed clause must contain all of $C$.

MiniSat uses backward subsumption: `backwardSubsumptionCheck` pops clauses from a
`subsumption_queue` and uses a 32-bit "abstraction" signature per clause to rule out most
candidates without comparing literals. CaDiCaL's main pass in `subsume.cpp` is forward (its
header comment explains why: only one literal per clause has to be connected), and it also
runs on learned clauses that are likely to be kept. During elimination CaDiCaL additionally
checks new resolvents backward (`backward.cpp`). kissat uses forward subsumption and
strengthening during elimination (`forward.c`).

Why it helps: subsumed clauses are pure overhead in propagation and in occurrence counts, and
shorter clauses propagate earlier. It is also the cleanup step after variable elimination,
which tends to produce resolvents that subsume each other. The cost is the occurrence-list
traversal, so all three solvers limit clause length and occurrence counts (for example kissat's
`subsumeclslim` and `subsumeocclim`).

#where[
  CaDiCaL: `subsume.cpp` (forward, `strengthen_clause`), `backward.cpp` (eager backward during
  elim), on-the-fly strengthening in `elim.cpp` · kissat: `forward.c` · MiniSat:
  `SimpSolver.cc` (`backwardSubsumptionCheck`, `strengthenClause`) · ksat port: not ported
]

== Bounded variable elimination

*Variable elimination* (also called DP resolution, after Davis and Putnam) removes a variable
$x$ completely: take every clause containing $x$, resolve it with every clause containing
$overline(x)$, keep all non-tautological resolvents, and delete all original clauses that
mention $x$. The result is equisatisfiable with the original.

The catch: with $p$ clauses containing $x$ and $n$ containing $overline(x)$ you get up to
$p dot n$ resolvents but only remove $p + n$ clauses. Doing this blindly blows up the formula.
*Bounded* variable elimination (BVE, popularized by the SatELite preprocessor) only eliminates
$x$ if the formula does not get bigger:

$ "non-tautological resolvents" <= p + n + "bound" $

with bound $= 0$ meaning "no more clauses than before". If the check fails, nothing is changed.

#example(title: "BVE that pays off")[
  $C_1 = (x or a)$, $C_2 = (overline(x) or b)$, $C_3 = (overline(x) or c)$, plus other clauses
  that do not mention $x$.

  Here $p = 1$ and $n = 2$. The resolvents are $C_1$ with $C_2$: $(a or b)$, and $C_1$ with
  $C_3$: $(a or c)$. Two resolvents $<= 1 + 2$, so $x$ is eliminated: the three clauses are
  replaced by $(a or b), (a or c)$. The formula lost a variable and a clause.
]

#example(title: "BVE that does not pay off")[
  $(x or a), (x or b), (x or c), (overline(x) or d), (overline(x) or e), (overline(x) or f)$.

  Now $p = n = 3$. Every pair gives a non-tautological resolvent: $(a or d), (a or e), dots,
  (c or f)$, nine in total. Nine $>$ six, so with bound 0 the solver leaves $x$ alone.
  (Eliminating it would still be sound, the formula just grows.)
]

In the examples all resolvents happened to be non-tautological. In real formulas many pairs
are tautological and do not count, and that is what makes BVE so effective on encodings with
lots of auxiliary variables (see the section on gates).

The bound is not fixed. CaDiCaL (`elim.cpp`, `elim_resolvents_are_bounded`) and kissat
(`resolve.c`, `eliminate.c`) start with 0 and, after an elimination round has tried all
candidates, increase it 0, 1, 2, 4, 8, 16 (`elimboundmax` / `eliminatebound`, both 16). MiniSat
uses `grow` (default 0) and never changes it. All three also refuse to create very long
resolvents (`elimclslim` 100 in CaDiCaL, `eliminateclslim` 100 in kissat, `cl-lim` 20 in
MiniSat). CaDiCaL and kissat also skip variables with too many occurrences (`elimocclim`,
`eliminateocclim`).

Why it helps: on structured instances BVE often removes a large fraction of the variables.
Fewer variables means fewer decisions, and the resolvents are usually shorter and denser. The
costs are the occurrence lists it needs (CDCL search only needs watches), the effort of trying
candidates, and the reconstruction bookkeeping: $x$ is gone, but the user still wants a value
for $x$ at the end.

#where[
  CaDiCaL: `elim.cpp` (+ `backward.cpp`) · kissat: `eliminate.c`, `resolve.c`, `weaken.c` ·
  MiniSat: `SimpSolver.cc` (`eliminateVar`, `merge`) · ksat port: not ported
]

== Fast elimination (fastel)

kissat 4.0.x has a second, cheaper elimination pass in `fastel.c`, called only from the
initial preprocessing in `preprocess.c`. It looks only at variables with few occurrences
(`fasteloccs` 100) and uses a different rule from the "not bigger" bound above: with $p$
positive and $n$ negative occurrences,

- if $p dot n <= 8$ (`fastelim`), eliminate right away without even counting;
- otherwise count non-tautological resolvents and eliminate if there are at most 8.

While collecting the occurrences it also drops satisfied clauses and runs a quick forward
subsumption check (`fastelsub`), and it repeats for up to `fastelrounds` (4) rounds.

#example(title: "fastel accepts what BVE would reject")[
  $(x or a), (x or b), (overline(x) or c), (overline(x) or d), (overline(x) or e),
  (overline(x) or f)$.

  $p = 2$, $n = 4$, $p dot n = 8 <= 8$, so fastel eliminates $x$ immediately. The result has 8
  resolvents ($(a or c), dots, (b or f)$) in place of 6 clauses. BVE with bound 0 would have
  refused ($8 > 2 + 4$).
]

So "fast" means: no scheduling heap, no gate detection, only a small fixed cap on resolvents,
in exchange for accepting a little growth. In the kissat 4.0.4 source the option `fastel` is
off by default (`options.h`), so you only get it with `--fastel=1`.

#where[
  CaDiCaL: — · kissat: `fastel.c` (called from `preprocess.c`) · MiniSat: — · ksat port: not
  ported
]

== Gates and definitions

Formulas produced from circuits or other encodings are full of *definitions*: auxiliary
variables whose value is a fixed function of other variables. The common ones and their clause
patterns:

#table(
  columns: (auto, auto),
  align: (left, left),
  [*Gate*], [*Clauses*],
  [Equivalence $x <=> a$], [$(overline(x) or a), (x or overline(a))$],
  [AND $x <=> a and b$], [$(overline(x) or a), (overline(x) or b), (x or overline(a) or overline(b))$],
  [XOR $x <=> a ⊕ b$], [$(overline(x) or a or b), (overline(x) or overline(a) or overline(b)), (x or overline(a) or b), (x or a or overline(b))$],
  [ITE $x <=>$ (if $c$ then $a$ else $b$)], [$(overline(x) or overline(c) or a), (overline(x) or c or b), (x or overline(c) or overline(a)), (x or c or overline(b))$],
)

Why gates matter for elimination: split the clauses with $x$ into the *gate clauses* $G$ (the
definition) and the rest $R$. One can show that it is enough to resolve gate clauses against
non-gate clauses. Gate-with-gate resolvents are tautological for these gates, and
non-gate-with-non-gate resolvents are implied by the others. Fewer resolvents means the bound
is met more often.

#example(title: "An AND gate makes elimination possible")[
  Gate $x <=> a and b$: $G_1 = (overline(x) or a)$, $G_2 = (overline(x) or b)$,
  $G_3 = (x or overline(a) or overline(b))$. Other clauses with $x$: $R_1 = (x or c)$,
  $R_2 = (x or f)$, $R_3 = (overline(x) or d)$, $R_4 = (overline(x) or e)$. Seven clauses.

  *Plain BVE:* positive $\{G_3, R_1, R_2\}$, negative $\{G_1, G_2, R_3, R_4\}$, 12 pairs. Only
  $G_3$ with $G_1$ and $G_3$ with $G_2$ are tautological, leaving 10 resolvents. $10 > 7$:
  rejected.

  *Gate-aware BVE:* only $G$ against $R$:
  - $G_3$ with $R_3, R_4$: $(overline(a) or overline(b) or d), (overline(a) or overline(b) or e)$
  - $R_1$ with $G_1, G_2$: $(a or c), (b or c)$; $R_2$ with $G_1, G_2$: $(a or f), (b or f)$

  6 resolvents $<= 7$: eliminated. The skipped resolvents such as $(c or d)$ (from $R_1$ and
  $R_3$) follow from the six: if $c = 0$ then $a = b = 1$, so $d = 1$.
]

You can read the six resolvents as "substitute the definition of $x$ into $R$": $R_1$ said
$x or c$, i.e. $(a and b) or c$, which is $(a or c) and (b or c)$. For an equivalence
$x <=> a$ this is literally replacing $x$ by $a$: $(x or c)$ becomes $(a or c)$.

How the solvers find gates:

- CaDiCaL (`gates.cpp`, `find_gate_clauses`) tries `find_equivalence`, `find_and_gate`,
  `find_if_then_else` and `find_xor_gate` by pattern matching on binary and ternary clauses.
  During resolution it skips pairs where both clauses are gate clauses or both are not
  (`c->gate == d->gate` in `elim_resolvents_are_bounded`).
- kissat (`gates.c`, `kissat_find_gates`) tries equivalence (`equivalences.c`), AND in both
  polarities (`ands.c`), if-then-else (`ifthenelse.c`) and finally a general definition
  (`definition.c`). There is no XOR pattern in kissat's elimination; XORs are used in
  congruence closure (chapter 5).
- MiniSat 2.2.0 does no gate detection.

kissat's `definition.c` finds definitions of any shape with a trick: remove $x$ and
$overline(x)$ from all clauses containing $x$ and hand the result to the small embedded
solver `kitten`. If that is unsatisfiable, the clauses in the unsatisfiable core are a
definition of $x$. In the example: removing $x$ leaves $(a), (b), (overline(a) or overline(b))$
from the gate and $(c), (f), (d), (e)$ from the rest. The first three are already
contradictory, so they form the core, and kitten has rediscovered the AND gate without knowing
what an AND gate is. For such general definitions kissat may also need gate-with-gate
resolvents (the `resolve_gate` flag in `resolve.c`).

#where[
  CaDiCaL: `gates.cpp` (used by `elim.cpp`) · kissat: `gates.c`, `ands.c`, `equivalences.c`,
  `ifthenelse.c`, `definition.c` (with `kitten.c`) · MiniSat: — · ksat port: not ported
]

== Blocked clause elimination

A clause $C$ is *blocked* on one of its literals $l$ if every resolvent of $C$ on $l$ (with
all clauses containing $overline(l)$) is tautological. Such a clause can be deleted and the
formula stays equisatisfiable. Intuition: the clauses with $overline(l)$ do not care whether
$l$ is true, because each of them is already satisfied by some other literal whenever $C$ is
falsified apart from $l$. So if a model falsifies $C$, flipping $l$ to true repairs $C$
without breaking anything.

A pure literal (no clause contains $overline(l)$) is the extreme case: every clause containing
$l$ is blocked, since there is nothing to resolve with.

#example(title: "A blocked clause and its repair")[
  $C_1 = (a or overline(b))$, $C_2 = (overline(a) or b)$, $C_3 = (a or c)$.

  Is $C_1$ blocked on $a$? The only clause with $overline(a)$ is $C_2$, and the resolvent is
  $(overline(b) or b)$, tautological. Yes. Delete $C_1$.

  The reduced formula $C_2, C_3$ has the model $a = 0, b = 1, c = 1$, which falsifies $C_1$. So
  the solver must remember "$C_1$, witness $a$". At the end: $C_1$ is false, flip $a$ to 1.
  Now $a = 1, b = 1, c = 1$: $C_1$ true (via $a$), $C_2$ true (via $b$), $C_3$ true.
]

Why it helps: blocked clauses are typically redundant pieces of encodings (for example one
direction of a definition whose other direction is all that is needed). Removing them makes
other variables easier to eliminate. BCE itself only deletes clauses (although deleting all
clauses of a pure literal leaves its variable unused).

CaDiCaL runs `block ()` inside `elim ()`, just before the elimination rounds, and only tries
literals whose negation recently disappeared from an irredundant clause (header comment of
`block.cpp`).
It has special fast paths for pure literals and literals with one negative occurrence. The
option `block` is off by default in CaDiCaL 2.1.3. kissat and MiniSat do not have BCE.

#where[
  CaDiCaL: `block.cpp` (option `block`, default off) · kissat: — · MiniSat: — · ksat port: not
  ported
]

== Covered clause elimination

Covered clause elimination (CCE) is a stronger version of BCE. Before checking whether $C$ is
blocked, it first *extends* $C$ with extra literals that can be added without changing
satisfiability, which makes it easier for the extended clause to become blocked (or
tautological). Two ways to add literals:

- *Covered literal addition* (CLA): look at all clauses with $overline(l)$ for some $l$ in $C$
  whose resolvent with $C$ is not tautological. If they all share some literal $m$ (besides
  $overline(l)$), add $m$ to $C$. Intuition: every way of using $overline(l)$ already needs
  $m$, so $C$ may as well "cover" it.
- *Asymmetric literal addition* (ALA): if the other clauses together with all literals of $C$
  being false force some literal $m$ to be false, add $m$ to $C$. This is unit propagation in
  disguise.

If the extended clause ends up blocked (or propagation hits a conflict), the original $C$ is
removed.

#example(title: "A covered clause")[
  $C_1 = (a or b)$, $C_2 = (overline(a) or c or d)$, $C_3 = (overline(a) or c or overline(d))$,
  $C_4 = (overline(c) or overline(b))$.

  $C_1$ is not blocked: on $a$ the resolvent with $C_2$ is $(b or c or d)$, on $b$ the
  resolvent with $C_4$ is $(a or overline(c))$.

  CLA on $a$: the clauses with $overline(a)$ are $C_2, C_3$; both contain $c$ (and $d$ appears
  with different signs). Add $c$: $C_1' = (a or b or c)$.

  Is $C_1'$ blocked on $c$? The only clause with $overline(c)$ is $C_4$, and the resolvent
  $(a or b or overline(b))$ is tautological. Yes. So $C_1$ is deleted.

  Two steps go on the reconstruction stack: first "$(a or b)$, witness $a$" (the CLA step),
  then "$(a or b or c)$, witness $c$". At the end they are undone newest first. The reduced
  formula $C_2, C_3, C_4$ has the model $a = b = c = d = 0$. Newest entry: $(a or b or c)$ is
  false, set $c = 1$. Next: $(a or b)$ is false, set $a = 1$. Result $a = 1, b = 0, c = 1,
  d = 0$, a model of all four clauses.
]

Note that $(a or b)$ and $(a or b or c)$ are not interchangeable in the formula: with
$C_2, C_3, C_4$ the assignment $a = 0, b = 0, c = 1$ satisfies the second but not the first.
CLA only preserves satisfiability, which is exactly why it needs reconstruction entries.

CaDiCaL implements the asymmetric variant (ALA plus CLA) in `cover.cpp` and runs `cover ()`
after `block ()` inside `elim ()`. It refuses CLA on frozen literals (`cover_propagate_covered`).
The option `cover` is off by default in 2.1.3.

#where[
  CaDiCaL: `cover.cpp` (option `cover`, default off) · kissat: — · MiniSat: — · ksat port: not
  ported
]

== Globally blocked clauses (conditioning)

For a blocked clause, the repair flips one literal of the clause. *Globally blocked* clauses
allow the repair to flip several literals, including variables that do not even occur in the
clause. CaDiCaL calls this _conditioning_ (`condition.cpp`, after Kiesl, Heule and Biere).

The idea uses an *autarky*: an assignment $omega$ that satisfies every clause it touches.
Setting an autarky can never hurt. Conditioning looks for a _conditional_ autarky: a partial
assignment $alpha$ (the condition) and an assignment $omega$ such that every clause touched by
$omega$ is satisfied either by $omega$ or by $alpha$. If $alpha$ consists of negations of
literals of $C$, and $omega$ satisfies some literal of $C$, then $C$ can be removed. Repair at
the end: if $C$ is false, set all literals of $omega$.

#example(title: "A clause repaired by flipping two variables")[
  $C_1 = (a or b)$, $C_2 = (overline(a) or c)$, $C_3 = (overline(b) or overline(c))$,
  $C_4 = (b or d)$.

  Take $alpha = \{b = 0\}$ (the negation of the literal $b$ of $C_1$) and
  $omega = \{a = 1, c = 1\}$. Check: $omega$ satisfies $a$ in $C_1$. $C_2$ is touched by
  $omega$ and satisfied by $c = 1$. $C_3$ is touched by $omega$ (via $c$) and not satisfied by
  $omega$, but it is satisfied by $alpha$ ($overline(b)$). $C_4$ is not touched by $omega$.
  So $C_1$ is globally blocked and is removed, with witness $\{a, c\}$.

  The reduced formula has the model $a = 0, b = 0, c = 0, d = 1$, which falsifies $C_1$.
  Flipping only $a$ would break $C_2$. Flipping the whole witness gives
  $a = 1, b = 0, c = 1, d = 1$, a model of all four clauses.
]

(This particular $C_1$ is also caught by CCE: CLA on $a$ adds $c$, and $(a or b or c)$ is
blocked on $c$. The example is chosen small, not to show a case only conditioning finds.)

CaDiCaL does not search for $alpha$ and $omega$ from scratch. It uses the current partial
assignment of the CDCL search, splits it into a conditional part and an autarky part, and
then refines that split for each candidate clause. It is triggered during search when the
decision level is above the average backjump level. This was the first technique in CaDiCaL
that needs witnesses with more than one literal on the reconstruction stack. The option
`condition` is off by default in 2.1.3.

#where[
  CaDiCaL: `condition.cpp` (option `condition`, default off) · kissat: — · MiniSat: — ·
  ksat port: not ported
]

== Instantiation

Instantiation shortens a clause instead of deleting it. For a literal $l$ in clause $C$:
assume $l$ true and every other literal of $C$ false, then run unit propagation. If that
leads to a conflict, then $l$ can be removed from $C$. Reason: the conflict shows that the
formula implies "$overline(l)$ or one of the other literals of $C$", and resolving that with
$C$ itself on $l$ gives $C$ without $l$.

#example(title: "Removing a literal by instantiation")[
  $C_1 = (a or b or c)$, $C_2 = (overline(a) or d)$, $C_3 = (overline(a) or b or overline(d))$.

  Try $a$ in $C_1$: assume $a = 1, b = 0, c = 0$. $C_2$ forces $d = 1$, then $C_3$ has all
  literals false: conflict. So $C_1$ becomes $(b or c)$, and the formula is equivalent to the
  original.

  Now $a$ only occurs as $overline(a)$, so $a$ is a pure literal and the next elimination
  round removes it for free.
]

That last effect is the point of CaDiCaL's version (`instantiate.cpp`): candidates are
literals with few occurrences, on variables where elimination just failed, collected at the
end of an elimination round (`elim_round` in `elim.cpp` calls
`collect_instantiation_candidates`). Removing
a rare literal can turn a variable pure. The clause must have at least three unassigned
literals. The option `instantiate` is off by default in 2.1.3.

#where[
  CaDiCaL: `instantiate.cpp` (option `instantiate`, default off) · kissat: — · MiniSat: — ·
  ksat port: not ported
]

== Bounded variable addition (factorization)

This is elimination run backwards: introduce a new variable if that makes the formula
smaller. If the clauses form a "product", every literal from a set $L$ combined with every
literal from a set $K$, then $|L| dot |K|$ clauses can be replaced by $|L| + |K|$ clauses using
one fresh variable $x$.

#example(title: "Factoring nine clauses into six")[
  The nine clauses $(a or d), (a or e), (a or f), (b or d), dots, (c or f)$ say
  "$a, b, c$ all true, or $d, e, f$ all true". With a fresh $x$:
  $ (a or x), (b or x), (c or x), (overline(x) or d), (overline(x) or e), (overline(x) or f) $
  If $x = 0$ the first three force $a, b, c$; if $x = 1$ the last three force $d, e, f$. The
  models restricted to $a dots f$ are exactly the original ones. 9 clauses become 6.
]

Notice that eliminating $x$ from the six clauses produces exactly the nine clauses again (9
resolvents for 6 clauses). That is why kissat only factors when the reduction is larger than
the current elimination bound (`reduction > factoring.bound` in `run_factorization`, where the
bound is the elimination's `additional_clauses`); otherwise BVE would immediately undo it.

kissat's `factor.c` runs during probing (`probe.c`, also in the initial preprocessing). It
searches for such products among clauses up to size `factorsize` (5),
greedily picking the factor that removes the most clauses (`best_quotient`). Fresh variables
need no reconstruction: any model of the new formula, with $x$ ignored, is a model of the old
one. CaDiCaL 2.1.3 and MiniSat 2.2.0 do not have factorization.

#where[
  CaDiCaL: — · kissat: `factor.c` · MiniSat: — · ksat port: not ported
]

== Model reconstruction: the extension stack

Everything that only preserves satisfiability (BVE, BCE, CCE, conditioning) leaves the solver
with a model of the reduced formula that may violate removed clauses, or may not even assign
eliminated variables. The fix, pioneered in MiniSat, is an *extension stack* (MiniSat
`elimclauses`, CaDiCaL `extension`, kissat `extend`; also called the _witness stack_). Each
removed clause is pushed together with its _witness_: the literal(s) that repair it.

After the search finds a model of the reduced formula, the stack is walked from the top
(newest entry) to the bottom:

- if the clause is satisfied by the current values, do nothing;
- otherwise set every witness literal to true.

Going newest-first matters: a later simplification ran on a formula that already lacked the
earlier clauses, so its repairs have to be done before the earlier ones are checked.

#example(title: "Extending a model after BVE")[
  Original: $C_1 = (x or a)$, $C_2 = (overline(x) or b)$, $C_3 = (overline(x) or c)$. After
  eliminating $x$: $(a or b), (a or c)$.

  MiniSat (`eliminateVar`) saves only the smaller side: here the one positive clause
  $(x or a)$ with witness $x$, and on top a unit $(overline(x))$ that just sets the default
  $x = 0$.

  The reduced formula has the model $a = 0, b = 1, c = 1$; $x$ has no value. Walk the stack
  from the top:
  + unit $(overline(x))$: set $x = 0$;
  + $(x or a)$: both false, so set the witness $x = 1$.

  Result $x = 1, a = 0, b = 1, c = 1$: $C_1$ via $x$, $C_2$ via $b$, $C_3$ via $c$. For the
  other model $a = 1, b = 0, c = 0$, step 2 finds $(x or a)$ satisfied and $x = 0$ stays, which
  is needed because $C_2$ would fail with $x = 1$.
]

Why it is enough to save one side: if all positive clauses are satisfied by the other
variables, $x = 0$ satisfies all negative clauses (they contain $overline(x)$). If some positive
clause needs $x = 1$, its other literals are all false, and then each resolvent with a negative
clause forces that negative clause's other literals true, so the negative clauses hold with
$x = 1$ as well.

The three solvers differ in what they save:

- MiniSat stores the smaller side plus a default unit (`mkElimClause`), and `extendModel`
  walks `elimclauses` from the end.
- kissat also stores the smaller side plus one unit for the other side (the smaller side is
  picked in `kissat_generate_resolvents`, the unit is added in `weaken_clauses` in
  `eliminate.c` unless the `incremental` option is set), and `extend.c` walks `extend` from the
  end.
- CaDiCaL stores all clauses of both sides (`mark_eliminated_clauses_as_garbage` in `elim.cpp`).
  The comment there says why: the one-side trick would break its incremental `restore` logic
  (next section). The exception is elimination with a gate (section "Gates and definitions"):
  then only the gate clauses are stored, since the gate alone defines $x$ (the test
  `if (!substitute || c->gate)` there). `External::extend` in `extend.cpp` walks the stack from the end; witnesses
  may have several literals (needed for conditioning).

#where[
  CaDiCaL: `extend.cpp` (`External::extend`, `push_clause_on_extension_stack`) · kissat:
  `extend.c`, `weaken.c` · MiniSat: `SimpSolver.cc` (`mkElimClause`, `extendModel`) · ksat
  port: not needed, nothing is eliminated
]

== Frozen variables

Elimination assumes the formula is final. In incremental use (chapter 6) it is not: the user
may add clauses or _assume_ literals in the next `solve` call, and an IPASIR-UP propagator
watches its _observed_ variables and expects to see their assignments. If such a variable was
eliminated, the solver gives wrong answers.

#example(title: "A spurious model after elimination")[
  As before, $x$ is eliminated from $(x or a), (overline(x) or b), (overline(x) or c)$, leaving
  $(a or b), (a or c)$.

  Next call, the user assumes $x = 0$ and $a = 0$. With the original clauses this is
  unsatisfiable: $x = 0$ and $a = 0$ falsify $(x or a)$. But the reduced formula does not
  mention $x$ any more, so it happily reports $a = 0, b = 1, c = 1$ (with $x = 0$). And the
  reconstruction step would then flip $x$ to 1, contradicting the assumption.
]

A *frozen* variable is one that elimination (and similar techniques) must not touch. The
three solvers handle this differently:

- MiniSat: the user calls `setFrozen(v, true)` for variables used later. `solve_` also
  freezes the current assumptions temporarily before calling `eliminate()` and unfreezes them
  afterwards. `eliminateVar` asserts the variable is not frozen.
- CaDiCaL: has `freeze` / `melt` with reference counts, but its header (`cadical.hpp`) calls
  this the old way. By default it instead *restores*: if a later `add` or `assume` uses a
  literal whose negation is a witness on the extension stack, `restore.cpp` puts the removed
  clauses back (recursively) before solving. Observed variables of an IPASIR-UP propagator are
  frozen when they are added (`add_observed_var` in `external.cpp` calls `freeze`), and `cover.cpp`
  skips frozen literals.
- kissat: upstream is not incremental (a second `kissat_solve` is rejected in `internal.c`:
  "incremental solving not supported"), so it has no freeze API.

#note(title: "ksat ports")[
  None of this chapter is ported: the ksat Kotlin ports of MiniSat, CaDiCaL and kissat have no
  pre- or inprocessing, and MiniSat's `SimpSolver` layer is not ported. Every variable stays in
  the formula, so assumptions and IPASIR-UP observed variables are always safe and there is
  nothing to freeze or restore. Freezing becomes relevant the moment any elimination technique
  is ported: assumptions and observed variables must then be frozen or restored, exactly as
  upstream does.
]

#where[
  CaDiCaL: `external.cpp` (`freeze`, `melt`), `restore.cpp`, `cadical.hpp` · kissat: — ·
  MiniSat: `SimpSolver.cc` (`setFrozen`, `solve_`) · ksat port: not needed (no elimination)
]
