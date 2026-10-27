# master: -rcheck gives SAT on UNSAT formulas, binary proof empty after UNSAT by simplification

Two bugs on master 664490d, both still in crystalball's code. Found while porting MiniSat to
Kotlin. csb is not affected. Repro for both is pigeonhole 3 into 2, php32.cnf:

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

## 1. -rcheck answers SATISFIABLE

```sh
./minisat -verb=0 -rcheck php32.cnf model.txt    # SATISFIABLE, model -1 2 -3 4 -5 6
```

Without `-rcheck` (or on csb with it) the answer is UNSATISFIABLE.

**Cause:** 333d3ef moved `removeClause(cls[i])` behind the resolvent loop in `eliminateVar`
(simp/SimpSolver.cc:562-566) and `substitute` (604-607). Right for DRAT, but with rcheck
`addClause_` asks `implied(ps)` first (SimpSolver.cc:163). The antecedents are still there, so
every resolvent counts as implied and is dropped, then the antecedents are removed.

**Fix:** skip the rcheck for these two calls (e.g. a `bool rcheck = true` parameter on
`SimpSolver::addClause_`). Downside: implied resolvents are no longer dropped with `-rcheck`.

## 2. Binary proof is only `a 0`

```sh
./minisat -drup-file=proof.drup php32.cnf && xxd proof.drup    # 00000000: 6100
```

**Cause:** the `BIN_DRUP` buffer is flushed only above 1 MB or at the end of `solve_()` with
`l_False` (core/Solver.cc:1024). When `eliminate()` already proves UNSAT, simp/Main.cc writes
`a 0` and exits (Main.cc:180-183), the buffer is never written. `binDRUP_flush` is protected.

**Fix:** flush before the final `a 0` (needs `binDRUP_flush` public), or flush in
`SimpSolver::eliminate()` / at the early `!ok` return of `Solver::solve_()`, which also covers
library users. With the flush the proof is 93 bytes and valid.

Also, master never got two fixes crystalball has: `drup_file &&` in `removeSatisfied`
(742f095; without it `minisat_core` segfaults once more than 1 MB of trimmed clauses are
buffered) and the `-rdb-at` counter (3ae6935/6b4f821; on master `reducedb_last_confl` is only
updated with `-show-info=1`, so reduceDB runs at every decision). Should master get those too,
or is master just frozen? Happy to send a PR for whatever makes sense.
