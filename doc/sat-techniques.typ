#import "lib/template.typ": ks-doc, note, warn, example, where

#show: body => ks-doc(
  title: "SAT Solver Techniques",
  subtitle: "A hands-on tutorial: what CaDiCaL, kissat and MiniSat do, with small worked examples",
  version: "Companion to the ksat ports",
  body,
)

= How to read this tutorial

This tutorial explains the techniques behind modern CDCL SAT solvers (MiniSat, CaDiCaL,
kissat), one keyword at a time, each with a tiny formula you can follow by hand. It is
deliberately separate from the port documentation (`incremental-ipasir.md`,
`shadowing-methodology`): those describe *what the Kotlin ports do and why*, this one teaches
*what the techniques are*. Every technique ends with a "where" box: in which upstream file it
lives, and whether the ksat Kotlin ports have it.

ksat has four solver ports: MicroSAT (a minimal solver, plain solve only, not covered further
here), MiniSat, CaDiCaL and kissat.

#note(title: "CaDiCaL: \"ksat port\" remarks are historical")[
  The "ksat port" remarks for CaDiCaL in the "where" boxes were written for the old CaDiCaL core
  port (CDCL core only, all inprocessing off), which was removed on 2026-10-22. The current
  CaDiCaL port is a 1:1 translation of all of CaDiCaL 2.1.3 (every technique, incremental API,
  proofs; see `cadical-full-port.md`) and behaves exactly like upstream with default options.
]

The chapters build on each other. Chapter 1 (the CDCL loop) is the foundation; chapters 2–3
make that loop fast; chapters 4–5 shrink the formula itself; chapter 6 is about using a solver
incrementally from a program; chapter 7 is a one-page map.

== Notation

- *Variables* are lowercase letters $a, b, c, dots$. A *literal* is a variable or its negation,
  written $overline(a)$ ("not $a$").
- A *clause* is a disjunction of literals, e.g. $(a or overline(b) or c)$: at least one of its
  literals must be true. Clauses are named $C_1, C_2, dots$.
- A *formula* in CNF is a set (conjunction) of clauses. It is *satisfiable* (SAT) if some
  assignment makes every clause true, otherwise *unsatisfiable* (UNSAT).
- An *assignment* is written $a = 1$ (true) or $a = 0$ (false). A literal is *falsified* when the
  assignment makes it false.
- In the solver's *trail* (the ordered list of assignments), $a@2$ means "$a$ was set true at
  decision level 2"; $overline(b)@2 arrow.l C_3$ means "$b$ was set false at level 2 because
  clause $C_3$ forced it".
- The same clauses in solver input format (DIMACS) number the variables $a = 1, b = 2, dots$ and
  write a negation as a minus sign: $(a or overline(b) or c)$ is `1 -2 3 0`.

#include "sat-techniques/01-cdcl.typ"
#include "sat-techniques/02-heuristics.typ"
#include "sat-techniques/03-clause-database.typ"
#include "sat-techniques/04-elimination.typ"
#include "sat-techniques/05-probing-equivalences.typ"
#include "sat-techniques/06-incremental.typ"
#include "sat-techniques/07-overview.typ"
