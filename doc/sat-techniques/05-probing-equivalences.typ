#import "../lib/template.typ": note, warn, example, where

= Simplifying the formula II: probing, equivalences, strengthening

Chapter 4 removed things from the formula: subsumed clauses, eliminated variables, blocked
clauses. This chapter is about the opposite direction. The solver spends a little time
*deriving* new short facts that the formula implies but does not state explicitly: units
("$a$ must be false"), binary clauses ("if $a$ then $d$"), and equivalences ("$x$ and $y$
always have the same value"). Short facts are valuable because unit propagation uses them
immediately, and an equivalence lets the solver delete a whole variable.

Almost every technique here is built from one cheap tool you already know from chapter 1:
unit propagation. The solver assigns a literal on purpose, propagates, and reads off what
happened. A few techniques also use the structure of the binary clauses (the *binary
implication graph*), and the last one, SAT sweeping, runs a tiny second SAT solver.

All of this is *inprocessing*: it runs at decision level 0, between phases of the normal CDCL
search, under an effort budget that is a fraction of the search effort. Nothing has to run to
completion; whatever was found is kept, the rest is tried next time.

#note(title: "Where these run in the two solvers")[
  CaDiCaL 2.1.3 groups them into two phases. Its `probe()` (in `probe.cpp`) runs equivalent
  literal substitution (`decompose`), then ternary resolution, then failed literal probing,
  then `decompose` again. Vivification and transitive reduction are scheduled at the end of
  `subsume()` (in `subsume.cpp`).

  kissat 4.0.4 has a single "probe" phase (`probe.c`) that calls, in this order: congruence
  closure, substitution, binary backbone, vivification, sweeping, substitution, transitive
  reduction, binary backbone, and factoring. kissat 4.0.4 has no classic failed literal
  probing and no ternary resolution; the binary backbone takes over the role of the former.
]

== The binary implication graph

Binary clauses are special. A binary clause $(x or y)$ says "if $x$ is false then $y$ is true,
and if $y$ is false then $x$ is true". So each binary clause gives two directed edges between
literals:
$ (x or y) quad arrow.r.double quad overline(x) arrow.r y quad "and" quad overline(y) arrow.r x. $

The graph over all $2n$ literals with these edges is the *binary implication graph* (BIG).
Following edges from a literal is exactly unit propagation restricted to binary clauses. The
graph is symmetric in a twisted way: whenever there is an edge $u arrow.r v$ there is also the
"contrapositive" edge $overline(v) arrow.r overline(u)$. So every path has a mirror path with all
literals negated and the direction reversed.

#example(title: "Reading the graph off three clauses")[
  $C_1 = (overline(a) or b)$, $C_2 = (overline(b) or c)$, $C_3 = (overline(c) or a)$ give the edges

  #table(
    columns: 3,
    [*clause*], [*edge*], [*mirror edge*],
    [$C_1 = (overline(a) or b)$], [$a arrow.r b$], [$overline(b) arrow.r overline(a)$],
    [$C_2 = (overline(b) or c)$], [$b arrow.r c$], [$overline(c) arrow.r overline(b)$],
    [$C_3 = (overline(c) or a)$], [$c arrow.r a$], [$overline(a) arrow.r overline(c)$],
  )

  There is a cycle $a arrow.r b arrow.r c arrow.r a$ and its mirror
  $overline(a) arrow.r overline(c) arrow.r overline(b) arrow.r overline(a)$.
]

Two words from graph theory are used in the next section. A _root_ is a literal with
outgoing edges but no incoming edge: nothing implies it through a binary clause. In the
example above there is no root, since every literal lies on a cycle. Seen from a start
literal $s$, a literal $d$ _dominates_ a literal $l$ if every path from $s$ to $l$ passes
through $d$; so $s$ itself dominates everything it reaches. When unit propagation starts from
$s$ and follows only binary clauses, each implied literal records the one literal that implied
it, and these links form a tree with $s$ at the top. In that tree the dominators of $l$ are
simply the literals on the path from $l$ up to $s$.

