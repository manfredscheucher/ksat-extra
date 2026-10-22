# cadical-full: instrumented upstream CaDiCaL 2.1.3 (shadow reference)

Reference for the full 1:1 Kotlin port of CaDiCaL (see `../../doc/cadical-full-port.md`).
Unlike `../cadical-c/cadical_trace.cc` (a hand transcription of the core), this is the
real upstream solver, unmodified, plus trace prints.

| File | What |
|---|---|
| `upstream/` | verbatim CaDiCaL 2.1.3 sources (`f13d744`), never edited, see `upstream/README.md` |
| `trace.patch` | unified diff applied to a copy of `upstream/`; only adds output (see below) |
| `driver.cpp` | small `main` on the public `Solver` API, plus a proof `Tracer` for ADD/DEL lines |
| `build_and_trace.sh` | builds `build/cadical_full_trace` and writes the golden traces |
| `build/` | build directory (gitignored via `**/build/`) |

Golden traces go to `../golden-cadical-full-<config>/<name>.trace` with a
`manifest.txt` (gitignored like every `shadow/golden*/`, regenerate with the script).

## Build and trace

    bash ksat-extra/shadow/cadical-full/build_and_trace.sh               # build + plain + default
    CHECK=1 bash ksat-extra/shadow/cadical-full/build_and_trace.sh       # + determinism / tracer check
    BIG=1 ...                                                            # also php_10_9 (~6M lines)
    CONFIGS="plain sat" ...                                              # other configs
    bash ksat-extra/shadow/cadical-full/build_and_trace.sh --build-only

The script copies `upstream/*.cpp *.hpp` to `build/src`, applies `trace.patch`
(`patch -p1`), writes `build/src/build.hpp` (the macros upstream's
`scripts/make-build-header.sh` generates: VERSION, IDENTIFIER, SHORTID, COMPILER, FLAGS,
DATE), and compiles every solver source except `cadical.cpp`, `mobical.cpp` (apps),
`ccadical.cpp`, `ipasir.cpp` (C APIs), plus `driver.cpp`:

    clang++ -O2 -std=c++11 -DNDEBUG -DNCLOSEFROM -DNCONTRIB

These are upstream's default `./configure` flags on macOS (`-std=c++11`, `-DNDEBUG`,
no `closefrom`), with `-O2` instead of `-O3` and contrib off. `VERSION` is not copied
into `build/src`: on a case-insensitive file system it would shadow the C++ header
`<version>`.

For every `../cnf/*.cnf` (php_10_9 only with `BIG=1`) and every config, the driver runs
with `LSTRACE=1`; the lines `s ...` (verdict) and `c ...` (upstream parser messages, one
contains the parse time) are dropped, everything else is the trace. With `CHECK=1` each
run is repeated and must be byte-identical, and run once more without the proof tracer
(`LSPROOF=0`); the search events must then be identical apart from clause ids (see
"Proof tracer").

## Driver

    build/cadical_full_trace [--config=plain|default|sat|unsat] [--name=value ...]
                             [--limit:<name>=<n> ...] [--proof=<path>|-]
                             <file.cnf> [<file.assume>]

Order of API calls: `Solver::configure(config)` (if given), `Solver::set_long_option`
for each `--name=value`, `connect_proof_tracer` (if enabled), `read_dimacs(path, vars,
strict=1)`, `assume` for each non-zero literal of the assumptions file,
`Solver::limit(name, n)` for each `--limit:<name>=<n>` (in the given order; names as in
upstream `Internal::limit`: terminate, conflicts, decisions, preprocessing, localsearch;
an unknown name or a malformed argument is an error, exit 1), `solve`. `--limit` exists
because some phases are only reachable through that API: `preprocess`
(`Internal::preprocess_round`) runs only with `limit("preprocessing", n > 0)`, so
`../cnf-full/OPTIONS` runs `bin_gadgets_r4.cnf` a second time with
`--limit:preprocessing=1`. The Kotlin driver (`runShadow`, `limits` parameter) does the
same. With `--proof=<path>` (`-` = stdout) the driver calls `Solver::trace_proof` right
after the options (format chosen by the upstream proof options: `--binary`, `--lrat`,
`--frat`, `--veripb`, `--idrup`, `--lidrup`, `--externallrat`) and `close_proof_trace`
right after `solve`; add `--quiet=1` when the proof goes to stdout, otherwise upstream's
`c ...` messages are mixed in. `runShadow(..., proofOut, lstrace = false)` is the Kotlin
side; `FullProofTest` compares both byte by byte. Prints
`s SATISFIABLE` / `s UNSATISFIABLE` / `s UNKNOWN` (always) and exits 10 / 20 / 0.

