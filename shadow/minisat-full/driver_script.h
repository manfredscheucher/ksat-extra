// Incremental script mode of the MiniSat shadow drivers, shared by minisat-full/driver.cpp (csb)
// and minisat-master/driver.cpp (master). Kotlin mirror: MiniSatShadowDriver.runScript (main repo,
// solver/minisat/src/jvmTest). Included after the driver's die().
//
//   <driver> [--simp=0|1] [--<option>=<value> ...] --script=<file.ops>
//
// Runs the operations of <file.ops> in order on ONE solver (Solver, or SimpSolver with --simp=1;
// for SimpSolver every call goes to the SimpSolver member, as a user holding a SimpSolver gets).
// One operation per line; empty lines and lines starting with '#' are skipped; tokens are separated
// by blanks. Literals are signed DIMACS numbers or [-]@k = the variable returned by the k-th
// `newvar` (1-based). In `add` / `assume` a missing numeric variable is created with newVar() like
// upstream's readClause (`while (var >= S.nVars()) S.newVar()`; this takes free_vars first);
// everywhere else a variable must exist.
//
//   add <lits> 0               addClause(lits)                        -> RET 0|1
//   assume <lits> 0            the assumptions for the following solves (replaces; `assume 0` clears)
//   solve [simp=0|1] [turnoff=0|1]
//                              solveLimited(assumptions) (SimpSolver: solveLimited(assumptions,
//                              do_simp, turn_off_simp), upstream defaults 1 0; core: no flags)
//                              -> RET SAT|UNSAT|UNKNOWN, then MODEL ... 0 (SAT) or FAILED ... 0 (UNSAT)
//   release <lit>              releaseVar(lit)
//   simplify                   simplify()                             -> RET 0|1
//   newvar [pol=t|f|u] [dvar=0|1]
//                              newVar(upol, dvar) (defaults u 1)      -> VAR <dimacs>
//   polarity <var> t|f|u       setPolarity(v, lbool)
//   decision <var> 0|1         setDecisionVar(v, b)
//   budget conf=<n> | budget prop=<n> | budget off
//                              setConfBudget(n) | setPropBudget(n) | budgetOff()
//   interrupt | clear-interrupt
//                              interrupt() | clearInterrupt()
//   freeze <var> 0|1           setFrozen(v, b)              (--simp=1 only)
//   eliminate [turnoff=0|1]    eliminate(turn_off_elim)     (--simp=1 only; default 0) -> RET 0|1
//
// Output (stdout, interleaved with the LSTRACE events): `OP <op tokens joined by one blank>`
// before every operation, then its result lines:
//   MODEL l1 ... ln 0   model[i] == l_True ? i+1 : l_False ? -(i+1) : ?(i+1), i = 0..nVars()-1
//   FAILED l1 ... lk 0  conflict[0..size-1] in its order (signed DIMACS)
// Exit code 0; 1 (message on stderr) on any script error.

#include <stdint.h>

#include <string>
#include <vector>