The BIG is the data structure behind failed literal probing, equivalent literal substitution
and transitive reduction. Solvers do not build the graph explicitly; the watch lists of
binary clauses already are its adjacency lists.

#where[
  CaDiCaL: used in `probe.cpp`, `decompose.cpp`, `transred.cpp` · kissat: used in
  `substitute.c`, `transitive.c`, `backbone.c` · MiniSat: — · ksat port: not ported
]

== Failed literal probing

*Intuition.* Pick a literal, say $a$, and pretend it is true: put it on the trail at decision
level 1 and run unit propagation. If propagation ends in a conflict, then $a = 1$ is
impossible in every model. So $overline(a)$ is a unit, and it can be added at level 0
permanently. The probe "failed", hence the name.

If the probe does not fail, nothing is learned (in the basic version) and the solver simply
backtracks to level 0 and tries the next literal.

#example(title: "A failed literal")[
  Formula:
  $C_1 = (overline(a) or b)$, $C_2 = (overline(a) or c)$, $C_3 = (overline(b) or overline(c) or d)$,
  $C_4 = (overline(b) or overline(d))$, $C_5 = (a or e or f)$.

  Probe $a$:
  - $a@1$ (the probe, a decision on level 1)
  - $b@1 arrow.l C_1$
  - $c@1 arrow.l C_2$
  - $d@1 arrow.l C_3$ (both $overline(b)$ and $overline(c)$ are false)
  - $C_4 = (overline(b) or overline(d))$ is now fully false: conflict.

  So $a = 1$ leads to a contradiction, and the solver adds the unit $overline(a)$. Back at level
  0 it propagates $overline(a)$: $C_1$, $C_2$ are satisfied, $C_5$ shrinks to $(e or f)$.
  Probing $overline(a)$ instead would not have failed; only one polarity gives a unit here.
]

*A stronger unit than the probe.* The conflict often does not depend on the probe itself but on
some literal implied by it. If the probe $a$ implies $b$ through a binary clause, and the
conflict only needs $b$, then $overline(b)$ is a unit as well, and it is stronger: it also
gives $overline(a)$ by propagation. CaDiCaL computes this "probing UIP" in
`failed_literal()` as the closest common dominator of the conflict literals in the tree of
binary implications from the previous section (function `probe_dominator()`), learns its negation as a unit, and then
also the negations of the literals on the path back up to the probe.

*Which literals to probe.* Probing every literal is expensive: one full propagation per
probe. CaDiCaL only probes _roots_ of the binary implication graph (previous section):
literals $l$ such that $overline(l)$ occurs in some binary clause but $l$ itself does not. In the example $a$ is such a root, since the binary clauses contain
only $overline(a)$. The reasoning: if $l$ has a predecessor $k$ (a binary clause gives
$k arrow.r l$), probing $k$ propagates everything that probing $l$ would, and more. CaDiCaL
also skips a probe if no new unit was found since the last time that literal was probed
(the `propfixed` counter).

=== Hyper-binary resolution

While probing $a$, every literal assigned at level 1 is implied by $a$. So for each such
literal $l$ the binary clause $(overline(a) or l)$ is implied by the formula. Adding all of them
would be far too many, but there is one useful case: when $l$ was forced by a *long* clause
(three or more literals). Then the solver adds a binary clause that, next time, gets the same
implication with a single binary propagation instead of a long-clause visit. This is
_hyper-binary resolution_ (HBR): it resolves the long reason clause with several binary
clauses in one step ("hyper").

#example(title: "Hyper-binary resolvent while probing")[
  Formula: $C_1 = (overline(a) or b)$, $C_2 = (overline(a) or c)$,
  $C_3 = (overline(b) or overline(c) or d)$, $C_4 = (a or overline(d) or e)$.

  Probe $a$: $a@1$, $b@1 arrow.l C_1$, $c@1 arrow.l C_2$, $d@1 arrow.l C_3$. No conflict.

  $d$ was forced by the ternary clause $C_3$. Its false literals are $overline(b)$ and
  $overline(c)$; both $b$ and $c$ were implied by $a$ through binary clauses, so $a$ is their
  common dominator. The hyper-binary resolvent is $(overline(a) or d)$: resolve $C_3$ with $C_1$ on
  $b$, then with $C_2$ on $c$. It is implied by the formula, and from now on $a = 1$ gives
  $d = 1$ through one binary clause.
]

