// Driver for the instrumented upstream MiniSat reference (ksat-extra/shadow/minisat-full).
//
//   minisat_full_trace [--simp=0|1] [--<option>=<value> ...] <file.cnf> [<file.assume>]
//
// --strict=1: parse_DIMACS(in, S, true) (upstream Main.cc -strict): prints "PARSE ERROR! DIMACS
// header mismatch: wrong number of clauses" to stdout when the clause count differs from the
// header and goes on. Default 0 (as upstream). Malformed input: upstream's parser prints
// "PARSE ERROR! Unexpected char: <c>" (stdout from parse_DIMACS_main, stderr from parseInt) and
// exits with 3.
//
// --script=<file.ops>: incremental script mode instead of a CNF, see driver_script.h.
//
// --simp=0 (default): core Minisat::Solver.  --simp=1: Minisat::SimpSolver, run like
// upstream simp/Main.cc: parse, eliminate(true), stop with UNSAT if !okay(), else
// solveLimited(assumptions).
//
// Every other --<name>=<value> is handed to upstream's own option parser
// (Minisat::parseOptions, strict) in upstream syntax: -<name>=<value> for int/double
// options, -<name> / -no-<name> for the bool options (value 1 / 0). So the names are the
// upstream ones (core: var-decay cla-decay rnd-freq rnd-seed ccmin-mode phase-saving
// rnd-init luby rfirst rinc gc-frac min-learnts; simp: asymm rcheck elim grow cl-lim
// sub-lim simp-gc-frac), with upstream's range checks. Options are parsed before the
// solver is constructed (upstream reads them in the constructor).
//
// The CNF is read with upstream's parse_DIMACS (core/Dimacs.h) through the zlib shim
// (zlib-shim/zlib.h: gzFile = FILE*). The optional assumptions file holds signed DIMACS
// literals (whitespace separated, 0 ignored); missing variables are created with newVar()
// (as the old minisat-c reference does). With --simp=1 every assumption variable is frozen
// (setFrozen(v, true)) before eliminate(true): upstream solve_ only freezes assumptions when
// it runs the elimination itself, and eliminate(true) turns simplification off for good.
//
// Output (stdout): the LSTRACE events (only with LSTRACE set), then
//   RESULT UNSAT          only when --simp=1 and eliminate() made the solver inconsistent
//                         (upstream simp/Main.cc does not call solve then; with LSTRACE)
//   MODEL l1 ... ln 0     after a SAT result (with LSTRACE): model[i] == l_True ? i+1 : -(i+1)
//                         for i = 0..nVars()-1; an l_Undef model value is an error (exit 1)
//   s SATISFIABLE | s UNSATISFIABLE | s UNKNOWN   (always)
// Exit code 10 / 20 / 0 like upstream, 1 on any error (message on stderr).

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

#include "minisat/core/Dimacs.h"
#include "minisat/core/Solver.h"
#include "minisat/simp/SimpSolver.h"
#include "minisat/utils/Options.h"
#include "minisat/utils/System.h"

using namespace Minisat;

