# -rdb-at reduces learnts at every decision unless -show-info=1 (master)

With `-rdb-at=k` the learnt clauses should be reduced every k conflicts. On master 664490d
that only works with `-show-info=1`. Without it, reduceDB runs before every decision once
`conflicts >= k`. Easy to see because a print option changes the search:

```sh
python3 -c "
n,h=9,8;v=lambda p,j:p*h+j+1
cl=[[v(p,j) for j in range(h)] for p in range(n)]+[[-v(p,j),-v(q,j)] for j in range(h) for p in range(n) for q in range(p+1,n)]
print('p cnf',n*h,len(cl))
for c in cl: print(*c,0)" > php9.cnf
./minisat -rdb-at=2000 -show-info=0 php9.cnf | grep ^conflicts
./minisat -rdb-at=2000 -show-info=1 php9.cnf | grep ^conflicts
```

(php9.cnf is pigeonhole 9 into 8, UNSAT.) Expected the same conflict count both times. Actual:
226823 with `-show-info=0`, 43589 with `-show-info=1`.

**Cause:** `reduceDB_needed()` tests
`conflicts - reducedb_last_confl >= reduceDB_at_confl` (core/Solver.h:640), but `reducedb_last_confl = conflicts`
(core/Solver.cc:697) sits inside `if (show_info == 1)` in `reduceDB()`. With show_info 0 it
stays 0 forever.

**Fix:** move the assignment after the `if` block. crystalball replaced it with a separate `last_conflicts`
set in `search()` (3ae6935, used by `reduceDB_needed()` since 6b4f821). On master moving the
line gives the same behaviour, since `search()` is the only caller of `reduceDB()`. Happy to
open a PR.

Roughly:

```diff
-        reducedb_last_confl = conflicts;
     }
+    reducedb_last_confl = conflicts;
     learnts.shrink(i - j);
```