CaDiCaL does this on the fly in `hyper_binary_resolve()` during probing on level 1. The new
clause consists of the newly implied literal and the negated dominator of all the false
literals in the reason clause. If the resolvent happens to subsume the reason (the negated
dominator was already in the reason clause), CaDiCaL adds the binary clause and marks the
long clause as garbage. Most hyper-binary resolvents are learned (redundant) clauses, so
the clause database can drop them again. Transitive reduction (below) exists partly to keep
their number under control.

Just before the probing rounds, CaDiCaL also removes duplicated binary clauses and does
*hyper unary resolution* in the same pass: from $(a or b)$ and $(overline(a) or b)$ it derives the
unit $b$ (`mark_duplicated_binary_clauses_as_garbage()`).

*Why it helps, and the cost.* Every unit removes a variable from the problem for good, and
the CDCL search would otherwise have to rediscover the same conflict over and over below
different decisions. The cost is one propagation per probe, which is why CaDiCaL limits the
total probing propagations to a fraction of the search propagations (options `probereleff`,
`probemineff`, `probemaxeff`) and keeps untried probes for the next call.

#where[
  CaDiCaL: `probe.cpp` (`probe_round`, `failed_literal`, `probe_dominator`, `hyper_binary_resolve`; option `probehbr`) ·
  kissat: no classic probing in 4.0.4, see "Backbone computation" (`backbone.c`) ·
  MiniSat: — · ksat port: not ported
]

== Vivification

*Intuition.* Vivification takes one existing clause and asks: "is a shorter version of this
clause already implied by the other clauses?" It tests this with unit propagation. For a
clause $C = (l_1 or l_2 or dots or l_k)$ the solver assumes the literals are false one after
the other, $overline(l_1)$, $overline(l_2)$, ..., and propagates the _other_ clauses after each
step. Three things can happen:

+ Propagation makes some later literal $l_j$ of $C$ *false*. Then $l_j$ is useless in $C$ and
  can be dropped.
+ Propagation runs into a *conflict* after assuming $overline(l_1), dots, overline(l_i)$.
  Then the prefix $(l_1 or dots or l_i)$ is implied by the other clauses, and $C$ can be
  shortened to it (in practice to the literals that conflict analysis found responsible).
+ Propagation makes some later literal $l_j$ *true*. Then $C$ is implied by the other
  clauses as a whole (an "asymmetric tautology"), and an irredundant $C$ can even be deleted.

The idea goes back to Piette, Hamadi and Sais (2008); the CaDiCaL comment calls it a special
case of asymmetric tautology and asymmetric literal elimination.

#example(title: "Vivifying a four-literal clause")[
  Clause to vivify: $C_1 = (a or b or c or d)$. Other clauses:
  $C_2 = (a or e)$, $C_3 = (overline(e) or overline(c))$, $C_4 = (b or overline(e) or f)$,
  $C_5 = (b or overline(e) or overline(f))$.

  - Assume $overline(a)$: $e arrow.l C_2$, then $overline(c) arrow.l C_3$. The literal $c$ of
    $C_1$ is now false (case 1), so $c$ could already be dropped.
  - Assume $overline(b)$: $f arrow.l C_4$, and $C_5 = (b or overline(e) or overline(f))$ is fully
    false: conflict (case 2).

  So $(a or b)$ is implied by $C_2, dots, C_5$ alone, and $C_1$ is replaced by $(a or b)$. The
  shorter clause subsumes the old one, so the set of models does not change.
]

Note the order: once the conflict appears after two literals, the rest of $C_1$ ($c$ and $d$)
is cut off, which already covers the dropping of $c$ from step 1.

