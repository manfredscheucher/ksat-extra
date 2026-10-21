// Shadow-reference driver for the full CaDiCaL 2.1.3 port (NOT upstream).
//
// Usage: cadical_full_trace [--config=plain|default|sat|unsat] [--name=value ...]
//                           <file.cnf> [<file.assume>]
//
// Reads the CNF through the public Solver API (read_dimacs), applies the
// configuration (Solver::configure) and options (Solver::set_long_option),
// optionally assumes the literals of the assumptions file (whitespace
// separated signed DIMACS literals, '0' ignored), solves and prints the
// verdict. With LSTRACE set, the patched solver prints its search and
// inprocessing events to stdout (see README.md), and this driver adds:
//   * ADD/DEL/WEAKEN/STRENGTHEN lines from a CaDiCaL::Tracer (unless LSPROOF=0)
//   * RESULT SAT|UNSAT|UNKNOWN and, for SAT, MODEL <lit_1> ... <lit_n> 0
// Independent of LSTRACE it always prints 's SATISFIABLE' / 's UNSATISFIABLE'
// / 's UNKNOWN' and exits with 10 / 20 / 0. Everything is deterministic.

#include "cadical.hpp"
#include "tracer.hpp"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static bool env_set (const char *name) { return getenv (name) != 0; }

// Logs every clause addition / deletion reported to proof tracers.
// Literals are external (DIMACS) literals in the order the solver passes them.
class LsTracer : public CaDiCaL::Tracer {
  static void lits (const std::vector<int> &c) {
    for (int lit : c)
      printf (" %d", lit);
    printf (" 0\n");
  }
  static const char *kind (bool redundant) { return redundant ? "red" : "irr"; }

public:
  void add_original_clause (uint64_t id, bool redundant,
                            const std::vector<int> &c,
                            bool restored) override {
    printf ("ADD %s %" PRIu64 " %s :", restored ? "R" : "O", id,
            kind (redundant));
    lits (c);
  }
  void add_derived_clause (uint64_t id, bool redundant,
                           const std::vector<int> &c,
                           const std::vector<uint64_t> &) override {
    printf ("ADD D %" PRIu64 " %s :", id, kind (redundant));
    lits (c);
  }
  void delete_clause (uint64_t id, bool redundant,
                      const std::vector<int> &c) override {
    printf ("DEL %" PRIu64 " %s :", id, kind (redundant));
    lits (c);
  }
  void weaken_minus (uint64_t id, const std::vector<int> &c) override {
    printf ("WEAKEN %" PRIu64 " :", id);
    lits (c);
  }
  void strengthen (uint64_t id) override {
    printf ("STRENGTHEN %" PRIu64 "\n", id);
  }
  void add_assumption_clause (uint64_t id, const std::vector<int> &c,
                              const std::vector<uint64_t> &) override {
    printf ("ADD A %" PRIu64 " :", id);
    lits (c);
  }
};

static void usage (const char *argv0) {
  fprintf (stderr,
           "usage: %s [--config=plain|default|sat|unsat] [--name=value ...] "
           "<file.cnf> [<file.assume>]\n",
           argv0);
}

int main (int argc, char **argv) {
  const char *config = 0;
  std::vector<const char *> options;
  std::vector<const char *> files;
  for (int i = 1; i < argc; i++) {
    const char *arg = argv[i];
    if (!strncmp (arg, "--config=", 9))
      config = arg + 9;
    else if (!strncmp (arg, "--", 2))
      options.push_back (arg);
    else
      files.push_back (arg);
  }
  if (files.empty () || files.size () > 2) {
    usage (argv[0]);
    return 1;
  }

  const bool trace = env_set ("LSTRACE");
  const char *proof_env = getenv ("LSPROOF");
  const bool proof = trace && !(proof_env && !strcmp (proof_env, "0"));

  CaDiCaL::Solver solver;
  if (config && !solver.configure (config)) {
    fprintf (stderr, "error: invalid configuration '%s'\n", config);
    return 1;
  }
  for (const char *opt : options)
    if (!solver.set_long_option (opt)) {
      fprintf (stderr, "error: invalid option '%s'\n", opt);
      return 1;
    }

  LsTracer tracer;
  if (proof)
    solver.connect_proof_tracer (&tracer, false, false);

  int vars = 0;
  const char *err = solver.read_dimacs (files[0], vars, 1);
  if (err) {
    fprintf (stderr, "error: %s: %s\n", files[0], err);
    return 1;
  }

  if (files.size () == 2) {
    FILE *af = fopen (files[1], "r");
    if (!af) {
      fprintf (stderr, "error: cannot open assumptions file %s\n", files[1]);
      return 1;
    }
    int lit;
    int got;
    while ((got = fscanf (af, "%d", &lit)) == 1)
      if (lit)
        solver.assume (lit);
    const bool bad = got != EOF;
    fclose (af);
    if (bad) {
      fprintf (stderr, "error: bad assumptions file %s\n", files[1]);
      return 1;
    }
  }

  const int res = solver.solve ();

  if (trace) {
    if (res == 10) {
      printf ("RESULT SAT\n");
      printf ("MODEL");
      const int n = solver.vars ();
      for (int idx = 1; idx <= n; idx++)
        printf (" %d", solver.val (idx) > 0 ? idx : -idx);
      printf (" 0\n");
    } else if (res == 20)
      printf ("RESULT UNSAT\n");
    else
      printf ("RESULT UNKNOWN\n");
  }
  if (proof)
    solver.disconnect_proof_tracer (&tracer);

  if (res == 10)
    printf ("s SATISFIABLE\n");
  else if (res == 20)
    printf ("s UNSATISFIABLE\n");
  else
    printf ("s UNKNOWN\n");
  fflush (stdout);
  return res;
}