static std::vector<std::string> script_tokens(const std::string& line) {
    std::vector<std::string> t;
    size_t i = 0;
    while (i < line.size()) {
        while (i < line.size() && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r')) i++;
        size_t j = i;
        while (j < line.size() && line[j] != ' ' && line[j] != '\t' && line[j] != '\r') j++;
        if (j > i) t.push_back(line.substr(i, j - i));
        i = j;
    }
    return t;
}

struct ScriptCtx {
    Solver* S;
    SimpSolver* SS;           // NULL for --simp=0
    std::vector<Var> newvars; // results of `newvar`, for @k
    vec<Lit> assumps;
    int lineno;
    std::string line;
};

static void sfail(const ScriptCtx& c, const char* what) {
    die("script line %d '%s': %s", c.lineno, c.line.c_str(), what);
}

// Decimal integer: optional '-', at least one digit, nothing else, within int64 range.
static bool script_num(const std::string& s, int64_t& out) {
    size_t i = 0;
    bool neg = false;
    if (i < s.size() && s[i] == '-') { neg = true; i++; }
    if (i >= s.size()) return false;
    int64_t v = 0;
    for (; i < s.size(); i++) {
        if (s[i] < '0' || s[i] > '9') return false;
        if (v > (INT64_MAX - (s[i] - '0')) / 10) return false;
        v = v * 10 + (s[i] - '0');
    }
    out = neg ? -v : v;
    return true;
}

static Var script_newvar(ScriptCtx& c, lbool upol, bool dvar) {
    return c.SS ? c.SS->newVar(upol, dvar) : c.S->newVar(upol, dvar);
}

// [-]<n> or [-]@k. create: numeric variables are created like readClause.
static Lit script_lit(ScriptCtx& c, const std::string& tok, bool create) {
    bool neg = tok.size() > 0 && tok[0] == '-';
    std::string body = neg ? tok.substr(1) : tok;
    Var v;
    int64_t n;
    if (body.size() > 1 && body[0] == '@') {
        if (!script_num(body.substr(1), n) || n < 1 || n > (int64_t)c.newvars.size())
            sfail(c, "bad @k reference");
        v = c.newvars[(size_t)(n - 1)];
    } else {
        if (!script_num(body, n) || n < 1 || n > INT32_MAX / 2) sfail(c, "bad literal");
        v = (Var)(n - 1);
        if (create)
            while (v >= c.S->nVars()) script_newvar(c, l_Undef, true);
        else if (v >= c.S->nVars())
            sfail(c, "variable does not exist");
    }
    return mkLit(v, neg);
}

static Var script_var(ScriptCtx& c, const std::string& tok) {
    if (tok.size() > 0 && tok[0] == '-') sfail(c, "a variable must be positive");
    return var(script_lit(c, tok, false));
}

// <lits> 0 at tokens[1..]; the 0 must be the last token.
static void script_lits(ScriptCtx& c, const std::vector<std::string>& t, vec<Lit>& out) {
    out.clear();
    if (t.size() < 2 || t.back() != "0") sfail(c, "literal list must end with 0");
    for (size_t i = 1; i + 1 < t.size(); i++) out.push(script_lit(c, t[i], true));
}

static int script_dimacs(Lit p) { return sign(p) ? -(var(p) + 1) : var(p) + 1; }

// key=value flag with value 0|1 (or t|f|u for pol), at most once each.
static bool script_flag01(ScriptCtx& c, const std::string& tok, const char* key, int& out) {
    std::string k = std::string(key) + "=";
    if (tok.compare(0, k.size(), k) != 0) return false;
    std::string v = tok.substr(k.size());
    if (v == "0") out = 0;
    else if (v == "1") out = 1;
    else sfail(c, "flag value must be 0 or 1");
    return true;
}

static lbool script_lbool(ScriptCtx& c, const std::string& v) {
    if (v == "t") return l_True;
    if (v == "f") return l_False;
    if (v == "u") return l_Undef;
    sfail(c, "polarity must be t, f or u");
    return l_Undef;
}

static void script_result(ScriptCtx& c, lbool ret) {
    const Solver& S = *c.S;
    printf("RET %s\n", ret == l_True ? "SAT" : ret == l_False ? "UNSAT" : "UNKNOWN");
    if (ret == l_True) {
        if (S.model.size() != S.nVars())
            die("model has %d values for %d variables", S.model.size(), S.nVars());
        printf("MODEL");
        for (int i = 0; i < S.nVars(); i++) {
            if (S.model[i] == l_True) printf(" %d", i + 1);
            else if (S.model[i] == l_False) printf(" %d", -(i + 1));
            else printf(" ?%d", i + 1);
        }
        printf(" 0\n");
    } else if (ret == l_False) {
        printf("FAILED");
        for (int i = 0; i < S.conflict.size(); i++) printf(" %d", script_dimacs(S.conflict[i]));
        printf(" 0\n");
    }
}

static void script_op(ScriptCtx& c, const std::vector<std::string>& t) {
    Solver& S = *c.S;
    const std::string& op = t[0];
    printf("OP");
    for (size_t i = 0; i < t.size(); i++) printf(" %s", t[i].c_str());
    printf("\n");
    if (op == "add") {
        vec<Lit> lits;
        script_lits(c, t, lits);
        bool r = c.SS ? c.SS->addClause(lits) : S.addClause(lits);
        printf("RET %d\n", r ? 1 : 0);
    } else if (op == "assume") {
        script_lits(c, t, c.assumps);
    } else if (op == "solve") {
        int do_simp = 1, turn_off = 0;
        for (size_t i = 1; i < t.size(); i++) {
            if (c.SS == NULL) sfail(c, "solve takes no flags without --simp=1");
            if (!script_flag01(c, t[i], "simp", do_simp) && !script_flag01(c, t[i], "turnoff", turn_off))
                sfail(c, "unknown solve flag");
        }
        lbool ret = c.SS ? c.SS->solveLimited(c.assumps, do_simp == 1, turn_off == 1) : S.solveLimited(c.assumps);
        script_result(c, ret);
    } else if (op == "release") {
        if (t.size() != 2) sfail(c, "usage: release <lit>");
        Lit p = script_lit(c, t[1], false);
        if (c.SS) c.SS->releaseVar(p); else S.releaseVar(p);
    } else if (op == "simplify") {
        if (t.size() != 1) sfail(c, "usage: simplify");
        printf("RET %d\n", S.simplify() ? 1 : 0);
    } else if (op == "newvar") {
        lbool pol = l_Undef;
        int dvar = 1;
        for (size_t i = 1; i < t.size(); i++) {
            if (t[i].compare(0, 4, "pol=") == 0) pol = script_lbool(c, t[i].substr(4));
            else if (!script_flag01(c, t[i], "dvar", dvar)) sfail(c, "unknown newvar flag");
        }
        Var v = script_newvar(c, pol, dvar == 1);
        c.newvars.push_back(v);
        printf("VAR %d\n", v + 1);
    } else if (op == "polarity") {
        if (t.size() != 3) sfail(c, "usage: polarity <var> t|f|u");
        S.setPolarity(script_var(c, t[1]), script_lbool(c, t[2]));
    } else if (op == "decision") {
        if (t.size() != 3 || (t[2] != "0" && t[2] != "1")) sfail(c, "usage: decision <var> 0|1");
        S.setDecisionVar(script_var(c, t[1]), t[2] == "1");
    } else if (op == "budget") {
        int64_t n;
        if (t.size() == 2 && t[1] == "off") S.budgetOff();
        else if (t.size() == 2 && t[1].compare(0, 5, "conf=") == 0 && script_num(t[1].substr(5), n)) S.setConfBudget(n);
        else if (t.size() == 2 && t[1].compare(0, 5, "prop=") == 0 && script_num(t[1].substr(5), n)) S.setPropBudget(n);
        else sfail(c, "usage: budget conf=<n> | prop=<n> | off");
    } else if (op == "interrupt") {
        if (t.size() != 1) sfail(c, "usage: interrupt");
        S.interrupt();
    } else if (op == "clear-interrupt") {
        if (t.size() != 1) sfail(c, "usage: clear-interrupt");
        S.clearInterrupt();
    } else if (op == "freeze") {
        if (c.SS == NULL) sfail(c, "freeze needs --simp=1");
        if (t.size() != 3 || (t[2] != "0" && t[2] != "1")) sfail(c, "usage: freeze <var> 0|1");
        c.SS->setFrozen(script_var(c, t[1]), t[2] == "1");
    } else if (op == "eliminate") {
        if (c.SS == NULL) sfail(c, "eliminate needs --simp=1");
        int turn_off = 0;
        for (size_t i = 1; i < t.size(); i++)
            if (!script_flag01(c, t[i], "turnoff", turn_off)) sfail(c, "unknown eliminate flag");
        printf("RET %d\n", c.SS->eliminate(turn_off == 1) ? 1 : 0);
    } else {
        sfail(c, "unknown operation");
    }
}

static int run_script(Solver& S, SimpSolver* SS, const char* path) {
    FILE* in = fopen(path, "r");
    if (in == NULL) die("cannot open script '%s'", path);
    ScriptCtx c;
    c.S = &S;
    c.SS = SS;
    c.lineno = 0;
    std::string line;
    int ch;
    bool more = true;
    while (more) {
        line.clear();
        while ((ch = fgetc(in)) != EOF && ch != '\n') line += (char)ch;
        if (ch == EOF) {
            if (ferror(in)) die("read error on '%s'", path);
            more = false;
            if (line.empty()) break;
        }
        c.lineno++;
        c.line = line;
        std::vector<std::string> t = script_tokens(line);
        if (t.empty() || t[0][0] == '#') continue;
        script_op(c, t);
    }
    fclose(in);
    return 0;
}