*Details in the real solvers.* Both solvers vivify learned (redundant) clauses as well as
irredundant ones. kissat sorts the learned clauses into tiers by glue (chapter 3) and
vivifies each tier separately; CaDiCaL 2.1.3 runs one round over the irredundant clauses and
one over all clauses. CaDiCaL sorts the literals of all candidates by
how often they occur and sorts the candidates so that consecutive clauses share prefixes.
Then it can _reuse_ the decisions of the previous candidate instead of starting over (the
idea of "distillation" from Han and Somenzi, done without an explicit trie). It also runs
conflict analysis to find which of the assumed literals were really needed, and it can
_instantiate_ the last literal (option `vivifyinst`). Case 3 (delete the clause because it
is implied) is only allowed when propagation used irredundant clauses only; a learned
clause may be deleted later, so it cannot justify removing an original clause.

*Why it helps, and the cost.* Shorter clauses propagate earlier, and learned clauses in
particular are often much longer than they need to be. In modern solvers vivification is one
of the most effective inprocessing steps. Its cost is a propagation per tested literal, so it
is budgeted relative to search propagations (`vivifyreleff` in CaDiCaL, `vivifyeffort` in
kissat).

#where[
  CaDiCaL: `vivify.cpp` (called from `subsume.cpp`) · kissat: `vivify.c` · MiniSat: — ·
  ksat port: not ported
]

== Equivalent literal substitution

*Intuition.* If the BIG has a cycle $a arrow.r b arrow.r c arrow.r a$, then $a$, $b$ and $c$
imply each other, so they are equal in every model. Literals that can all reach each other
form a _strongly connected component_ (SCC). All literals in one SCC are equivalent. The
solver picks one _representative_ per SCC, replaces every other literal of the SCC by it in
all clauses, and the replaced variables disappear from the formula. This is _equivalent
literal substitution_ (ELS), also called equivalence reasoning or "decompose".

Two side effects come for free:
- If a literal and its own negation end up in the same SCC ($x arrow.r dots arrow.r overline(x)
  arrow.r dots arrow.r x$), the formula is unsatisfiable.
- After substitution some clauses contain both $l$ and $overline(l)$ (tautologies, deleted), some
  contain the same literal twice (shortened), and some become duplicates.

SCCs are found in linear time with Tarjan's algorithm, one depth-first search over the BIG.
By the mirror property, the SCC of $overline(a), overline(b), overline(c)$ is the mirror of the SCC
of $a, b, c$ and gets the mirrored representative.

#example(title: "Substituting an SCC")[
  $C_1 = (overline(a) or b)$, $C_2 = (overline(b) or c)$, $C_3 = (overline(c) or a)$ (the cycle from the
  example in "The binary implication graph"), plus $C_4 = (b or d or e)$, $C_5 = (overline(c) or overline(d))$,
  $C_6 = (b or overline(c) or e)$.

  SCCs: ${a, b, c}$ and its mirror ${overline(a), overline(b), overline(c)}$. Choose $a$ as the
  representative: replace $b$ by $a$ and $c$ by $a$ (and $overline(b), overline(c)$ by
  $overline(a)$).
  - $C_1, C_2, C_3$ become $(overline(a) or a)$: tautologies, deleted.
  - $C_4$ becomes $(a or d or e)$, $C_5$ becomes $(overline(a) or overline(d))$.
  - $C_6$ becomes $(a or overline(a) or e)$: tautology, deleted.

  Result: two clauses over $a, d, e$ instead of six over $a, dots, e$. Every model of the new
  formula extends to a model of the old one by setting $b = a$ and $c = a$, and every model of
  the old formula arises that way.
]

The last sentence is model reconstruction from chapter 4: the solver keeps the equivalences
$b equiv a$ and $c equiv a$ (as the two binary clauses each) on its reconstruction stack, so
the final model can assign the removed variables. CaDiCaL pushes them in `decompose.cpp`
onto the extension stack; kissat's `substitute.c` does the same through `weaken.c`.

