#!/usr/bin/env python3
"""Brute-force checks for the worked examples in
ksat-extra/doc/sat-techniques/05-probing-equivalences.typ.

Throwaway verification helper (stdlib only). Every check asserts; the script
exits non-zero on the first wrong claim. Literals are strings: 'a', '-a'.
"""
import itertools
import sys


def cl(s):
    return tuple(s.split())


def var(l):
    return l.lstrip('-')


def neg(l):
    return l[1:] if l.startswith('-') else '-' + l


def variables(F):
    return sorted({var(l) for c in F for l in c})


def sat_lit(l, m):
    return m[var(l)] == (not l.startswith('-'))


def models(F, vs=None):
    vs = vs or variables(F)
    out = []
    for bits in itertools.product([False, True], repeat=len(vs)):
        m = dict(zip(vs, bits))
        if all(any(sat_lit(l, m) for l in c) for c in F):
            out.append(m)
    return out


def implies(F, clause, vs=None):
    vs = sorted(set(vs or variables(F)) | {var(l) for l in clause})
    return all(any(sat_lit(l, m) for l in clause) for m in models(F, vs))


def up(F, assumptions):
    """Unit propagation. Returns (set of true literals, conflict?)."""
    true = set(assumptions)
    changed = True
    while changed:
        changed = False
        for c in F:
            if any(l in true for l in c):
                continue
            open_ = [l for l in c if neg(l) not in true]
            if not open_:
                return true, True
            if len(open_) == 1:
                true.add(open_[0])
                changed = True
    return true, False


def resolve(c1, c2, pivot):
    assert pivot in c1 and neg(pivot) in c2
    r = [l for l in c1 if l != pivot] + [l for l in c2 if l != neg(pivot)]
    return tuple(sorted(set(r)))


def same_models(F, G, vs):
    key = lambda ms: sorted(tuple(sorted(m.items())) for m in ms)
    return key(models(F, vs)) == key(models(G, vs))


def ok(name):
    print(f"OK  {name}")


# ---------------------------------------------------------------- E1 FLP
F = [cl("-a b"), cl("-a c"), cl("-b -c d"), cl("-b -d"), cl("a e f")]
true, conflict = up(F, ["a"])
assert conflict, "probe a must fail"
assert implies(F, cl("-a"))
_, c2 = up(F, ["-a"])
assert not c2
assert models(F), "formula should stay satisfiable"
ok("E1 failed literal: probing a conflicts, unit -a implied")

# ---------------------------------------------------------------- E2 HBR
F = [cl("-a b"), cl("-a c"), cl("-b -c d"), cl("a -d e")]
true, conflict = up(F, ["a"])
assert not conflict and {"b", "c", "d"} <= true
bins = [c for c in F if len(c) == 2]
tb, _ = up(bins, ["a"])
assert {"b", "c"} <= tb and "d" not in tb  # d needs the ternary clause
hbr = resolve(resolve(F[2], F[0], "-b"), F[1], "-c")
assert hbr == tuple(sorted(("-a", "d"))), hbr
assert implies(F, cl("-a d"))
# a is a root of the BIG: occurs only negatively in binary clauses
assert all("a" not in c for c in bins) and any("-a" in c for c in bins)
ok("E2 hyper-binary resolvent (-a d) derived and implied; a is a BIG root")

# ---------------------------------------------------------------- E3 vivify
C1 = cl("a b c d")
rest = [cl("a e"), cl("-e -c"), cl("b -e f"), cl("b -e -f")]
t1, k1 = up(rest, ["-a"])
assert not k1 and {"e", "-c"} <= t1
t2, k2 = up(rest, ["-a", "-b"])
assert k2
assert implies(rest, cl("a b"))
vs = variables(rest + [C1])
assert same_models(rest + [C1], rest + [cl("a b")], vs)
ok("E3 vivification: (a b c d) shrinks to (a b), implied by the rest")

# ---------------------------------------------------------------- E4 SCC/ELS
F = [cl("-a b"), cl("-b c"), cl("-c a"), cl("b d e"), cl("-c -d"),
     cl("b -c e")]
# build BIG and run a simple SCC (Kosaraju)
edges = {}
for c in F:
    if len(c) == 2:
        x, y = c
        edges.setdefault(neg(x), set()).add(y)
        edges.setdefault(neg(y), set()).add(x)
nodes = set(edges) | {w for s in edges.values() for w in s}
reach = {n: up([c for c in F if len(c) == 2], [n])[0] for n in nodes}
sccs = {frozenset(m for m in nodes if m in reach[n] and n in reach[m])
        for n in nodes}
assert frozenset({"a", "b", "c"}) in sccs
assert frozenset({"-a", "-b", "-c"}) in sccs
for m in models(F):
    assert m["a"] == m["b"] == m["c"]
G = [cl("a d e"), cl("-a -d")]  # substituted: b->a, c->a, C6 tautology
mf = sorted(tuple(sorted(m.items())) for m in models(F))
mg = []
for m in models(G, ["a", "d", "e"]):
    m = dict(m)
    m["b"] = m["a"]
    m["c"] = m["a"]
    mg.append(tuple(sorted(m.items())))
assert mf == sorted(mg)
ok("E4 SCC {a,b,c}; substitution + reconstruction gives exactly F's models")

# ---------------------------------------------------------------- E5 transred
F = [cl("-a b"), cl("-b c"), cl("-a c")]
assert implies(F[:2], cl("-a c"))
assert same_models(F, F[:2], ["a", "b", "c"])
ok("E5 transitive edge (-a c) redundant")