Configs are upstream's (`config.cpp`): `default` = option defaults; `plain` =
`Options::disable_preprocessing`, which sets every option flagged as preprocessing to 0:
`block compact cover decompose deduplicate elim instantiate probe subsume ternary
transred vivify` (`condition` is already 0 by default). `plain` does NOT turn off `lucky`, `walk`, `rephase`, `chrono`, `otfs`, reduce
or restarts, so `START lucky`, `START walk`, `REPHASE` and `OTFS` occur in plain traces
too. That is upstream behaviour.

## Proof tracer

The driver connects a `CaDiCaL::Tracer` subclass through
`Solver::connect_proof_tracer(tracer, antecedents=false, finalize_clauses=false)` (API
available in 2.1.3, must be called in state CONFIGURING) when `LSTRACE` is set and
`LSPROOF` is not `0`. With `antecedents=false` it does not force LRAT and with
`finalize_clauses=false` it does not enable FRAT.

Effect on behaviour, checked in the source and empirically: connecting it creates
`internal->proof`. All `if (proof)` branches only emit proof events, except that some of
them allocate extra clause ids: `Proof::otfs_strengthen_clause` gives an on-the-fly
strengthened clause a fresh id (`++internal->clause_id`), and assumption clauses,
decompose and cover also take ids only in proof mode. Clause ids are never compared or
used for ordering in the solver, so the search (decisions, assignments, conflicts,
learned literals, phases) is identical; only the printed clause ids differ after the
first such event. `CHECK=1` verifies exactly this on every CNF (`search_events` in the
script blanks the ids). The golden traces are produced WITH the tracer, so their ids
follow upstream's proof-mode id allocation; the Kotlin port must reproduce that (or
compare with ids blanked).

## Trace vocabulary

One event per line, stdout, only when `LSTRACE` is set. `<lits>` is always
` l1 l2 ... lk 0`-style: the external (DIMACS) literals in the solver's current stored
order, each preceded by one space, ending with ` 0`. Search events print internal
literals mapped through `Internal::externalize`. `<id>` is the upstream 64-bit clause
id (`Clause::id`), printed in decimal.