*Why it helps, and the cost.* Each non-trivial SCC removes variables, merges clauses, and
often exposes new subsumptions. It is cheap (linear in the number of binary clauses), so
both solvers run it several times per phase: CaDiCaL before and after probing and again
after ternary resolution if that produced binary clauses; kissat twice per probe phase and
after congruence closure and sweeping, which feed it new equivalences.

#where[
  CaDiCaL: `decompose.cpp` (option `decompose`) · kissat: `substitute.c` (option `substitute`) ·
  MiniSat: — · ksat port: not ported
]

== Transitive reduction

*Intuition.* If the BIG has edges $a arrow.r b$ and $b arrow.r c$, then the direct edge
$a arrow.r c$ adds nothing: propagation reaches $c$ from $a$ anyway via $b$. The binary clause
behind such a shortcut edge is _transitive_ and can be deleted. Removing all of them is the
_transitive reduction_ of the graph.

#example(title: "A transitive binary clause")[
  $C_1 = (overline(a) or b)$, $C_2 = (overline(b) or c)$, $C_3 = (overline(a) or c)$.

  Edges $a arrow.r b$, $b arrow.r c$, $a arrow.r c$. Without $C_3$ there is still the path
  $a arrow.r b arrow.r c$. Indeed $C_3$ is the resolvent of $C_1$ and $C_2$ on $b$, so the
  formula $C_1 and C_2$ already implies it, and $C_3$ is removed.
]

*How it is computed.* For each candidate binary clause, say with edge $s arrow.r t$, the
solver searches the BIG from $s$ (a breadth-first propagation over binary clauses) while
ignoring this one clause. If it reaches $t$, the clause is transitive and is deleted. If the
search instead reaches both some literal and its negation, then $s$ is a failed literal and
$overline(s)$ becomes a unit. So transitive reduction finds some failed literals as a by-product. An irredundant
clause may only be removed using a path of irredundant clauses (a learned clause along the
path might be deleted later). CaDiCaL does not try hyper-binary resolvents as candidates,
since they come in large numbers and are usually not transitive when added.

*Why it helps, and the cost.* Fewer binary clauses mean shorter watch lists and fewer
redundant propagation steps. CaDiCaL's source says it plainly: this matters mostly because
hyper-binary resolution would otherwise produce too many binary clauses. A full reduction is
too expensive for large formulas, so it is bounded like probing and resumes next time.

#where[
  CaDiCaL: `transred.cpp` (option `transred`, called from `subsume.cpp`) · kissat:
  `transitive.c` (option `transitive`) · MiniSat: — · ksat port: not ported
]

== Ternary resolution

*Intuition.* Bounded variable elimination (chapter 4) adds resolvents only to remove a
variable. Ternary resolution adds resolvents for their own sake, but only small ones: it
resolves pairs of _ternary_ clauses (three literals) and keeps the resolvent only if it has
at most three literals and is not already present or subsumed by a binary clause. Resolvents
with four literals are dropped. A binary resolvent is the jackpot: it subsumes both ternary
clauses it came from, so they are deleted, and it adds new edges to the BIG.

The interesting use is with *gates* (chapter 4). If the formula encodes the same XOR or
if-then-else twice, with two different output variables, ternary resolution plus ELS can
discover that the outputs are equivalent.

#example(title: "Two copies of the same XOR")[
  Let $c = "XOR"(a, b)$ and $d = "XOR"(a, b)$, each with its usual four ternary clauses:
  $(a or b or overline(c))$, $(overline(a) or overline(b) or overline(c))$, $(overline(a) or b or c)$,
  $(a or overline(b) or c)$, and the same four with $d$ in place of $c$.

  Probing does not help: assuming $c$ (or $overline(c)$, $d$, $overline(d)$) propagates nothing,
  because every clause still has two open literals. Ternary resolution:
  - $(a or b or overline(c))$ and $(overline(a) or b or d)$ on $a$: $R_1 = (b or overline(c) or d)$.
  - $(overline(a) or overline(b) or overline(c))$ and $(a or overline(b) or d)$ on $a$:
    $R_2 = (overline(b) or overline(c) or d)$.
  - $R_1$ and $R_2$ on $b$: $(overline(c) or d)$, a binary clause.

  Symmetrically one gets $(c or overline(d))$. Now the BIG has $c arrow.r d$ and $d arrow.r c$,
  and equivalent literal substitution merges $d$ into $c$.
]

