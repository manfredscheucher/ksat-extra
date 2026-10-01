# doc/ — sat-solvers-kotlin

**What "shadowing" means here:** to check a Kotlin port really behaves like its C original (not
just that it answers SAT/UNSAT), an instrumented build of BOTH prints a trace — every decision,
propagation and conflict, step by step — and the two traces are diffed. The saved reference
trace from the C solver is the **golden trace**; the port passes when its trace matches the
golden one line for line.

The docs are written in Typst (`*.typ`, compiled to `*.pdf`).

- **shadowing-methodology** — how each port is checked against its C original: the
  step-by-step trace comparison, the per-solver comparison level, the lessons
  learned while porting, and the current status per solver.
- **shadow-test-setup** — the mechanics of the shadow harness (the instrumented C
  reference, the shared trace format, how traces are generated and diffed).
- **benchmarks** — measured runtime comparison C vs Kotlin/JVM vs Kotlin/Native on
  pigeonhole instances, and why Kotlin/Native is slower than the JVM here.
