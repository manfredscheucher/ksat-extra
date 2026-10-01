# TODO / known limits

## Partial solver ports → incremental enumeration limited to MINISAT

`enumerateModels(..., incremental = true)` (ksat facade) keeps one warm solver and adds each
blocking clause after `solve()`. Measured behaviour (IncrementalBlockingProbe, now folded into
EnumerateModelsTest): only **MINISAT** blocks correctly on the same instance. **CADICAL** and
**KISSAT** do not — adding a clause after a solve doesn't take, so they'd enumerate forever.

Cause: CaDiCaL and kissat are ported as the **CDCL search core only** (no inprocessing, and
the incremental add-after-solve machinery isn't fully ported). So `incremental = true` throws
for anything but MINISAT, and the default `incremental = false` (fresh solver per round) is the
portable path that works for all solvers (incl. MICROSAT).

**Future:** finish porting the CaDiCaL (and likely kissat) incremental path, then allow
`incremental = true` for them too and drop the `require(solver == MINISAT)` guard. Not planned
for the first stable version — the fresh-solver path covers all solvers correctly meanwhile.
