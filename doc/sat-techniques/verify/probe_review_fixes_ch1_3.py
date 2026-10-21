#!/usr/bin/env python3
"""Brute-force checks for the examples changed by the review fixes in chapters 1-3 of the
SAT techniques tutorial (ksat-extra/doc/sat-techniques/01..03). Fails loudly on any mismatch."""
import itertools
import sys

FAIL = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        FAIL.append(msg)


def lit(s, names):
    neg = s.startswith("-")
    return (-1 if neg else 1) * (names.index(s.lstrip("-")) + 1)


def parse(clauses, names):
    return [[lit(x, names) for x in c.split()] for c in clauses]


def sat(cl, asg):  # asg: dict var -> bool
    return any(asg.get(abs(l)) == (l > 0) for l in cl)


def models(cnf, n):
    for bits in itertools.product([False, True], repeat=n):
        asg = {i + 1: bits[i] for i in range(n)}
        if all(sat(c, asg) for c in cnf):
            yield asg


def implied(cnf, n, clause):
    return all(sat(clause, m) for m in models(cnf, n))


def propagate(cnf, asg):
    """Unit propagation; returns (assignment, conflict flag)."""
    asg = dict(asg)
    changed = True
    while changed:
        changed = False
        for c in cnf:
            if sat(c, asg):
                continue
            open_ = [l for l in c if abs(l) not in asg]
            if not open_:
                return asg, True
            if len(open_) == 1:
                asg[abs(open_[0])] = open_[0] > 0
                changed = True
    return asg, False


# ---------------- chapter 1 ----------------
N1 = list("abcdefghijk")
F1 = parse(["-a b", "-c d", "-c e", "-f g", "-h i", "-i j", "-i -a -d k", "-j -k -b -e"], N1)
n1 = len(N1)
check(any(True for _ in models(F1, n1)), "ch1 formula is satisfiable")
L1 = parse(["-i -a -b -d -e"], N1)[0]
L2 = parse(["-i -a -d -e"], N1)[0]
L3 = parse(["-i -a -c"], N1)[0]
H_UIP = parse(["-h -a -b -d -e"], N1)[0]
DEC = parse(["-h -a -c"], N1)[0]
for name, c in [("L1", L1), ("L2", L2), ("L3", L3), ("h-UIP cut", H_UIP), ("decision cut", DEC)]:
    check(implied(F1, n1, c), f"ch1 {name} is implied by C1..C8")
# trail after four decisions a,c,f,h (all 1) ends in a conflict on C8
asg = {}
for d in "acfh":
    asg[N1.index(d) + 1] = True
    asg, confl = propagate(F1, asg)
check(confl, "ch1 decisions a,c,f,h all =1 lead to a conflict")
# backjump to level 2 with each candidate learned clause: same forced literals ~i, ~h
lvl2 = {N1.index(v) + 1: True for v in "abcde"}
for name, c in [("L1", L1), ("L2", L2), ("L3", L3)]:
    a2, confl = propagate(F1 + [c], lvl2)
    check(not confl and a2.get(N1.index("i") + 1) is False and a2.get(N1.index("h") + 1) is False,
          f"ch1 at level 2 the learned {name} forces ~i, then C5 forces ~h")
model = {N1.index(v) + 1: v in "abcdefgj" for v in N1}
check(all(sat(c, model) for c in F1 + [L2, L3]), "ch1 final model a..g,j=1, h,i,k=0 satisfies F + L2/L3")

# OTFS toy: D1=(~b c) D2=(~a ~c d) D3=(~c ~d); (~a ~c) implied
N0 = list("abcd")
D = parse(["-b c", "-a -c d", "-c -d"], N0)
check(implied(D, 4, parse(["-a -c"], N0)[0]), "ch1 OTFS: (~a ~c) implied by D1..D3")

# ---------------- chapter 2 ----------------
# phase saving: C1=(a ~b), C2=(b c); a=0 propagates ~b, c; a=1 propagates nothing
N2 = list("abc")
P = parse(["a -b", "b c"], N2)
a0, cf = propagate(P, {1: False})
check(not cf and a0 == {1: False, 2: False, 3: True}, "ch2 phase saving: a=0 forces b=0, c=1")
a1, cf = propagate(P, {1: True})
check(not cf and a1 == {1: True}, "ch2 phase saving: a=1 forces nothing")

# warmup: C1=(~a c), C2=(b ~c d), order a,b,c,d, saved a=1 b=0 c=0 d=1
N3 = list("abcd")
W = parse(["-a c", "b -c d"], N3)
saved = {1: True, 2: False, 3: False, 4: True}
check(not sat(W[0], saved), "ch2 warmup: saved phases falsify C1")
asg = {}
trace = []
for v in [1, 2, 3, 4]:
    if v in asg:
        continue
    asg[v] = saved[v]
    trace.append(("dec", v, saved[v]))
    asg, cf = propagate(W, asg)
    check(not cf, f"ch2 warmup: no conflict after deciding {N3[v-1]}")
check([t[1] for t in trace] == [1, 2], "ch2 warmup: decisions are a then b")
check(asg == {1: True, 2: False, 3: True, 4: True}, "ch2 warmup: result a=1 b=0 c=1 d=1")
check(all(sat(c, asg) for c in W), "ch2 warmup: result satisfies both clauses")

# ---------------- chapter 3 ----------------
# LBD example levels (only the levels matter): a1 b1 c2 d2 e3 f3 g4
lev = dict(a=1, b=1, c=2, d=2, e=3, f=3, g=4)
check(len({lev[v] for v in "bcdf"}) == 3, "ch3 E1 LBD = 3")
check(len({lev[v] for v in "aceg"}) == 4, "ch3 E2 LBD = 4")

if FAIL:
    print(f"{len(FAIL)} check(s) FAILED", file=sys.stderr)
    sys.exit(1)
print("all checks passed")
