# TODO / known limits

## Incremental enumeration: not for MICROSAT

`enumerateModels(..., incremental = true)` keeps one warm solver and adds each blocking clause
after `solve()`. MINISAT (with `pre=0`; its default `pre=1` is the SimpSolver, see
`solver-options.md`), CADICAL and KISSAT support add-clause-after-solve (CaDiCaL/kissat
since the `incremental` work, see `incremental-ipasir.md`), so the old MINISAT-only guard is
gone. MICROSAT has no incremental path, so `incremental = true` still throws for it; the
default `incremental = false` (fresh solver per round) works for every solver.
