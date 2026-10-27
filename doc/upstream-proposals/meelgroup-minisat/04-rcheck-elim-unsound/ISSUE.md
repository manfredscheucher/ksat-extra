# -rcheck makes minisat answer SATISFIABLE on UNSAT formulas (master)

On master 664490d, `minisat -rcheck` says SAT for php32.cnf (pigeonhole 3 into 2):

```
p cnf 6 9
1 2 0
3 4 0
5 6 0
-1 -3 0
-1 -5 0
-3 -5 0
-2 -4 0
-2 -6 0
-4 -6 0
```

```sh
./minisat -verb=0 -rcheck php32.cnf model.txt
# SATISFIABLE
cat model.txt
# SAT
# -1 2 -3 4 -5 6 0
```

The model breaks `-2 -4` (and two more). Expected UNSATISFIABLE, which is what master says without `-rcheck`,
and what csb says with it.

**Cause:** 333d3ef ("Fixing DRAT") moved `removeClause(cls[i])` behind the loop that adds the
resolvents in `SimpSolver::eliminateVar` (simp/SimpSolver.cc:562-566), and did the same in
`substitute` (simp/SimpSolver.cc:604-607, API only, same problem). That order is right for DRAT. But with rcheck on,
`SimpSolver::addClause_` first asks `implied(ps)` (simp/SimpSolver.cc:163), and since the
antecedents are still in the database every resolvent is implied and gets dropped. Then the
antecedents are removed, and the eliminated variable's clauses are lost.

**Fix:** don't run the rcheck for the resolvents and the substituted clauses. The attached patch
adds a `bool rcheck = true` parameter to `SimpSolver::addClause_` and passes `false` at those
two call sites, so the DRAT order stays. Downside: `-rcheck` then no longer drops implied
resolvents. Keeping that would need the old remove-first order with the proof deletions written
after the resolvents, which is a bigger change. Happy to open a PR either way. crystalball has the same code (SimpSolver.cc:163, 574,
617), the patch needs a small rebase there.