# ---------------------------------------------------------------- E6 ternary
X = [cl("a b -c"), cl("-a -b -c"), cl("-a b c"), cl("a -b c"),
     cl("a b -d"), cl("-a -b -d"), cl("-a b d"), cl("a -b d")]
R1 = resolve(cl("a b -c"), cl("-a b d"), "a")
R2 = resolve(cl("-a -b -c"), cl("a -b d"), "-a")
R3 = resolve(R1, R2, "b")
assert set(R1) == {"b", "-c", "d"} and set(R2) == {"-b", "-c", "d"}
assert set(R3) == {"-c", "d"}
for r in (R1, R2, R3, cl("c -d")):
    assert implies(X, r)
for m in models(X):
    assert m["c"] == m["d"]
for p in ("c", "-c", "d", "-d"):
    t, k = up(X, [p])
    assert t == {p} and not k, (p, t)
ok("E6 ternary resolvents (b -c d), (-b -c d), (-c d) implied; c==d; "
   "probing c/d propagates nothing")

# ---------------------------------------------------------------- E7 backbone
F = [cl("-a b"), cl("-a c"), cl("-b -c"), cl("a d"), cl("-d e f"),
     cl("-e -f")]
ms = models(F)
vs = variables(F)
backbone = {(v if all(m[v] for m in ms) else "-" + v)
            for v in vs if len({m[v] for m in ms}) == 1}
assert backbone == {"-a", "d"}, backbone
bins = [c for c in F if len(c) == 2]
mb = models(bins, vs)
bb2 = {(v if all(m[v] for m in mb) else "-" + v)
       for v in vs if len({m[v] for m in mb}) == 1}
assert bb2 == {"-a", "d"}, bb2
_, k = up(bins, ["a"])
assert k
t, k = up(bins, ["-a"])
assert not k and "d" in t
ok("E7 backbone {-a, d}; also backbone of binary clauses; probe a fails")

# ---------------------------------------------------------------- E8 congruence
def AND(o, i, j):
    return [cl(f"-{o} {i}"), cl(f"-{o} {j}"), cl(f"{o} -{i} -{j}")]


F = AND("g", "a", "b") + AND("h", "a", "b") + AND("p", "g", "c") + \
    AND("q", "h", "c")
ms = models(F)
assert ms
for m in ms:
    assert m["g"] == m["h"] and m["p"] == m["q"]
# p,q not syntactically same before merging g,h; after merging they are.
ok("E8 congruence: g==h and then p==q in all models")

def XOR(o, i, j):
    return [cl(f"-{o} {i} {j}"), cl(f"-{o} -{i} -{j}"),
            cl(f"{o} -{i} {j}"), cl(f"{o} {i} -{j}")]


F = XOR("g", "a", "b") + XOR("h", "a", "b")
for m in models(F):
    assert m["g"] == m["h"]
for p in ("g", "-g", "h", "-h"):
    t, k = up(F, [p])
    assert t == {p} and not k
ok("E8b XOR congruence: g==h; probing g/h propagates nothing")

# ---------------------------------------------------------------- E9 sweeping
F = XOR("x", "a", "b") + \
    [cl("-u a"), cl("-u -b"), cl("u -a b")] + \
    [cl("-v -a"), cl("-v b"), cl("v a -b")] + \
    [cl("-y u v"), cl("y -u"), cl("y -v")]
assert len(F) == 13
ms = models(F)
assert len(ms) == 4
for m in ms:
    assert m["x"] == m["y"]
assert not models(F + [cl("x"), cl("-y")])
assert not models(F + [cl("-x"), cl("y")])
for p in ("x", "-x", "y", "-y"):
    t, k = up(F, [p])
    assert not k
    other = "y" if var(p) == "x" else "x"
    assert other not in t and neg(other) not in t, (p, t)
# environment from a with kissat's depth rule (default sweepdepth = 2)
env_vars = ["a"]
env = []
expand, nxt, depth = 0, 1, 1
while True:
    if expand == nxt:
        if depth >= 2:
            break
        nxt = len(env_vars)
        if expand == nxt:
            break
        depth += 1
    v = env_vars[expand]
    for c in F:
        if v in map(var, c) and c not in env:
            env.append(c)
            for l in c:
                if var(l) not in env_vars:
                    env_vars.append(var(l))
    expand += 1
assert len(env) == 13, len(env)
# the model table in the text (rows over a b x u v y)
table = [(1, 0, 1, 1, 0, 1), (0, 0, 0, 0, 0, 0), (0, 1, 1, 0, 1, 1),
         (1, 1, 0, 0, 0, 0)]
names = ["a", "b", "x", "u", "v", "y"]
for row in table:
    m = {n: bool(b) for n, b in zip(names, row)}
    assert all(any(sat_lit(l, m) for l in c) for c in F), row
# partition refinement: start with literals true in the first model
first = {n: bool(b) for n, b in zip(names, table[0])}
cands = [n if first[n] else "-" + n for n in names]
classes = [cands]
for row in table[1:]:
    m = {n: bool(b) for n, b in zip(names, row)}
    new = []
    for cls in classes:
        t = [l for l in cls if sat_lit(l, m)]
        f = [l for l in cls if not sat_lit(l, m)]
        new += [s for s in (t, f) if len(s) >= 2]
    classes = new
assert classes == [["x", "y"]], classes
# backbone candidates: no literal is true in all four models
assert not [l for l in cands
            if all(sat_lit(l, {n: bool(b) for n, b in zip(names, r)})
                   for r in table)]
ok("E9 sweeping: env(a, depth 2) = all 13 clauses; models refine to {x,y}; "
   "x==y proven by two UNSAT calls; probing x/y finds nothing")

print("all chapter-5 examples verified")