The CaDiCaL source describes this as simulating "structural hashing" of multiplexer (ITE) and
binary XOR gates when combined with `decompose`. That is why `probe()` calls `decompose()`
again whenever `ternary()` produced a binary clause. The resolvents themselves become clauses
of the formula, so later resolution steps (in the same round or the next of
`ternaryrounds`) can use them, as $R_1$ and $R_2$ were used above.

*Why it helps, and the cost.* It finds binary clauses and equivalences that unit propagation
cannot see, at bounded cost: CaDiCaL counts steps like propagations, limits the number of
added clauses (`ternarymaxadd`), and skips literals with too many occurrences
(`ternaryocclim`). kissat 4.0.4 does not have ternary resolution; congruence closure (below)
finds gate equivalences like the XOR one directly.

#where[
  CaDiCaL: `ternary.cpp` (option `ternary`) · kissat: — (not in 4.0.4) · MiniSat: — ·
  ksat port: not ported
]

== Backbone computation

*Intuition.* The _backbone_ of a satisfiable formula is the set of literals that are true in
every model. A backbone literal can be added as a unit without losing any model. The exact
test is simple but expensive: $l$ is a backbone literal if and only if the formula plus the
unit $overline(l)$ is unsatisfiable, which is a full SAT call per literal.

Failed literal probing is a cheap under-approximation: if probing $overline(l)$ fails, then $l$
is in the backbone. kissat makes this systematic for the binary clauses: `backbone.c`
computes backbone literals of the *binary part* of the formula. For each candidate literal it
assigns it as a decision and propagates over binary clauses only. A conflict means the
candidate failed; kissat analyzes the conflict to find the UIP (the same dominator idea as in
CaDiCaL's probing) and adds its negation as a unit. Since the binary clauses are part of the
formula, every literal true in all models of the binary part is also true in all models of
the full formula.

#example(title: "Backbone of a small formula")[
  $C_1 = (overline(a) or b)$, $C_2 = (overline(a) or c)$, $C_3 = (overline(b) or overline(c))$,
  $C_4 = (a or d)$, $C_5 = (overline(d) or e or f)$, $C_6 = (overline(e) or overline(f))$.

  Candidate $a$, propagating binary clauses only: $a@1$, $b@1 arrow.l C_1$, $c@1 arrow.l C_2$,
  and $C_3$ is false: conflict. The UIP is $a$ itself, so $overline(a)$ is a unit. Propagating it
  at level 0 gives $d arrow.l C_4$.

  The backbone of this formula is exactly ${overline(a), d}$: in every model $a = 0$ and
  $d = 1$, while each of $b, c, e, f$ takes both values in some models. Here the binary
  clauses alone already have the same backbone.
]

kissat's other source of backbone literals is SAT sweeping (last section): there the small
sub-solver kitten tests backbone candidates exactly, but only on a local part of the formula.

*Why it helps, and the cost.* Units are the best simplification there is. Restricting the
search to binary clauses makes each probe very cheap, and kissat's version is bounded by
"ticks" (`backboneeffort`) and a round limit. CaDiCaL 2.1.3 has no separate backbone
procedure; its failed literal probing covers similar ground.

#where[
  CaDiCaL: — (failed literal probing in `probe.cpp` is the closest) · kissat: `backbone.c`
  (option `backbone`, "binary clause backbone") · MiniSat: — · ksat port: not ported
]

== Congruence closure

*Intuition.* Many CNF formulas are translated from circuits, so they contain _gates_: groups
of clauses that define one output variable as AND, XOR or if-then-else of some inputs
(chapter 4 shows how gates are detected for variable elimination). If two gates have the same
type and the same inputs, their outputs must be equal. In a circuit tool this is called
structural hashing; in logic it is _congruence_: equal arguments give equal function values.

