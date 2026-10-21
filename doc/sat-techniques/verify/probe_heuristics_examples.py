#!/usr/bin/env python3
"""Throwaway checks for the worked examples in
ksat-extra/doc/sat-techniques/02-heuristics.typ.

Each check prints the numbers used in the text and asserts the claims.
Variables a,b,c,... are 1,2,3,...; a negative int is a negated literal.
"""
import math

A, B, C, D, E, F = 1, 2, 3, 4, 5, 6
NAME = {1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f"}


def lit_str(l):
    return NAME[abs(l)] if l > 0 else "~" + NAME[abs(l)]


def unit_propagate(clauses, assign):
    """assign: dict var->bool. Returns (assign, conflict_flag). Extends in place."""
    changed = True
    while changed:
        changed = False
        for cl in clauses:
            unassigned, sat = [], False
            for l in cl:
                v = abs(l)
                if v in assign:
                    if assign[v] == (l > 0):
                        sat = True
                        break
                else:
                    unassigned.append(l)
            if sat:
                continue
            if not unassigned:
                return assign, True
            if len(unassigned) == 1:
                l = unassigned[0]
                assign[abs(l)] = l > 0
                changed = True
    return assign, False


def satisfies(clauses, assign):
    return all(any(assign[abs(l)] == (l > 0) for l in cl) for cl in clauses)


# ---------------------------------------------------------------- EVSIDS
def check_evsids():
    print("== EVSIDS (score.cpp / bump.c, factor 1/0.95)")
    f = 1000 / 950  # CaDiCaL scorefactor 950; kissat decay 50 -> 1/(1-0.05)
    assert abs(f - 1 / (1 - 0.050)) < 1e-15
    score = {v: 0.0 for v in "abcd"}
    inc = 1.0
    conflicts = [("a", "b"), ("b", "c"), ("a", "c")]
    for i, bumped in enumerate(conflicts, 1):
        for v in bumped:
            score[v] += inc
        inc *= f
        print(f"  after conflict {i}: inc={inc:.4f}",
              {k: round(s, 4) for k, s in score.items()})
    order = sorted(score, key=lambda v: -score[v])
    print("  order:", order)
    assert order == ["c", "a", "b", "d"]
    # Equivalent 'decay everything' view: multiply all by 0.95, bump by 1.
    dec = {v: 0.0 for v in "abcd"}
    for bumped in conflicts:
        for v in dec:
            dec[v] *= 0.95
        for v in bumped:
            dec[v] += 1
    print("  decay view:", {k: round(s, 4) for k, s in dec.items()})
    # proportional: score / inc_before_last_increase == dec / 1 after scaling
    # score_k = sum_j inc_j over bumps, inc_j = f^(j-1); dec = sum 0.95^(k-j)
    k = len(conflicts)
    for v in score:
        assert abs(score[v] / f ** (k - 1) - dec[v]) < 1e-12
    print("  OK: scores = decay-view * f^(k-1)")


# ---------------------------------------------------------------- VMTF
def check_vmtf():
    print("== VMTF move-to-front")
    stamp = {"a": 5, "b": 4, "c": 3, "d": 2, "e": 1}
    nxt = 5
    analyzed = ["b", "d"]
    for v in sorted(analyzed, key=lambda v: stamp[v]):  # old stamp ascending
        nxt += 1
        stamp[v] = nxt
    q = sorted(stamp, key=lambda v: -stamp[v])
    print("  queue front->back:", q, stamp)
    assert q == ["b", "d", "a", "c", "e"]


# ---------------------------------------------------------------- rephase / mode intervals
def check_intervals():
    print("== CaDiCaL rephase limits (rephaseint 1e3, delta = 1e3*(total+1))")
    lim, out = 1000, [1000]
    for total in range(1, 4):
        lim = lim + 1000 * (total + 1)  # assuming rephase exactly at limit
        out.append(lim)
    print("  ", out)
    assert out == [1000, 3000, 6000, 10000]

    print("== kissat rephase deltas 1e3 * n * log10(n+9)^3")
    ds = [int(1000 * n * math.log10(n + 9) ** 3) for n in range(1, 5)]
    print("  ", ds)

    print("== CaDiCaL mode switches (stabilizeint 1e3, factor 200%)")
    inc, lim, pts = 1000, 1000, [1000]
    for _ in range(3):
        inc *= 2
        lim += inc
        pts.append(lim)
    print("  ", pts)
    assert pts == [1000, 3000, 7000, 15000]

    print("== kissat focused-mode forced phase: (switched>>1)&7")
    eps = []
    for ep in range(1, 17):          # focused episode number
        switched = 2 * (ep - 1)      # starts focused with switched=0
        sel = (switched >> 1) & 7
        eps.append((ep, {1: "original", 3: "inverted"}.get(sel, "-")))
    print("  ", eps)
    assert eps[1][1] == "original" and eps[3][1] == "inverted"
    assert eps[9][1] == "original" and eps[11][1] == "inverted"

    print("== kissat random decisions (randecinit 500, randeclength 10)")
    for n in range(1, 4):
        length = int(10 * math.log10(n + 9))
        delta = int(500 * math.log10(n + 9))
        print(f"  sequence {n}: length {length} conflicts, next limit +{delta}")
    assert int(10 * math.log10(10)) == 10


# ---------------------------------------------------------------- Luby / reluctant
def luby(y, x):
    size, seq = 1, 0
    while size < x + 1:
        seq += 1
        size = 2 * size + 1
    while size - 1 != x:
        size = (size - 1) >> 1
        seq -= 1
        x = x % size
    return y ** seq


def check_luby():
    print("== MiniSat Luby (rfirst 100, rinc 2)")
    seq = [int(100 * luby(2, i)) for i in range(15)]
    print("  ", seq)
    assert seq == [100, 100, 200, 100, 100, 200, 400,
                   100, 100, 200, 100, 100, 200, 400, 800]
    cum = [sum(seq[: i + 1]) for i in range(7)]
    print("  cumulative:", cum)

    print("== Knuth reluctant doubling (u,v) vs Luby")
    u = v = 1
    vs = [v]
    for _ in range(14):
        if (u & -u) == v:
            u, v = u + 1, 1
        else:
            v = 2 * v
        vs.append(v)
    print("  v:", vs)
    assert vs == [int(luby(2, i)) for i in range(15)]
    print("  with period 1024:", [1024 * x for x in vs[:7]])


# ---------------------------------------------------------------- EMA
class EMA:
    def __init__(self, window):
        self.alpha = 1.0 / window
        self.beta = 1 - self.alpha
        self.biased = 0.0
        self.exp = 1.0
        self.value = 0.0

    def update(self, y):
        self.biased += self.alpha * (y - self.biased)
        self.exp *= self.beta
        self.value = self.biased / (1 - self.exp)


def check_ema():
    print("== Glucose EMA restarts (fast 33, slow 1e5, margin 10%)")
    fast, slow = EMA(33), EMA(1e5)
    glues = [4] * 1000 + [8] * 10
    rows = []
    for i, g in enumerate(glues, 1):
        fast.update(g)
        slow.update(g)
        restart = fast.value >= 1.1 * slow.value
        rows.append((i, g, fast.value, slow.value, restart))
    for r in rows:
        if r[0] in (1, 10, 1000) or r[0] > 1000:
            print("   conflict %2d glue %d fast %.3f slow %.3f restart=%s" % r)
    assert abs(rows[0][2] - 4) < 1e-9 and abs(rows[0][3] - 4) < 1e-9
    assert not any(r[4] for r in rows[:1000])
    first = next(r[0] for r in rows if r[4])
    print("  first conflict with fast >= 1.1*slow:", first)
    assert first == 1004

    print("== toy EMA alpha=1/2 without bias correction (hand example)")
    x = 0.0
    for g in [4, 4, 8]:
        x += 0.5 * (g - x)
        print("   ", x)


# ---------------------------------------------------------------- trail reuse
def check_reuse():
    print("== trail reuse (kissat reuse_stable_trail)")
    decisions = [("a", 9), ("b", 7), ("c", 4), ("d", 2)]
    limit = 5  # score of next decision e
    res = 0
    while res < len(decisions):
        if decisions[res][1] <= limit:
            break
        res += 1
    print("  backtrack to level", res)
    assert res == 2


# ---------------------------------------------------------------- reorder
def check_reorder():
    print("== kissat reorder weights")
    clauses = [(A, B), (-A, C), (A, -B, C), (-A, -B, -C)]
    table = {s: 2.0 ** -(s - 2) for s in range(2, 101)}
    w = {}
    for cl in clauses:
        for l in cl:
            w[l] = w.get(l, 0) + table[len(cl)]
    res = {}
    for v in (A, B, C):
        p, n = w.get(v, 0), w.get(-v, 0)
        res[NAME[v]] = max(p, n) + 2 * min(p, n)
        print(f"  {NAME[v]}: pos {p} neg {n} -> {res[NAME[v]]}")
    assert res == {"a": 4.5, "b": 3.0, "c": 2.5}


# ---------------------------------------------------------------- warmup
def check_warmup():
    print("== warmup")
    clauses = [(-A, C), (B, -C, D)]
    saved = {A: True, B: False, C: False, D: True}
    print("  saved phases satisfy?", satisfies(clauses, saved))
    assert not satisfies(clauses, saved)
    assign = {}
    for v in (A, B, C, D):  # decision order a,b,c,d
        if v in assign:
            continue
        assign[v] = saved[v]
        assign, confl = unit_propagate(clauses, assign)
        assert not confl
    print("  warmup assignment:", {NAME[k]: int(v) for k, v in assign.items()})
    assert assign == {A: True, C: True, B: False, D: True}
    assert satisfies(clauses, assign)


# ---------------------------------------------------------------- lucky
def check_lucky():
    print("== lucky")
    clauses = [(A, B), (-A, -B), (B, -C)]
    allf = {A: False, B: False, C: False}
    allt = {A: True, B: True, C: True}
    assert not satisfies(clauses, allf) and not satisfies(clauses, allt)
    # forward true (CaDiCaL order: trivially false, trivially true, forward true)
    assign = {}
    for v in (A, B, C):
        if v in assign:
            continue
        assign[v] = True
        assign, confl = unit_propagate(clauses, assign)
        assert not confl
    print("  forward-true:", {NAME[k]: int(v) for k, v in assign.items()})
    assert assign == {A: True, B: False, C: False}
    assert satisfies(clauses, assign)
    # kissat order tries forward false first
    assign = {}
    for v in (A, B, C):
        if v in assign:
            continue
        assign[v] = False
        assign, confl = unit_propagate(clauses, assign)
        assert not confl
    print("  forward-false:", {NAME[k]: int(v) for k, v in assign.items()})
    assert assign == {A: False, B: True, C: False}
    assert satisfies(clauses, assign)


# ---------------------------------------------------------------- walk
def fit_cb(size):
    cb = [(0.0, 2.00), (3.0, 2.50), (4.0, 2.85), (5.0, 3.70), (6.0, 5.10), (7.0, 7.40)]
    i = 0
    while i + 2 < len(cb) and (cb[i][0] > size or cb[i + 1][0] < size):
        i += 1
    (x1, y1), (x2, y2) = cb[i], cb[i + 1]
    return (y2 - y1) * (size - x1) / (x2 - x1) + y1


def check_walk():
    print("== walk (ProbSAT)")
    clauses = [(A, B), (-A, C), (-B, -C), (-A, -B, C)]
    start = {A: True, B: True, C: True}
    broken = [i for i, cl in enumerate(clauses) if not satisfies([cl], start)]
    print("  broken:", [f"C{i+1}" for i in broken])
    assert broken == [2]

    def brk(v):
        a2 = dict(start)
        a2[v] = not a2[v]
        return sum(1 for cl in clauses
                   if satisfies([cl], start) and not satisfies([cl], a2))

    bb, bc = brk(B), brk(C)
    print("  break(b)", bb, "break(c)", bc)
    assert (bb, bc) == (0, 2)
    for cb in (2.0, fit_cb(sum(map(len, clauses)) / len(clauses))):
        sb, sc = cb ** -bb, cb ** -bc
        print(f"  cb={cb:.3f}: p(b)={sb/(sb+sc):.3f} p(c)={sc/(sb+sc):.3f}")
    assert abs(fit_cb(2.25) - 2.375) < 1e-12
    after = dict(start)
    after[B] = False
    assert satisfies(clauses, after)
    afterc = dict(start)
    afterc[C] = False
    print("  flip c instead breaks:",
          [f"C{i+1}" for i, cl in enumerate(clauses) if not satisfies([cl], afterc)])
    print("  OK: flipping b satisfies everything")


# ---------------------------------------------------------------- lookahead
def check_lookahead():
    print("== lookahead")
    clauses = [(-A, B), (-A, C), (-B, D), (-C, -E), (D, E, F)]
    binaries = [cl for cl in clauses if len(cl) == 2]
    occ = set(l for cl in binaries for l in cl)
    probes = sorted(set(-l for l in occ), key=abs)
    res = {}
    for p in probes:
        assign = {abs(p): p > 0}
        assign, confl = unit_propagate(clauses, assign)
        res[lit_str(p)] = (len(assign), confl)
    print("  probes:", res)
    best = max(res, key=lambda k: res[k][0])
    print("  best:", best)
    assert best == "a" and res["a"] == (5, False)
    assert sorted(v[0] for v in res.values())[-2] < 5


if __name__ == "__main__":
    check_evsids()
    check_vmtf()
    check_intervals()
    check_luby()
    check_ema()
    check_reuse()
    check_reorder()
    check_warmup()
    check_lucky()
    check_walk()
    check_lookahead()
    print("ALL CHECKS PASSED")
