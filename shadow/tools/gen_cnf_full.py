#!/usr/bin/env python3
"""Deterministic CNF generator for the cadical-full inprocessing shadow suite.

Writes ksat-extra/shadow/cnf-full/*.cnf plus the per-file option manifest
cnf-full/OPTIONS (one line per file: "<file> <options...>", no options =
upstream defaults under --config=default). Every instance is meant to make the
instrumented upstream CaDiCaL 2.1.3 (cadical-full/build/cadical_full_trace) run
one or more inprocessing techniques with an actual effect (ADD/DEL lines inside
the START/END bracket) within about 2 s. Coverage is checked by
tools/cnf_full_coverage.sh. Everything is seeded with fixed seeds, so re-running
writes byte-identical files.

Scheduling facts from upstream 2.1.3 that the instances are built around (all
limits count conflicts; scale(v) = v * log2(clauses/vars) if that ratio > 2):
  * elim       first at scale(elimint=2000); elim() starts with a full
               subsume() round (subsume, vivify, transred), then elim rounds,
               then block() and cover() (only with --block=1 / --cover=1),
               then instantiate() (only with --instantiate=1)
  * probe      first at probeint=5000; probe() runs decompose, ternary,
               decompose again if ternary derived a binary, deduplicate,
               failed-literal probing rounds, decompose
  * subsume    on its own at scale(subsumeint=1e4), right after a reduce
  * compact    at level 0, >= compactint=2000 conflicts, when at least
               compactmin=100 and compactlim=10% of the variables are inactive
  * condition  off by default; first at conditionint=1e4
  * walk       inside rephase 'W' (4th rephase of stable mode with walk=1)
  * lucky      before search, if no assumptions
  * elim never touches a variable with > elimocclim=100 occurrences of both
    signs, block only considers literals with <= blockocclim=100 negative
    occurrences, instantiate only literals with <= instantiateocclim=1
    occurrence of a variable elim could not remove

The `preprocess` phase (Internal::preprocess_round) only runs when the API call
Solver::limit("preprocessing", n) is made with n > 0. The shadow driver has no
way to make that call, so no CNF file can cover it.

Families (see the functions below for details):
  planted_kcnf      random k-SAT with a hidden model sigma (every clause
                    satisfied by sigma): hard near the threshold, SAT, and any
                    gadget satisfied by sigma keeps it SAT
  random_kcnf       plain random k-SAT (UNSAT/SAT near the threshold)
  equiv_expand      replace every variable by a cycle of k equivalent copies
                    (decompose / compact / deduplicate / transred material)
  gadgets           sigma-consistent binary structure: implication chains with
                    transitive shortcuts (transred), hyper-unary pairs
                    (deduplicate), failed literals (probe)
  blocked_clauses   clauses blocked on a high-occurrence literal (block, cover)
  instantiation     a literal with one occurrence whose clause can be shrunk
                    by propagation (instantiate)
  pigeonhole        PHP(n+1, n)
  parity            Tseitin parity on a random 3-regular graph (XOR gates)
  miter             two structurally different ripple-carry adders compared
                    (AND/XOR gate definitions, structural equivalences)
  lucky             tiny formulas solved by one of the lucky_phases strategies

Usage:
  python3 gen_cnf_full.py           # write cnf-full/*.cnf and cnf-full/OPTIONS
  python3 gen_cnf_full.py --list    # print what would be written
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "cnf-full"))


# ---------------------------------------------------------------------------
# Basic families
# ---------------------------------------------------------------------------

def random_kcnf(nv, k, m, seed):
    """m uniform random k-clauses over 1..nv (distinct variables per clause)."""
    r = random.Random(seed)
    out = []
    for _ in range(m):
        vs = r.sample(range(1, nv + 1), k)
        out.append([v if r.random() < 0.5 else -v for v in vs])
    return out


def planted_kcnf(nv, k, m, seed):
    """Random k-SAT with a hidden model: clauses falsified by sigma are
    rejected. Returns (sigma, clauses), sigma[v] is True/False (index 0 unused)."""
    r = random.Random(seed)
    sigma = [None] + [r.random() < 0.5 for _ in range(nv)]
    out = []
    while len(out) < m:
        vs = r.sample(range(1, nv + 1), k)
        c = [v if r.random() < 0.5 else -v for v in vs]
        if any((l > 0) == sigma[abs(l)] for l in c):
            out.append(c)
    return sigma, out


def true_lit(sigma, v):
    """The literal of variable v that sigma makes true."""
    return v if sigma[v] else -v


def pigeonhole(holes):
    pigeons = holes + 1

    def x(p, h):
        return (p - 1) * holes + h

    out = [[x(p, h) for h in range(1, holes + 1)] for p in range(1, pigeons + 1)]
    for h in range(1, holes + 1):
        for p in range(1, pigeons + 1):
            for q in range(p + 1, pigeons + 1):
                out.append([-x(p, h), -x(q, h)])
    return pigeons * holes, out


def xor_clauses(lits, parity):
    """CNF of XOR(lits) == parity (direct encoding, 2^(n-1) clauses)."""
    n = len(lits)
    out = []
    for mask in range(1 << n):
        # clause excludes the assignment where lit i is true iff bit i set
        ones = bin(mask).count("1")
        if ones % 2 != parity:
            out.append([-l if (mask >> i) & 1 else l for i, l in enumerate(lits)])
    return out


def parity(nodes, seed):
    """Tseitin parity formula on a random 3-regular multigraph-free graph with
    an odd total charge: UNSAT. One variable per edge, one XOR per node."""
    r = random.Random(seed)
    while True:  # configuration model, retry until simple
        stubs = [v for v in range(nodes) for _ in range(3)]
        r.shuffle(stubs)
        edges = [(stubs[i], stubs[i + 1]) for i in range(0, len(stubs), 2)]
        if all(a != b for a, b in edges) and len(set(tuple(sorted(e)) for e in edges)) == len(edges):
            break
    inc = [[] for _ in range(nodes)]
    for i, (a, b) in enumerate(edges):
        inc[a].append(i + 1)
        inc[b].append(i + 1)
    charge = [0] * nodes
    charge[0] = 1
    out = []
    for v in range(nodes):
        out += xor_clauses(inc[v], charge[v])
    return len(edges), out


class Gates:
    """Tiny Tseitin circuit builder (AND / XOR / OR over literals)."""

    def __init__(self, nv=0):
        self.nv = nv
        self.clauses = []

    def new(self):
        self.nv += 1
        return self.nv

    def AND(self, a, b):
        g = self.new()
        self.clauses += [[-g, a], [-g, b], [g, -a, -b]]
        return g

    def OR(self, a, b):
        return -self.AND(-a, -b)

    def XOR(self, a, b):
        g = self.new()
        self.clauses += [[-g, a, b], [-g, -a, -b], [g, -a, b], [g, a, -b]]
        return g


def miter_adders(bits):
    """UNSAT miter: ripple-carry adder with XOR/AND/OR carries versus a
    majority-style carry (AND/OR only), outputs required to differ somewhere."""
    g = Gates(2 * bits)
    a = list(range(1, bits + 1))
    b = list(range(bits + 1, 2 * bits + 1))
    # adder 1: s = a^b^c, c' = (a&b) | (c&(a^b))
    c = None
    s1 = []
    for i in range(bits):
        t = g.XOR(a[i], b[i])
        if c is None:
            s1.append(t)
            c = g.AND(a[i], b[i])
        else:
            s1.append(g.XOR(t, c))
            c = g.OR(g.AND(a[i], b[i]), g.AND(c, t))
    s1.append(c)
    # adder 2: s = (a^c)^b, c' = (a&b) | (a&c) | (b&c)
    c = None
    s2 = []
    for i in range(bits):
        if c is None:
            s2.append(g.XOR(b[i], a[i]))
            c = g.AND(b[i], a[i])
        else:
            s2.append(g.XOR(g.XOR(a[i], c), b[i]))
            c = g.OR(g.OR(g.AND(a[i], b[i]), g.AND(a[i], c)), g.AND(b[i], c))
    s2.append(c)
    diffs = [g.XOR(x, y) for x, y in zip(s1, s2)]
    g.clauses.append(diffs)  # some output bit differs
    return g.nv, g.clauses


def multiplier(g, a, b):
    """Array multiplier: partial products a_i & b_j summed with full adders."""
    n = len(a)
    rows = [[g.AND(a[i], b[j]) for i in range(n)] for j in range(n)]
    acc = rows[0] + [None] * n
    for j in range(1, n):
        carry = None
        for i in range(n):
            x, y = acc[i + j], rows[j][i]
            if x is None:
                s, c = y, None
            else:
                s, c = g.XOR(x, y), g.AND(x, y)
            if carry is not None:
                s2 = g.XOR(s, carry)
                c2 = g.AND(s, carry)
                c = c2 if c is None else g.OR(c, c2)
                s = s2
            acc[i + j] = s
            carry = c
        k = j + n
        acc[k] = carry if acc[k] is None else g.XOR(acc[k], carry)
    return [x for x in acc if x is not None]


def miter_mult(bits):
    """UNSAT commutativity miter a*b != b*a with two array multipliers."""
    g = Gates(2 * bits)
    a = list(range(1, bits + 1))
    b = list(range(bits + 1, 2 * bits + 1))
    p1 = multiplier(g, a, b)
    p2 = multiplier(g, b, a)
    g.clauses.append([g.XOR(x, y) for x, y in zip(p1, p2)])
    return g.nv, g.clauses


# ---------------------------------------------------------------------------
# Structure added on top of a planted formula (all satisfied by sigma)
# ---------------------------------------------------------------------------

def equiv_expand(clauses, nv, k, seed, extra=()):
    """Replace variable v by k copies v_0..v_{k-1} tied by the implication
    cycle v_0 -> v_1 -> ... -> v_{k-1} -> v_0 (an SCC for decompose; for k>=3
    no copy is an equivalence gate, so elim does not substitute them first).
    Every occurrence picks a random copy. `extra` clauses (over the original
    variables) are expanded the same way. Returns (nv*k, clauses, member)
    where member(lit) maps an original literal to a random copy."""
    r = random.Random(seed)

    def copy(v, i):
        return (v - 1) * k + i + 1

    def member(l):
        return (1 if l > 0 else -1) * copy(abs(l), r.randrange(k))

    out = [[member(l) for l in c] for c in clauses]
    out += [[member(l) for l in c] for c in extra]
    if k > 1:
        for v in range(1, nv + 1):
            for i in range(k):
                out.append([-copy(v, i), copy(v, (i + 1) % k)])
    return nv * k, out, member


class Builder:
    """Clause list plus fresh-variable allocation on top of a core formula."""

    def __init__(self, nv, clauses):
        self.nv = nv
        self.clauses = [list(c) for c in clauses]

    def fresh(self):
        self.nv += 1
        return self.nv


def binary_gadgets(b, hyper=0, dups=0, failed=0, chains=0, trfailed=0):
    """Small components on fresh variables, all satisfied by the all-true
    assignment (default phase is true, so search never conflicts on them and
    never learns their units before inprocessing sees them):
      hyper   x1<->x2, y1<->y2, (x1 y1), (x2 -y2): after decompose substitutes
              the equivalences, deduplicate sees (x y), (x -y) and derives x
      dups    a1<->a2, b1<->b2, (a1 b1), (a2 b2): duplicates after decompose
      failed  (p -q), (p -s), (q s t), (q s -t): -p is a failed literal;
              ternary resolves the last two to (q s)
      chains  (-a b), (-b c), (-a c): transred removes the shortcut (binary
              clauses are only traced as DEL at their actual deletion, i.e.
              in a later collect, so this is invisible inside the bracket)
      trfailed (p x), (-x z), (p w), (-w z), (p -y), (y -z): -p reaches z
              and -z in the binary implication graph without the checked
              clause, so transred derives the unit p (needs elim, which
              runs subsume/transred first, to come before probe)"""
    for _ in range(hyper):
        x1, x2, y1, y2 = [b.fresh() for _ in range(4)]
        b.clauses += [[-x1, x2], [-x2, x1], [-y1, y2], [-y2, y1], [x1, y1], [x2, -y2]]
    for _ in range(dups):
        a1, a2, b1, b2 = [b.fresh() for _ in range(4)]
        b.clauses += [[-a1, a2], [-a2, a1], [-b1, b2], [-b2, b1], [a1, b1], [a2, b2]]
    for _ in range(failed):
        p, q, s, t = [b.fresh() for _ in range(4)]
        b.clauses += [[p, -q], [p, -s], [q, s, t], [q, s, -t]]
    for _ in range(chains):
        x, y, z = [b.fresh() for _ in range(3)]
        b.clauses += [[-x, y], [-y, z], [-x, z]]
    for _ in range(trfailed):
        p, x, z, w, y = [b.fresh() for _ in range(5)]
        b.clauses += [[p, x], [-x, z], [p, w], [-w, z], [p, -y], [y, -z]]


def blocked_gadget(b, core_nv, seed, blocked=10, xside=5, aside=5, neg=5):
    """Fresh x, a with
      `blocked` clauses (x a u v)   blocked on x: every clause with -x is
                                     one of the `neg` clauses (-x -a w), so
                                     each resolvent contains a and -a
      `xside` clauses (x u v)        non-tautological resolvents on x
      `aside` clauses (-a u v)       non-tautological resolvents on a
    The extra clauses give x and a more non-tautological resolvents than
    clauses, so bounded variable elimination (bound 0) keeps both and block /
    cover see the blocked clauses. All other literals use pairwise distinct
    core variables, so the asymmetric literal addition in cover does not
    cascade into a conflict (that would only count as an asymmetric
    tautology without removing the clause). Adding blocked clauses preserves
    satisfiability; the side clauses are new constraints. a is the negative
    literal of a fresh variable, so all gadget clauses are satisfied by the
    all-true assignment (default phase): search then does not learn short
    clauses over x, a (e.g. (-x -a), which would subsume the -x clauses)."""
    r = random.Random(seed)
    x, a = b.fresh(), -b.fresh()
    need = 2 * blocked + 2 * xside + 2 * aside + neg
    assert need <= core_nv, "blocked_gadget needs %d distinct core variables" % need
    pool = [v * r.choice((1, -1)) for v in r.sample(range(1, core_nv + 1), need)]
    for _ in range(blocked):
        b.clauses.append([x, a, pool.pop(), pool.pop()])
    for _ in range(xside):
        b.clauses.append([x, pool.pop(), pool.pop()])
    for _ in range(aside):
        b.clauses.append([-a, pool.pop(), pool.pop()])
    for _ in range(neg):
        b.clauses.append([-x, -a, pool.pop()])


def instantiation_gadget(b, core_nv, seed, count=3, protect=110, cside=3):
    """`count` gadgets with fresh variables v_i, a_i, c_i on top of a core
    whose variables occur often in both signs (e.g. random 4-SAT near the
    threshold), so bounded elimination never removes a core variable:
      candidate (-v_i a_i c_i)   the only occurrence of -v_i and of a_i
      chain (v_i c_i p), (-p q), (-q c_i v_i)   (p, q core literals):
                                 -v_i & -c_i propagates to a conflict, so
                                 instantiate can drop -v_i from the
                                 candidate. The middle link is binary, so
                                 hyper ternary resolution cannot derive
                                 (v_i c_i), which would strengthen the
                                 candidate to (a_i c_i) before elim
      `cside` clauses (-c_i y z) c_i gets more non-tautological resolvents
                                 than clauses, so elim keeps it
      `protect` clauses (v_1 .. v_count x y z) and as many
                                 (-a_1 .. -a_count x y z) over core literals:
                                 above elimocclim=100 occurrences (with a
                                 margin for clauses removed before elim), so
                                 elim skips v_i and a_i
    Every clause touching v_i has only gadget or (never eliminated) core
    variables, so v_i is not re-marked as an elimination candidate (that
    would exclude it from instantiation). v_i and a_i are true in the default
    phase, so the protect clauses are satisfied and search never involves
    v_i in a conflict. The variable order v_i < a_i together with equal
    scores makes vivify sort a_i last in the candidate; vivify's own
    instantiation of a_i fails, so vivify leaves the candidate alone."""
    r = random.Random(seed)

    def core(n):
        return [w * r.choice((1, -1)) for w in r.sample(range(1, core_nv + 1), n)]

    vs = [b.fresh() for _ in range(count)]
    cs = [b.fresh() for _ in range(count)]
    avars = [b.fresh() for _ in range(count)]  # a_i: larger indices than v_i
    for v, a, c in zip(vs, avars, cs):
        p, q = core(2)
        b.clauses += [[-v, a, c], [v, c, p], [-p, q], [-q, c, v]]
        for _ in range(cside):
            b.clauses.append([-c] + core(2))
    for _ in range(protect):
        b.clauses.append(vs + core(3))
    for _ in range(protect):
        b.clauses.append([-a for a in avars] + core(3))


# ---------------------------------------------------------------------------
# The suite
# ---------------------------------------------------------------------------

def horn_lucky(nv, m, seed):
    """Satisfiable Horn formula (unit (1), implications towards larger
    indices, one all-negative clause): neither trivially false- nor
    true-satisfiable, solved by one of the later lucky_phases strategies
    without any search conflict."""
    r = random.Random(seed)
    out = [[1]]
    while len(out) < m:
        vs = sorted(r.sample(range(1, nv + 1), r.choice((2, 3))))
        out.append([-v for v in vs[:-1]] + [vs[-1]])
    out.append([-v for v in r.sample(range(2, nv + 1), 3)])
    return nv, out


def specs():
    """List of (name, nv, clauses, options, comment). Seeds and sizes were
    chosen with the instrumented reference (see the module docstring); the
    expected coverage is checked by tools/cnf_full_coverage.sh."""
    S = []
    R4 = (60, 4, 594, 2)  # random 4-SAT, ratio 9.9, UNSAT, ~9k conflicts

    def r4core():
        nv, k, m, seed = R4
        return nv, random_kcnf(nv, k, m, seed)

    # 1. Binary-implication gadgets on a high-ratio UNSAT core: probe (5000
    #    conflicts) runs before elim (scale(2000) ~ 5600), so decompose sees
    #    the input SCCs, deduplicate the hyper-unary pairs, probe the failed
    #    literals, ternary the (q s t)/(q s -t) pairs.
    nv, core = r4core()
    b = Builder(nv, core)
    binary_gadgets(b, hyper=3, dups=3, failed=3, chains=3)
    S.append(("bin_gadgets_r4.cnf", b.nv, b.clauses, [],
              "random 4-SAT core (n=60, m=594, seed=2) + binary_gadgets(hyper=3, dups=3,\n"
              "failed=3, chains=3): decompose, deduplicate, probe, ternary, elim, subsume, vivify"))

    # 2. Low-ratio parity core: elim (with subsume/vivify/transred) runs before
    #    probe, so transred finds the failed literals of the trfailed gadgets.
    nv, core = parity(40, 1)
    b = Builder(nv, core)
    binary_gadgets(b, chains=2, trfailed=4)
    S.append(("transred_parity40.cnf", b.nv, b.clauses, [],
              "Tseitin parity, random 3-regular graph with 40 nodes (seed=1) +\n"
              "binary_gadgets(chains=2, trfailed=4): transred units, elim (XOR gates)"))

    # 3. compact: 110 fixed fresh variables (> compactmin=100, > 10%).
    nv, core = parity(40, 1)
    b = Builder(nv, core)
    for _ in range(110):
        b.clauses.append([b.fresh()])
    S.append(("compact_units_parity40.cnf", b.nv, b.clauses, [],
              "Tseitin parity (40 nodes, seed=1) + 110 unit clauses on fresh variables:\n"
              "compact after 2000 conflicts"))

    # 4. Every core variable replaced by a 3-cycle of copies: large SCC
    #    substitution in decompose, then compact on the substituted variables.
    nv, core = r4core()
    nv, cl, _ = equiv_expand(core, nv, 3, 5)
    S.append(("equiv_expand_r4.cnf", nv, cl, [],
              "random 4-SAT core (n=60, m=594, seed=2), every variable expanded into an\n"
              "implication 3-cycle of copies (seed=5): decompose, compact"))

    # 5. walk: the 4th rephase in stable mode is 'W'.
    nv, cl = parity(56, 1)
    S.append(("walk_parity56.cnf", nv, cl, [],
              "Tseitin parity, random 3-regular graph with 56 nodes (seed=1): walk"))

    # 6. lucky
    nv, cl = horn_lucky(60, 150, 1)
    S.append(("lucky_horn.cnf", nv, cl, [],
              "satisfiable Horn formula (60 vars, seed=1): solved by lucky_phases"))

    # 7.-9. blocked clauses (block, cover, condition are off by default)
    for name, seed, opt, what in (("block_gadget_r4.cnf", 2, "--block=1", "block"),
                                  ("cover_gadget_r4.cnf", 1, "--cover=1", "cover"),
                                  ("condition_gadget_r4.cnf", 1, "--condition=1", "condition")):
        nv, core = r4core()
        b = Builder(nv, core)
        blocked_gadget(b, nv, seed)
        S.append((name, b.nv, b.clauses, [opt],
                  "random 4-SAT core (n=60, m=594, seed=2) + blocked_gadget(seed=%d): %s\n"
                  "(run with %s)" % (seed, what, opt)))

    # 10. instantiate (off by default)
    nv = 64
    core = random_kcnf(nv, 4, int(nv * 9.9), 2)
    b = Builder(nv, core)
    instantiation_gadget(b, nv, 1)
    S.append(("instantiate_gadget_r4.cnf", b.nv, b.clauses, ["--instantiate=1"],
              "random 4-SAT core (n=64, m=633, seed=2) + instantiation_gadget(seed=1):\n"
              "instantiate (run with --instantiate=1)"))
    return S


def write_cnf(path, nv, clauses, comment):
    lines = ["c " + c for c in comment.splitlines()]
    lines.append("p cnf %d %d" % (nv, len(clauses)))
    lines += [" ".join(str(l) for l in c) + " 0" for c in clauses]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    list_only = "--list" in sys.argv[1:]
    all_specs = specs()
    if list_only:
        for name, nv, cl, opts, _ in all_specs:
            print("%-28s vars=%-5d clauses=%-6d %s" % (name, nv, len(cl), " ".join(opts)))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = []
    for name, nv, cl, opts, comment in all_specs:
        write_cnf(os.path.join(OUT_DIR, name), nv, cl, comment)
        manifest.append((name + " " + " ".join(opts)).rstrip())
        print("wrote %-28s vars=%-5d clauses=%-6d %s" % (name, nv, len(cl), " ".join(opts)))
    with open(os.path.join(OUT_DIR, "OPTIONS"), "w") as f:
        f.write("\n".join(manifest) + "\n")


if __name__ == "__main__":
    main()
