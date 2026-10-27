# minisat_core segfaults on a big input without any proof option (master)

On `master` (664490d), `minisat_core` crashes with SIGSEGV on this satisfiable instance.
No proof option is involved, core/Main.cc doesn't have one.

```sh
python3 -c "
print('p cnf 30000 10001')
for i in range(10000): print(-1, *[10000 + (40*i + j) % 20000 for j in range(40)], 0)
print('1 0')" > trim.cnf
./minisat_core trim.cnf
```

Expected `SATISFIABLE` (exit 10). Actual: segfault (exit 139).

The file is 10000 clauses of `-1` plus 40 positive literals, then the unit `1`, so the first
`simplify()` trims `-1` out of every clause.

**Cause:** since 6b0d7ff, in `Solver::removeSatisfied` (core/Solver.cc:729) the proof lines for a trimmed
clause are written under `if (trimmed)`, without the `drup_file` check that every other proof
write has. With `BIN_DRUP` (the default) the bytes go into the static buffer, and as soon as more
than 1 MB is pending, `binDRUP_flush` calls `fwrite_unlocked(..., NULL)`. Hence the big input. Without
`BIN_DRUP` it is `fprintf(NULL, ...)`, and the first trimmed clause already crashes (then even
`minisat` on a plain pigeonhole formula segfaults).

**Fix:** `if (drup_file && trimmed)`. crystalball got the same `drup_file` check in 742f095
(2020-07-19), it never made it to master. Happy to open a PR.

```diff
-            if (trimmed){
+            if (drup_file && trimmed){
```

*PS: on macOS master needs two small build fixes first (`fwrite_unlocked` is glibc-only, and
the non-Linux `memUsedPeak()` definitions in utils/System.cc lack the `bool` parameter). I
built with `-Dfwrite_unlocked=fwrite` and fixed the signatures locally. CMake 4 also wants
`-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.*
