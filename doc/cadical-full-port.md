# Full CaDiCaL port (all of CaDiCaL 2.1.3)

## What was asked

Manfred, 2026-10-21: "mach weiter, alles portieren für cadical". Port all of CaDiCaL, not only the
CDCL core + incremental API. The rule from the start of the project still holds: translate the
upstream code 1:1, line by line; never invent. Follow upstream behaviour, including its no-ops;
deviate only for an upstream bug that can be isolated and reproduced.

## Key decision: the reference becomes real upstream

The existing shadow reference `shadow/cadical-c/cadical_trace.cc` is a simplified
re-implementation of the core, and it deviates from upstream 2.1.3 in places (reduce schedule and
`keep` flag, two restart margins, no root-level `mark_satisfied` during search; found while
writing the SAT techniques tutorial). A full port cannot be checked against it.

New reference: `shadow/cadical-full/` holds a verbatim copy of upstream CaDiCaL 2.1.3
(`f13d744`) plus a separate patch that only adds trace output at the shared events. The copy
stays verbatim; the build script applies the patch to a build directory. The Kotlin port must
match this reference with upstream default options, step by step.

## Plan

1. Foundation: instrumented upstream reference + build/trace scripts; Kotlin skeleton that mirrors
   the headers (`Internal`, `External`, `Var`, `Flags`, `Clause`, watches, occurrence lists, all
   options with upstream defaults, stats, limits, averages, queue, heap, random).
2. Parallel translation: each upstream `.cpp` becomes a `.kt` of extension functions on `Internal`
   (C++ member functions spread over files map to Kotlin extension functions spread over files).
3. Integration: compile, then match traces against the reference. Upstream has an option per
   technique, so first all inprocessing off (core must match), then enable one technique at a
   time until the default configuration matches.
4. Switch over: the facade's `Solver.CADICAL` uses the full port once it passes every existing test
   (facade tests incl. IPASIR-UP / failed / phase / listener) and the new shadow suite.

The new code lives next to the old port in package `org.bytefred.ksat.cadical.full` until the
switch. Branch: `incremental`.

## Scope

In: everything the solver does (all of `src/*.cpp` that implements solving, inprocessing,
incremental API, IPASIR-UP, model reconstruction, options, statistics as counters).
Proof tracers (DRAT/LRAT/FRAT/VeriPB/IDRUP, checkers) come in a later wave, writing to a sink.
Out (not a solver): `mobical.cpp` (fuzzer), `cadical.cpp` (CLI app), `ccadical.cpp`/`ipasir.cpp`
(C API), terminal/signal/resources/file I/O and message formatting (mapped to no-ops or Kotlin
equivalents where the solver logic needs them).

## Reference build (step 1, done 2026-10-21)

`shadow/cadical-full/` (details and the exact trace vocabulary in its `README.md`):
`upstream/` verbatim 2.1.3 sources, `trace.patch` (adds `lstrace.hpp` and prints only,
no removed lines), `driver.cpp` (Solver API + a proof `Tracer` for ADD/DEL/WEAKEN lines),
`build_and_trace.sh` (golden traces for `plain` and `default` into
`shadow/golden-cadical-full-<config>/`).

Decisions taken while building it:
- Search events print external literals (`Internal::externalize`), clause reasons as
  `<id> :<lits>` in stored order, so the port must match clause ids and literal order.
- `START x`/`END x` bracket the whole upstream function (first statement to any return),
  so phases that return at once (e.g. `cover` with `cover=0`) still appear.
- Assignments inside probe/vivify/instantiate/condition are not traced (only their
  `BACKTRACK` lines and their clause effects via the tracer).
- The proof tracer does not change the search, but proof mode allocates extra clause ids
  (e.g. OTFS strengthening). Goldens are made with the tracer on; `LSPROOF=0` traces
  differ only in ids. `CHECK=1` verifies determinism and this neutrality.
- `plain` is upstream's config: it disables only the preprocessing-flagged options;
  lucky, walk, rephase, chrono, otfs stay on.
- With the current shadow CNFs, `default` only differs from `plain` on php_8_7, php_9_8
  (and php_10_9): the small instances finish before any inprocessing is scheduled.
