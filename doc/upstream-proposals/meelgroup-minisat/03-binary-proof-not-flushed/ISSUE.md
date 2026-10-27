# Binary DRUP proof only contains the empty clause when simplification proves UNSAT (master)

With the default binary proof format, `minisat` on master 664490d writes a proof that is
just `a 0` when `eliminate()` already finds the formula UNSAT. Everything before it is lost.

php32.cnf (pigeonhole 3 into 2):

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
./minisat -drup-file=proof.drup php32.cnf
xxd proof.drup
# 00000000: 6100    a.
```

Expected: a valid proof. Actual: 2 bytes, and the empty clause alone is not RUP for this
formula, so no checker can accept it. With the fix below the file has 93 bytes (24 steps) and
passes a small RUP checker. The ASCII build (with `#define BIN_DRUP` in core/Solver.h:24
removed) writes the full proof already.

**Cause:** with `BIN_DRUP` the proof goes into the static `drup_buf`. That buffer is written
only when more than 1 MB is pending (core/Solver.h:378) or at the end of `solve_()` when the
result is `l_False` (core/Solver.cc:1024). When `eliminate()` makes the solver inconsistent,
simp/Main.cc never calls solve. It writes `a 0` straight to the file (simp/Main.cc:180-183) and exits,
and the buffer is never flushed. Main can't flush it either, `binDRUP_flush` is protected.

**Fix:** make `binDRUP_flush` public and call it in simp/Main.cc before writing the final
`a 0`. Happy to open a PR. This only fixes the `minisat` binary: library users calling `solve()`
lose the buffer the same way (`SimpSolver::solve_` skips `Solver::solve_` when `eliminate()`
fails, and `Solver::solve_` returns early on `!ok` before its flush). Flushing in those two
places instead would cover both and keep `binDRUP_flush` protected, if you prefer that.

crystalball's simp/Main.cc has the same path without a flush (Main.cc:236-243), not run there.
