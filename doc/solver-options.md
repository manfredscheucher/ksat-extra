# Solver options in the ksat facade

## What was asked (Manfred, 2026-10-30)

"MINISAT and MINISAT_SIMP": there should be only one MiniSat (and every other solver only once).
Instead, each solver takes an additional, optional dict of options where such features can be
switched on. Cleaner. In the web interface (playground) an "Options" button lets the user pick the
options of the selected solver.

## Background (Claude)

- CaDiCaL (full 2.1.3 port): preprocessing/inprocessing on by default and still incremental
  (eliminated variables are restored by CaDiCaL itself). Options exist upstream: `set(name, value)`.
- Kissat port: CDCL core only, all inprocessing off (shadow-test design). No options.
- MiniSat: preprocessing is a separate upstream class (`SimpSolver`), not incremental after
  elimination. Upstream binary switch: `-pre` / `-no-pre`.
- MicroSat: no options.

## Decisions (Claude's recommendations, accepted by Manfred: "mach mal")

- `Ksat(solver, numVars, options: Map<String, Int> = emptyMap())`; `enumerateModels` takes the same
  `options`. Option names are the upstream names.
- `Solver.MINISAT_SIMP` is removed. MiniSat: option `pre` (0/1, the upstream binary's switch):
  `pre=1` builds MiniSat's `SimpSolver`, otherwise the core `Solver`.
- CaDiCaL: every option goes to upstream `Solver.set(name, value)` before any clause is added.
- Unknown option names, values the solver rejects, and any option for KISSAT / MICROSAT fail loudly
  (IllegalArgumentException).
- Scope (Manfred: "ksat soll ne portierung sein, insofern möcht i alles habn"): ALL upstream
  options the ports have. MiniSat: every `Option` of Solver.cc / SimpSolver.cc plus `pre` from
  simp/Main.cc; CaDiCaL: every option of options.hpp. Kissat and MicroSat ports have none (the Kissat
  port has no inprocessing, so kissat's options are not ported). The playground's Options dialog
  shows all options of the selected solver.
- Defaults (Manfred: "default natürlich übernehmen! so wies normal gesetzt is"): exactly the
  upstream defaults, so MiniSat `pre` defaults to 1 as in the minisat binary (simp/Main.cc).
- Order: facade (+ sat-chess-kotlin) first, then the playground.

## Made while building (Claude)

- Consequence of `pre=1` by default: MiniSat without options is MiniSat's `SimpSolver`, used as
  MINISAT_SIMP was (no clauses on eliminated variables after the first solve, so no incremental
  enumeration). Incremental use needs `pre=0`.
- sat-chess-kotlin: its "MiniSat (simp)" entry is dropped (one MiniSat).
- Option values are `Map<String, Number>`, not `Map<String, Int>` as in the decision above: MiniSat
  has double options (`var-decay`, `rinc`, ...), which an Int cannot carry.
- "Integral" is checked on the value, not the Kotlin type (`3`, `3L` and `3.0` are all taken for an
  int option), since Kotlin/JS cannot tell Int and Double apart at runtime. Bool options take 0 / 1.
- MiniSat ranges exactly as upstream: open / closed `DoubleRange` ends are kept (`SolverOption`
  has `minInclusive` / `maxInclusive`), `HUGE_VAL` is +infinity, and `grow` (an `IntOption` without
  `IntRange`) has upstream's default range INT32_MIN..INT32_MAX.
- MiniSat with `pre` = 0 is the core `Solver`, which has no SimpSolver options, so `asymm`,
  `rcheck`, `elim`, `grow`, `cl-lim`, `sub-lim` and `simp-gc-frac` together with `pre` = 0 throw
  (the upstream binary accepts them with `-no-pre`, where they have no effect).
- MiniSat: no other simp/Main.cc options (`verb`, `show-info`, `solve`, `dimacs`, `cpu-lim`,
  `mem-lim`, `strict`, `drup`, `drup-file`: binary / I/O settings), and no port settings that are
  not upstream `Option`s (`rnd_pol`, `learntsize_*`, `verbosity`, `csbCompat`, `binDrup`,
  `drupFile`).
- CaDiCaL: upstream `set` returns false for an unknown name and clamps an out-of-range value
  silently; the adapter (`CaDiCaL.setOption`) throws `IllegalArgumentException` for both, like
  MiniSat. The facade checks the range first as well.
- CaDiCaL option type: BOOL for range 0..1 (as upstream's usage prints `--name=bool`), else INT.
  The table has 177 options (`log` / `logsort` exist only with LOGGING upstream and are not in the
  port); `report` defaults to 0 (library default, as upstream).
- CaDiCaL adapter additions (outside the `full` package): `setOption`, `getOption`,
  `CaDiCaL.optionTable` and the class `CaDiCaLOption`.
- Introspection: `solverOptions(solver): List<SolverOption>` with `name`, `type`
  (BOOL / INT / DOUBLE), `default`, `min`, `max`, `minInclusive`, `maxInclusive`, `help`
  (upstream help text / options.hpp description). Empty for MICROSAT and KISSAT.
- `enumerateModels`: `options` is the last parameter; the options are checked eagerly (before the
  sequence is iterated), as the other argument checks.
- `Ksat.copy()` (CaDiCaL only): upstream `Solver::copy` copies the options, so the copy keeps them
  (tested).
- Facade tests: old `MINISAT` runs as `MINISAT_CORE` (`pre` = 0), old `MINISAT_SIMP` as
  `MINISAT_PRE` (no options), through a small `SolverConfig` test helper.
- Playground and sat-chess-kotlin pass no options yet, so their MiniSat is the SimpSolver
  (`pre` = 1) and enumerates non-incrementally (a fresh solver per round). For sat-chess this
  changes its MiniSat from the incremental core solver to SimpSolver.
