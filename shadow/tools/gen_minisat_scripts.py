#!/usr/bin/env python3
"""Durable, deterministic generator of the incremental MiniSat shadow scripts.

Writes ../minisat-scripts/<name>.core.ops (run with --simp=0) and <name>.simp.ops (--simp=1) in
the operation format of ../minisat-full/driver_script.h (the drivers' --script mode; Kotlin mirror
MiniSatShadowDriver.runScript). Everything is seeded (random.Random(seed).random() only), so
re-running reproduces byte-identical files. Kept in the repo (never-delete rule).

Both variants of a script run the same operations. The .simp variant follows SimpSolver's usage
contract (a variable that is eliminated must never be referenced again): before the first
solve/eliminate it freezes every variable that a later operation references, and it freezes every
`newvar` right after creation. Scripts using SimpSolver-only operations (eliminate, solve flags)
have only a .simp variant. Variables released with `release` are never referenced again by
number; a reused variable (free_vars) is only reached through `newvar` (@k).

Covered: add-after-solve, changing assumptions, failed assumptions / cores (FAILED after UNSAT),
releaseVar + reuse through free_vars, conflict / propagation budgets (solveLimited returning
l_Undef, then continuing), interrupt / clearInterrupt, user polarity and decision flags,
simp=1 with frozen variables and later solves (do_simp, turn_off_simp, explicit eliminate).

Usage:
  python3 gen_minisat_scripts.py           # (re)write ../minisat-scripts/
  python3 gen_minisat_scripts.py --list    # print what would be written
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "minisat-scripts"))

import random as _random


class Rng:
    """Only random() of the Mersenne Twister (stable across Python versions)."""

    def __init__(self, seed):
        self.r = _random.Random(seed)

    def below(self, n):
        return int(self.r.random() * n)

    def chance(self, p):
        return self.r.random() < p

    def lit(self, nvars):
        v = 1 + self.below(nvars)
        return v if self.chance(0.5) else -v

    def sample(self, items, k):
        items = list(items)
        out = []
        for _ in range(min(k, len(items))):
            out.append(items.pop(self.below(len(items))))
        return out


def rand_clause(rng, nvars, k=3):
    vs = rng.sample(range(1, nvars + 1), k)
    return [v if rng.chance(0.5) else -v for v in vs]


def php(holes):
    """PHP(holes+1, holes): var p*holes + h + 1 = pigeon p in hole h."""
    pigeons = holes + 1
    x = lambda p, h: p * holes + h + 1
    cls = [[x(p, h) for h in range(holes)] for p in range(pigeons)]
    for h in range(holes):
        for p in range(pigeons):
            for q in range(p + 1, pigeons):
                cls.append([-x(p, h), -x(q, h)])
    return pigeons * holes, cls


class Script:
    """Operations as token lists. Literal tokens are ints (numeric variables) or '@k' strings."""

    def __init__(self, name, comment, simp_only=False):
        self.name = name
        self.comment = comment
        self.simp_only = simp_only
        self.ops = []
        self.nnew = 0

    def op(self, *toks):
        self.ops.append([str(t) for t in toks])

    def add(self, lits):
        self.op("add", *(list(lits) + [0]))

    def assume(self, lits):
        self.op("assume", *(list(lits) + [0]))

    def touch(self, n):
        """`add n -n 0`: a tautology (dropped by addClause_) that creates variables 1..n."""
        self.add([n, -n])

    def newvar(self, *flags):
        self.op("newvar", *flags)
        self.nnew += 1
        return "@%d" % self.nnew

    # -- the .simp variant: freezes (see module doc) --------------------------------------------
    def simp_ops(self):
        def var_tokens(op):
            name = op[0]
            if name in ("add", "assume"):
                toks = op[1:-1]
            elif name in ("release", "polarity", "decision", "freeze"):
                toks = op[1:2]
            else:
                return []
            return [t.lstrip("-") for t in toks]

        first = None
        for i, op in enumerate(self.ops):
            if op[0] in ("solve", "eliminate"):
                first = i
                break
        out = []
        if first is not None:
            later = []
            for op in self.ops[first:]:
                for t in var_tokens(op):
                    if not t.startswith("@") and t not in later:
                        later.append(t)
            later.sort(key=int)
        for i, op in enumerate(self.ops):
            if i == first:
                for t in later:
                    out.append(["freeze", t, "1"])
            out.append(op)
            if op[0] == "newvar":
                out.append(["freeze", "@%d" % sum(1 for o in self.ops[: i + 1] if o[0] == "newvar"), "1"])
        return out

    def render(self, ops):
        lines = ["# " + c for c in self.comment.splitlines()]
        lines.append("# generated by ksat-extra/shadow/tools/gen_minisat_scripts.py")
        lines += [" ".join(op) for op in ops]
        return "\n".join(lines) + "\n"

    def files(self):
        out = []
        if not self.simp_only:
            out.append((self.name + ".core.ops", self.render(self.ops)))
        out.append((self.name + ".simp.ops", self.render(self.simp_ops())))
        return out


# ---------------------------------------------------------------------------------------------
# hand-shaped scripts

def s_add_after_solve():
    s = Script("add_after_solve", "random 3-SAT, 30 vars: solve, then add clauses in batches until UNSAT")
    rng = Rng(101)
    for _ in range(90):
        s.add(rand_clause(rng, 30))
    s.op("solve")
    for _ in range(10):
        for _ in range(8):
            s.add(rand_clause(rng, 30))
        s.op("solve")
    return s


def s_changing_assumptions():
    s = Script("changing_assumptions", "random 3-SAT, 40 vars: solves under changing assumption sets")
    rng = Rng(202)
    for _ in range(150):
        s.add(rand_clause(rng, 40))
    for k in range(12):
        s.assume([rng.lit(40) for _ in range(1 + rng.below(7))])
        s.op("solve")
    s.assume([])
    s.op("solve")
    return s


def s_failed_cores():
    s = Script("failed_cores", "PHP(5,4) with a selector per clause: cores (FAILED) under selector assumptions")
    n, cls = php(4)
    sel = []
    for i, c in enumerate(cls):
        a = n + 1 + i
        sel.append(a)
        s.add(c + [-a])
    rng = Rng(303)
    s.assume(sel)
    s.op("solve")
    for _ in range(8):
        s.assume(rng.sample(sel, 1 + rng.below(len(sel))))
        s.op("solve")
    s.assume([-sel[0]] + sel[1:])
    s.op("solve")
    return s


def s_failed_units():
    s = Script("failed_units", "assumptions contradicting top-level units and each other")
    s.add([1, 2])
    s.add([-1, 3])
    s.add([-3, -2, 4])
    s.add([5])
    for a in ([-5], [1, -3], [2, -4, 1], [-2, -1], [4, -4], [3, 5, -2, 1, -4]):
        s.assume(a)
        s.op("solve")
    s.add([-5])
    s.assume([1])
    s.op("solve")
    s.assume([])
    s.op("solve")
    return s


def s_release_reuse():
    s = Script("release_reuse", "releaseVar + simplify moves the variable to free_vars, newvar reuses it\n"
               "(simplify does the move only when it is not skipped: before the first solve it always runs)")
    rng = Rng(404)
    s.touch(20)
    for _ in range(55):
        s.add(rand_clause(rng, 20))
    a = s.newvar()
    b = s.newvar()
    for _ in range(6):
        s.add([a] + rand_clause(rng, 20, 2))
        s.add(["-" + b] + rand_clause(rng, 20, 2))
    s.op("release", a)
    s.op("release", "-" + b)
    s.op("simplify")
    c = s.newvar()                      # reuses b's variable (free_vars.last())
    d = s.newvar("pol=f")               # reuses a's variable
    e = s.newvar("pol=t", "dvar=1")     # a new variable
    for _ in range(5):
        s.add([c, "-" + d] + rand_clause(rng, 20, 1))
        s.add(["-" + c, e] + rand_clause(rng, 20, 1))
    s.assume(["-" + c])
    s.op("solve")
    s.assume([d, "-" + e])
    s.op("solve")
    s.assume([])
    s.op("release", c)
    s.op("solve")                       # search's own simplify() may move c to free_vars
    s.op("simplify")
    f = s.newvar()
    s.add([f, "-" + e])
    s.assume(["-" + f])
    s.op("solve")
    s.op("release", "-" + f)
    s.op("release", d)
    s.assume([])
    s.op("solve")
    s.op("simplify")
    g = s.newvar()
    h = s.newvar()
    s.add([g, h, e])
    s.add(["-" + g, "-" + h])
    s.assume([g])
    s.op("solve")
    return s


def s_conf_budget():
    s = Script("conf_budget", "PHP(7,6): conflict budgets, solveLimited l_Undef then continuing")
    _, cls = php(6)
    for c in cls:
        s.add(c)
    for k in (5, 0, 20, 200, 1000):
        s.op("budget", "conf=%d" % k)
        s.op("solve")
    s.op("budget", "off")
    s.op("solve")
    return s


def s_prop_budget():
    s = Script("prop_budget", "random 3-SAT 60 vars near the threshold: propagation budgets")
    rng = Rng(505)
    for _ in range(255):
        s.add(rand_clause(rng, 60))
    for k in (50, 300, 2000, 10000):
        s.op("budget", "prop=%d" % k)
        s.op("solve")
    s.op("budget", "off")
    s.op("solve")
    s.assume([rng.lit(60), rng.lit(60)])
    s.op("budget", "conf=3")
    s.op("solve")
    s.op("budget", "off")
    s.op("solve")
    return s


def s_interrupt():
    s = Script("interrupt", "interrupt() before solve: l_Undef; clearInterrupt() then solve")
    _, cls = php(4)
    for c in cls:
        s.add(c)
    s.op("interrupt")
    s.op("solve")
    s.op("solve")
    s.op("clear-interrupt")
    s.op("solve")
    return s


def s_polarity_decision():
    s = Script("polarity_decision", "user polarities and decision flags between solves")
    rng = Rng(606)
    s.touch(25)
    for _ in range(70):
        s.add(rand_clause(rng, 25))
    for v in range(1, 26, 2):
        s.op("polarity", v, "t")
    s.op("solve")
    for v in range(1, 26, 3):
        s.op("polarity", v, "f")
    s.op("decision", 4, "0")
    s.op("decision", 9, "0")
    s.op("solve")
    s.op("decision", 4, "1")
    s.op("polarity", 1, "u")
    s.op("solve")
    return s


def s_simp_frozen():
    s = Script("simp_frozen", "SimpSolver: solve with elimination, later adds on frozen variables, turn_off_simp",
               simp_only=True)
    rng = Rng(707)
    for _ in range(110):
        s.add(rand_clause(rng, 40))
    s.op("solve")
    for _ in range(8):
        s.add(rand_clause(rng, 12))
    s.assume([1, -2])
    s.op("solve")
    s.assume([])
    s.op("solve", "simp=0")
    for _ in range(8):
        s.add(rand_clause(rng, 12))
    s.op("solve", "turnoff=1")
    for _ in range(8):
        s.add(rand_clause(rng, 12))
    s.op("solve")
    return s


def s_simp_eliminate():
    s = Script("simp_eliminate", "SimpSolver: explicit eliminate, then incremental solves", simp_only=True)
    _, cls = php(5)
    rng = Rng(808)
    for c in cls[:-6]:
        s.add(c)
    s.op("eliminate")
    s.op("solve", "simp=0")
    s.assume([1, 7])
    s.op("solve")
    s.assume([])
    for c in cls[-6:]:
        s.add(c)
    s.op("eliminate", "turnoff=1")
    s.op("solve")
    return s


def s_simp_newvar():
    s = Script("simp_newvar", "SimpSolver: new variables after elimination, release, assumptions",
               simp_only=True)
    rng = Rng(909)
    for _ in range(80):
        s.add(rand_clause(rng, 30))
    s.op("solve")
    a = s.newvar()
    b = s.newvar("pol=t")
    for _ in range(5):
        s.add([a, b] + rand_clause(rng, 6, 1))
        s.add(["-" + a] + rand_clause(rng, 6, 2))
    s.assume(["-" + b])
    s.op("solve")
    s.op("release", "-" + b)
    s.assume([])
    s.op("solve")
    s.op("solve", "turnoff=1")
    c = s.newvar()
    s.op("release", c)
    s.op("simplify")
    d = s.newvar()
    s.add([d, a])
    s.assume(["-" + d])
    s.op("solve")
    return s


# ---------------------------------------------------------------------------------------------
# random op sequences

def s_random(idx):
    seed = 1000 + idx
    rng = Rng(seed)
    nvars = 20 + rng.below(30)
    ratio = 3.0 + rng.r.random() * 1.2
    s = Script("random_%02d" % idx, "random incremental script, seed %d, %d vars" % (seed, nvars))
    released = set()      # numeric variables never to be referenced again
    newvars = []          # live @k tokens
    assumed = []

    def live_var():
        pool = [v for v in range(1, nvars + 1) if v not in released]
        if newvars and rng.chance(0.25):
            return newvars[rng.below(len(newvars))]
        return pool[rng.below(len(pool))]

    def lit():
        v = live_var()
        neg = rng.chance(0.5)
        return ("-" + v if neg else v) if isinstance(v, str) else (-v if neg else v)

    def clause(k):
        out = []
        while len(out) < k:
            l = lit()
            if l not in out:
                out.append(l)
        return out

    s.touch(nvars)
    for _ in range(int(nvars * ratio)):
        s.add(clause(3))
    for _ in range(14 + rng.below(10)):
        r = rng.r.random()
        if r < 0.30:
            s.op("solve")
        elif r < 0.45:
            for _ in range(1 + rng.below(6)):
                s.add(clause(2 + rng.below(3)))
        elif r < 0.60:
            assumed = [lit() for _ in range(rng.below(5))]
            s.assume(assumed)
        elif r < 0.66:
            pool = [v for v in range(1, nvars + 1) if v not in released]
            v = pool[rng.below(len(pool))]
            s.op("release", -v if rng.chance(0.5) else v)
            released.add(v)
            if any(abs(l) == v for l in assumed if isinstance(l, int)):
                assumed = [l for l in assumed if not (isinstance(l, int) and abs(l) == v)]
                s.assume(assumed)
        elif r < 0.71:
            s.op("simplify")
        elif r < 0.77:
            newvars.append(s.newvar(*(["pol=" + "tfu"[rng.below(3)]] if rng.chance(0.5) else [])))
        elif r < 0.83:
            s.op("budget", "conf=%d" % rng.below(30))
            s.op("solve")
            s.op("budget", "off")
        elif r < 0.88:
            s.op("budget", "prop=%d" % (10 + rng.below(500)))
            s.op("solve")
            s.op("budget", "off")
        elif r < 0.94:
            v = live_var()
            if isinstance(v, int):
                s.op("polarity", v, "tfu"[rng.below(3)])
        else:
            v = live_var()
            if isinstance(v, int):
                s.op("decision", v, "1" if rng.chance(0.6) else "0")
    s.op("solve")
    return s


def all_scripts():
    out = [s_add_after_solve(), s_changing_assumptions(), s_failed_cores(), s_failed_units(),
           s_release_reuse(), s_conf_budget(), s_prop_budget(), s_interrupt(), s_polarity_decision(),
           s_simp_frozen(), s_simp_eliminate(), s_simp_newvar()]
    out += [s_random(i) for i in range(10)]
    return out


def main():
    files = []
    for s in all_scripts():
        files += s.files()
    if "--list" in sys.argv[1:]:
        for name, text in files:
            print("%-36s %5d ops" % (name, sum(1 for l in text.splitlines() if l and not l.startswith("#"))))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for old in os.listdir(OUT_DIR):
        if old.endswith(".ops"):
            os.remove(os.path.join(OUT_DIR, old))
    for name, text in files:
        with open(os.path.join(OUT_DIR, name), "w") as f:
            f.write(text)
    print("wrote %d scripts to %s" % (len(files), OUT_DIR))


if __name__ == "__main__":
    main()