| Line | Printed in (upstream function) | Meaning |
|---|---|---|
| `DECIDE <lit>` | `Internal::search_assume_decision` (propagate.cpp) | new decision level with decision `<lit>`; also for assumptions, constraint literals and the decisions inside `lucky` |
| `DECIDE 0` | `Internal::new_trail_level` (decide.cpp), only for `lit == 0` | pseudo decision level (assumption or constraint already satisfied) |
| `ASSIGN <lit> level=<L> reason=D` | `Internal::search_assign` (propagate.cpp) | the decision just announced by `DECIDE` |
| `ASSIGN <lit> level=0 reason=U` | `search_assign` | root-level unit (assignment level 0, `Var::reason` becomes 0) |
| `ASSIGN <lit> level=<L> reason=E` | `search_assign` | external propagator reason (`external_reason`) |
| `ASSIGN <lit> level=<L> reason=C <id> :<lits>` | `search_assign` | implied by clause `<id>`; `<lits>` in stored order at the time of the assignment. `level` is the assignment level (with `chrono` it can be below the current level) |
| `CONFLICT level=<L> <id> :<lits>` | `Internal::analyze` entry (analyze.cpp) | conflict clause handed to analysis; `L` = current decision level |
| `OTFS <id> :<lits>` | `Internal::analyze`, after `on_the_fly_strengthen` | the strengthened reason that becomes the new conflict |
| `OTFS 0 : 0` | same | on-the-fly strengthening produced a unit (null clause) |
| `LEARN id=<id> glue=<g> jump=<j> :<lits>` | `Internal::new_driving_clause` (analyze.cpp) | 1st-UIP clause after minimize/shrink and sorting, `id=0` for size 0/1 (no clause object); `j` = jump level |
| `BACKTRACK <level>` | `Internal::backtrack` (backtrack.cpp), after the `new_level == level` early return | backtrack to `<level>`; every caller (search, restart, probe, vivify, lucky, walk, ...). Assignments of probe/vivify/instantiate/condition are not traced, so their `BACKTRACK 0` lines appear without a preceding `DECIDE` |
| `RESTART` | `Internal::restart` (restart.cpp) | restart; the `BACKTRACK` to the reuse-trail level follows |
| `MODE stable` / `MODE focused` | `Internal::stabilizing` (restart.cpp), after `stable = !stable` | mode switch |
| `REDUCE` / `FLUSH` | `Internal::reduce` (reduce.cpp), after `flushing ()` | reduce, or reduce in flush mode |
| `REPHASE <c>` | `Internal::rephase` (rephase.cpp), after the type is chosen | `c` is upstream's type char: `O` original, `I` inverted, `F` flipping, `#` random, `B` best, `W` walk |
| `START <phase>` / `END <phase>` | entry / exit (any return) of the function below | |
| `ADD O <id> irr\|red :<lits>` | driver tracer `add_original_clause` | original clause (`irr`/`red` = irredundant/redundant), literals as given |
| `ADD R <id> irr\|red :<lits>` | same, `restored == true` | original clause restored from the extension stack |
| `ADD D <id> irr\|red :<lits>` | driver tracer `add_derived_clause` | derived clause (learned, resolvent, strengthened copy, unit, empty clause `ADD D <id> irr : 0`) |
| `ADD A <id> :<lits>` | driver tracer `add_assumption_clause` | clause derived from failed assumptions |
| `DEL <id> irr\|red :<lits>` | driver tracer `delete_clause` | clause deleted (binary clauses are reported at actual deletion, larger ones at `mark_garbage`, as upstream does) |
| `WEAKEN <id> :<lits>` | driver tracer `weaken_minus` | clause moved to the reconstruction stack (elim, block, ...) |
| `STRENGTHEN <id>` | driver tracer `strengthen` | clause strengthened |
| `RESULT SAT\|UNSAT\|UNKNOWN` | driver, after `solve` | verdict |
| `MODEL <lit_1> ... <lit_n> 0` | driver, only after `RESULT SAT` | `val(i) > 0 ? i : -i` for `i = 1..vars()` |

Phases (`START`/`END` names) and the function they bracket. The guard sits at the very
first statement, so a phase that returns immediately (e.g. `cover` with `opts.cover=0`)
still prints `START x` / `END x`:

| Name | Upstream function |
|---|---|
| `preprocess` | `Internal::preprocess_round` (internal.cpp) |
| `probe` | `Internal::probe(bool)` (probe.cpp) |
| `vivify` | `Internal::vivify` |
| `subsume` | `Internal::subsume(bool)` |
| `elim` | `Internal::elim(bool)` |
| `block` | `Internal::block` |
| `cover` | `Internal::cover` |
| `condition` | `Internal::condition(bool)` |
| `ternary` | `Internal::ternary` |
| `decompose` | `Internal::decompose` |
| `transred` | `Internal::transred` |
| `instantiate` | `Internal::instantiate(Instantiator&)` |
| `deduplicate` | `Internal::mark_duplicated_binary_clauses_as_garbage` |
| `lucky` | `Internal::lucky_phases` |
| `walk` | `Internal::walk_round` (initial local search and rephase walk) |
| `rephase` | `Internal::rephase` |
| `compact` | `Internal::compact` |
| `collect` | `Internal::garbage_collection` |

Relation to the old core vocabulary (`../cadical-c`): `DECIDE`, `RESTART`, `REDUCE`,
`RESULT` are the same lines; `ASSIGN` and `CONFLICT` keep their prefix and add fields
(`reason=C` becomes `reason=C <id> :<lits>`); everything else is new.

## How trace.patch was made

`trace.patch` is `diff -ruN` between `upstream/` and a copy edited by the throwaway
helper `scripts/probe/make_cadical_full_trace_patch.py` (top-level repo; exact anchors,
each must occur once). It adds the new header `lstrace.hpp` (`LSTRACE(...)` printf
macro gated by `getenv("LSTRACE")`, `lstrace_lits`, and the `LSTRACE_PHASE` scope
guard), includes it from `internal.hpp`, and adds only prints plus one read-only local
(`lstrace_reason` in `search_assign`). The patch has no removed lines.