The "closure" part is what makes it strong. Once two outputs are merged, gates that use them
as inputs may suddenly have identical inputs too, so their outputs can be merged as well, and
so on until nothing changes.

#example(title: "Merging gates, then merging again")[
  Four AND gates, each with its three clauses (for $g = "AND"(a, b)$:
  $(overline(g) or a)$, $(overline(g) or b)$, $(g or overline(a) or overline(b))$):
  $ g = "AND"(a, b), quad h = "AND"(a, b), quad p = "AND"(g, c), quad q = "AND"(h, c). $

  - $g$ and $h$ are the same gate on the same inputs: merge, $h equiv g$.
  - Rewrite $q$ with the merged input: $q = "AND"(g, c)$, which is now the same gate as $p$:
    merge, $q equiv p$.

  Two variables disappear. In every model of the twelve clauses $g = h$ and $p = q$.
]

For AND gates, failed literal probing with hyper-binary resolution could eventually find
$g arrow.r h$ as well. For XOR gates it cannot: with $g = "XOR"(a, b)$ and $h = "XOR"(a, b)$, assuming
$g$, $overline(g)$, $h$ or $overline(h)$ propagates nothing (the same situation as in the ternary
resolution example). Congruence closure sees the equal gates directly, by hashing.

kissat's `congruence.c` extracts AND gates (`congruenceands`), XOR gates up to a small arity
(`congruencexors`, `congruencexorarity`) and if-then-else gates (`congruenceites`), stores
them in a hash table keyed by gate type and inputs, merges outputs on a hash hit, rewrites the
gates that use a merged literal, and repeats. It also finds units implied by gates, and at the
end performs forward subsumption on the rewritten clauses. The found equivalences are handed
to `substitute.c` for the actual replacement in the formula.

*Why it helps, and the cost.* Formulas from hardware verification (for example miters that
compare two versions of a circuit) are full of such duplicate structure, and congruence
closure can collapse large parts of them before search starts; kissat runs it in its initial
probing as well (`preprocesscongruence`). The cost is gate extraction, a pass over the
clauses with hashing. When it keeps finding almost nothing, kissat increases a delay so it
runs less often.

#where[
  CaDiCaL: — (not in 2.1.3) · kissat: `congruence.c` (option `congruence`) · MiniSat: — ·
  ksat port: not ported
]

== SAT sweeping with the kitten sub-solver

*Intuition.* All techniques so far use propagation or syntax. Some equivalences need real
search: you have to try cases to see that $x$ and $y$ are always equal. SAT sweeping does
exactly that, but only on a _small piece_ of the formula, so each search is tiny. The idea
comes from circuit verification, where "sweeping" means finding and merging equivalent
nodes. kissat's version works like this, one variable at a time:

+ *Environment.* Start at a variable $v$ and collect the clauses around it: first all clauses
  containing $v$ (depth 1), then all clauses of the variables in those clauses (depth 2),
  and so on, up to a depth (`sweepdepth`, default 2) and a size limit (`sweepvars`,
  `sweepclauses`).
+ *Solve.* Load the environment into _kitten_, a small, simple CDCL solver embedded in
  kissat (`kitten.c`), and solve it. Since the environment is a subset of the formula, it is
  satisfiable if the formula is.
+ *Candidates from models.* From the model, every literal that is true is a backbone candidate,
  and all of them start in one equivalence class (all have the same value, true). Each further
  model splits the classes: literals with different values in some model cannot be
  equivalent. kitten gets further models from `kitten_flip_literal` (flip one variable if the
  model stays satisfying) and from the solve calls in the next step.
+ *Prove.* For a backbone candidate $l$, solve with the assumption $overline(l)$: if UNSAT, $l$
  is a unit. For an equivalence candidate pair $x, y$, solve with assumptions $x, overline(y)$
  and then $overline(x), y$: if both are UNSAT, the binary clauses $(overline(x) or y)$ and
  $(x or overline(y))$ are implied. If a call is SAT instead, its model refines the classes
  further.