static void die(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fflush(stdout);
    fprintf(stderr, "minisat_full_trace: error: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

#include "driver_script.h"   // --script mode (incremental)

static const char* const bool_options[] = { "luby", "rnd-init", "elim", "asymm", "rcheck", NULL };

static bool is_bool_option(const std::string& name) {
    for (int i = 0; bool_options[i] != NULL; i++)
        if (name == bool_options[i]) return true;
    return false;
}

static bool strict_parse = false;   // --strict=1: parse_DIMACS(in, S, true) (upstream -strict)

template<class S>
static void read_cnf(S& solver, const char* path) {
    FILE* in = fopen(path, "rb");
    if (in == NULL) die("cannot open CNF file '%s'", path);
    parse_DIMACS(in, solver, strict_parse);
    if (ferror(in)) die("read error on '%s'", path);
    fclose(in);
}

template<class S>
static void read_assumptions(S& solver, const char* path, vec<Lit>& assumps) {
    FILE* in = fopen(path, "r");
    if (in == NULL) die("cannot open assumptions file '%s'", path);
    int lit;
    int r;
    while ((r = fscanf(in, "%d", &lit)) == 1) {
        if (lit == 0) continue;
        int v = abs(lit) - 1;
        while (v >= solver.nVars()) solver.newVar();
        assumps.push(mkLit(v, lit < 0));
    }
    if (r != EOF || ferror(in)) die("malformed assumptions file '%s'", path);
    fclose(in);
}

static int finish(const Solver& solver, lbool ret) {
    if (ret == l_True) {
        if (lstrace_on()) {
            if (solver.model.size() != solver.nVars())
                die("model has %d values for %d variables", solver.model.size(), solver.nVars());
            printf("MODEL");
            for (int i = 0; i < solver.nVars(); i++) {
                if (solver.model[i] == l_Undef) die("model value of variable %d is undefined", i + 1);
                printf(" %d", solver.model[i] == l_True ? i + 1 : -(i + 1));
            }
            printf(" 0\n");
        }
        printf("s SATISFIABLE\n");
        return 10;
    }
    if (ret == l_False) {
        printf("s UNSATISFIABLE\n");
        return 20;
    }
    printf("s UNKNOWN\n");
    return 0;
}

int main(int argc, char** argv) {
    int simp = 0;
    std::string script;   // --script=<file.ops>: incremental script mode (driver_script.h)
    std::vector<std::string> upstream_args;
    std::vector<const char*> files;
    upstream_args.push_back(argv[0]);

    for (int i = 1; i < argc; i++) {
        const char* a = argv[i];
        if (strncmp(a, "--", 2) == 0) {
            const char* eq = strchr(a, '=');
            if (eq == NULL || eq == a + 2) die("option '%s' must have the form --<name>=<value>", a);
            std::string name(a + 2, eq);
            std::string value(eq + 1);
            if (name == "script") {
                if (value.empty()) die("--script needs a file");
                script = value;
            } else if (name == "strict") {
                if (value == "0") strict_parse = false;
                else if (value == "1") strict_parse = true;
                else die("--strict must be 0 or 1, got '%s'", value.c_str());
            } else if (name == "simp") {
                if (value == "0") simp = 0;
                else if (value == "1") simp = 1;
                else die("--simp must be 0 or 1, got '%s'", value.c_str());
            } else if (is_bool_option(name)) {
                if (value == "1") upstream_args.push_back("-" + name);
                else if (value == "0") upstream_args.push_back("-no-" + name);
                else die("--%s is a bool option, value must be 0 or 1, got '%s'", name.c_str(), value.c_str());
            } else {
                // Upstream's IntOption/DoubleOption accept trailing garbage (strtol/strtod
                // without an end check); require a complete number here instead.
                char* end = NULL;
                strtod(value.c_str(), &end);
                if (value.empty() || end == NULL || *end != '\0')
                    die("option --%s needs a number, got '%s'", name.c_str(), value.c_str());
                upstream_args.push_back("-" + name + "=" + value);
            }
        } else if (a[0] == '-') {
            die("unknown argument '%s' (options are --<name>=<value>)", a);
        } else {
            files.push_back(a);
        }
    }
    if (!script.empty() && !files.empty()) die("--script takes no CNF / assumptions file");
    if (script.empty() && (files.size() < 1 || files.size() > 2))
        die("usage: %s [--simp=0|1] [--strict=0|1] [--<option>=<value> ...] <file.cnf> [<file.assume>]  |  [--simp=0|1] [--<option>=<value> ...] --script=<file.ops>", argv[0]);

    // Upstream option parser, strict: an unknown or malformed flag exits(1) with
    // "ERROR! Unknown flag ...", an out-of-range value exits(1) as well.
    std::vector<char*> uargv;
    for (size_t i = 0; i < upstream_args.size(); i++) uargv.push_back(const_cast<char*>(upstream_args[i].c_str()));
    uargv.push_back(NULL);
    int uargc = (int)upstream_args.size();
    parseOptions(uargc, &uargv[0], true);
    if (uargc != 1) die("option '%s' was not consumed by the upstream option parser", uargv[1]);

    if (!script.empty()) {
        if (simp == 0) {
            Solver S;
            return run_script(S, NULL, script.c_str());
        }
        SimpSolver S;
        return run_script(S, &S, script.c_str());
    }

    vec<Lit> assumps;
    if (simp == 0) {
        Solver S;
        read_cnf(S, files[0]);
        if (files.size() == 2) read_assumptions(S, files[1], assumps);
        lbool ret = S.solveLimited(assumps);
        return finish(S, ret);
    }

    SimpSolver S;
    read_cnf(S, files[0]);
    if (files.size() == 2) read_assumptions(S, files[1], assumps);
    for (int i = 0; i < assumps.size(); i++) S.setFrozen(var(assumps[i]), true);
    S.eliminate(true);
    if (!S.okay()) {
        LSTRACE("RESULT UNSAT\n");
        return finish(S, l_False);
    }
    lbool ret = S.solveLimited(assumps);
    return finish(S, ret);
}