Because the environment is part of the formula, anything proven on it holds for the whole
formula. The binary clauses go into the main solver, and `substitute.c` then removes the
merged variable.

#example(title: "Two different circuits for the same function")[
  The formula computes $"XOR"(a, b)$ twice, in two different ways:
  - $x = "XOR"(a, b)$, as one XOR gate (four ternary clauses);
  - $u = "AND"(a, overline(b))$, $v = "AND"(overline(a), b)$, $y = "OR"(u, v)$, as three
    gates with three clauses each.

  That is 13 clauses. Congruence closure cannot merge $x$ and $y$: they are outputs of gates
  of different types with different inputs. Probing does not help either: assuming $x$,
  $overline(x)$, $y$ or $overline(y)$ never assigns the other one of $x, y$ and never fails.

  Sweeping around $a$ with depth 2: depth 1 adds the clauses containing $a$ (the four XOR
  clauses and two clauses each of $u$ and $v$), which brings in $b, x, u, v$; depth 2 adds
  their remaining clauses, which brings in $y$. The environment is all 13 clauses. Suppose
  kitten produces these models:

  #table(
    columns: 6,
    [$a$], [$b$], [$x$], [$u$], [$v$], [$y$],
    [1], [0], [1], [1], [0], [1],
    [0], [0], [0], [0], [0], [0],
    [0], [1], [1], [0], [1], [1],
    [1], [1], [0], [0], [0], [0],
  )

  After the first model the candidate class is ${a, overline(b), x, u, overline(v), y}$ (the true
  literals). The second model splits it into ${overline(b), overline(v)}$ and ${a, x, u, y}$.
  The third splits ${a, x, u, y}$ into ${x, y}$ and ${a, u}$; it leaves
  ${overline(b), overline(v)}$ together, since both are false in it. The fourth ($a = 1$,
  $b = 1$) separates $a$ from $u$ and $overline(b)$ from $overline(v)$. Only ${x, y}$ is left,
  and no literal was true in all four models, so there is no backbone candidate either.

  kitten then solves the environment with assumptions $x, overline(y)$: UNSAT. And with
  $overline(x), y$: UNSAT. So $x equiv y$, the clauses $(overline(x) or y)$ and $(x or overline(y))$ are
  added, and $y$ is substituted by $x$.
]

*Why it helps, and the cost.* Sweeping finds equivalences and units that need case splits,
which no propagation-based method finds, and it does so with search on problems of a few
hundred variables instead of the whole formula. The cost is many small SAT calls, bounded
by kitten "ticks" (`sweepeffort`) and by the environment limits. kissat runs it in every probe
phase and, by default, during initial preprocessing (`preprocessweep`). kitten is reused
elsewhere in kissat too: `definition.c` uses it to find gate definitions for variable
elimination from an unsatisfiable core.

#where[
  CaDiCaL: — (not in 2.1.3) · kissat: `sweep.c`, `kitten.c` (option `sweep`) · MiniSat: — ·
  ksat port: not ported
]

== Summary of this chapter

#table(
  columns: 4,
  [*technique*], [*derives*], [*CaDiCaL 2.1.3*], [*kissat 4.0.4*],
  [failed literal probing], [units], [`probe.cpp`], [— (see backbone)],
  [hyper-binary resolution], [binary clauses], [`probe.cpp`], [—],
  [vivification], [shorter / deleted clauses], [`vivify.cpp`], [`vivify.c`],
  [equivalent literal substitution], [equivalences (from BIG cycles)], [`decompose.cpp`], [`substitute.c`],
  [transitive reduction], [deleted binary clauses, some units], [`transred.cpp`], [`transitive.c`],
  [ternary resolution], [binary and ternary clauses], [`ternary.cpp`], [—],
  [backbone], [units], [—], [`backbone.c` (binary clauses)],
  [congruence closure], [equivalences (from gates)], [—], [`congruence.c`],
  [SAT sweeping], [equivalences and units], [—], [`sweep.c`, `kitten.c`],
)

MiniSat has none of these techniques, and none of them is ported in the ksat Kotlin ports.
