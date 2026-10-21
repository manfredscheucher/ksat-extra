#!/usr/bin/env python3
"""Throwaway reviewer probe: brute-force check of worked examples in sat-techniques ch4-6."""
import itertools

def parse(s):
    # "a -b c" -> list of (var, sign)
    return [tuple(c.split()) for c in s]

def lits(cl):
    out = []
    for t in cl.split():
        out.append((t.lstrip('-'), not t.startswith('-')))
    return out

def F(*cls):
    return [lits(c) for c in cls]

def vars_of(*fs):
    vs = set()
    for f in fs:
        for c in f:
            for v, _ in c:
                vs.add(v)
    return sorted(vs)

def sat(c, m):
    return any(m[v] == s for v, s in c)

def models(f, vs=None):
    vs = vs or vars_of(f)
    for bits in itertools.product([0, 1], repeat=len(vs)):
        m = dict(zip(vs, map(bool, bits)))
        if all(sat(c, m) for c in f):
            yield m

def proj(ms, vs):
    return {tuple(m[v] for v in vs) for m in ms}

def equiv(f, g):
    vs = vars_of(f, g)
    return proj(models(f, vs), vs) == proj(models(g, vs), vs)

def implied(f, c):
    vs = vars_of(f, [c])
    return all(sat(c, m) for m in models(f, vs))

def is_sat(f):
    return next(models(f), None) is not None

def check(name, cond):
    print(("OK   " if cond else "FAIL ") + name)

def extend(m, stack):
    m = dict(m)
    for clause, witness in reversed(stack):
        if not all(v in m for v, _ in clause):
            for v, _ in clause:
                m.setdefault(v, False)
        if not sat(clause, m):
            for v, s in witness:
                m[v] = s
    return m

def recon_ok(orig, reduced, stack):
    vs_o = vars_of(orig)
    vs_r = vars_of(reduced)
    allv = sorted(set(vs_o) | set(vs_r))
    for m in models(reduced, allv):
        e = extend(m, stack)
        if not all(sat(c, e) for c in orig):
            return False, m
    return True, None

# ---- ch4 ----
o = F("a b", "a b c", "-a b c", "-b d")
check("ch4 subsumption result equivalent", equiv(o, F("a b", "b c", "-b d")))

# BVE pays off: count non-tautological resolvents
def resolvents(f, x):
    pos = [c for c in f if (x, True) in c]
    neg = [c for c in f if (x, False) in c]
    out = []
    for p in pos:
        for n in neg:
            r = set(l for l in p if l[0] != x) | set(l for l in n if l[0] != x)
            if any((v, not s) in r for v, s in r):
                continue
            out.append(r)
    return pos, neg, out

f = F("x a", "-x b", "-x c")
p, n, r = resolvents(f, "x")
check("ch4 BVE pays off 2 res", len(r) == 2)
f = F("x a", "x b", "x c", "-x d", "-x e", "-x f")
check("ch4 BVE no pay 9 res", len(resolvents(f, "x")[2]) == 9)
f = F("x a", "x b", "-x c", "-x d", "-x e", "-x f")
check("ch4 fastel 8 res", len(resolvents(f, "x")[2]) == 8)
gate = F("-x a", "-x b", "x -a -b", "x c", "x f", "-x d", "-x e")
check("ch4 gate plain 10", len(resolvents(gate, "x")[2]) == 10)
six = F("-a -b d", "-a -b e", "a c", "b c", "a f", "b f")
check("ch4 gate-aware equisat (projection equal)", proj(models(gate, vars_of(gate)), list("abcdef")) == proj(models(six, list("abcdef")), list("abcdef")))
check("ch4 (c d) implied by six", implied(six, lits("c d")[0:2] and lits("c d")))
# gate truth tables
for name, cls, fn in [
    ("XOR", F("-x a b", "-x -a -b", "x -a b", "x a -b"), lambda a, b, c: a != b),
    ("ITE", F("-x -c a", "-x c b", "x -c -a", "x c -b"), lambda a, b, c: a if c else b),
    ("AND", F("-x a", "-x b", "x -a -b"), lambda a, b, c: a and b),
]:
    ok = True
    for a, b, c in itertools.product([False, True], repeat=3):
        for x in [False, True]:
            m = dict(a=a, b=b, c=c, x=x)
            ok &= (all(sat(cl, m) for cl in cls) == (x == bool(fn(a, b, c))))
    check("ch4 gate table " + name, ok)

# BCE
o = F("a -b", "-a b", "a c")
red = F("-a b", "a c")
check("ch4 BCE recon", recon_ok(o, red, [(lits("a -b"), lits("a"))])[0])
# CCE
o = F("a b", "-a c d", "-a c -d", "-c -b")
red = F("-a c d", "-a c -d", "-c -b")
st = [(lits("a b"), lits("a")), (lits("a b c"), lits("c"))]
check("ch4 CCE recon", recon_ok(o, red, st)[0])
check("ch4 CCE equisat", is_sat(o) == is_sat(red))
# conditioning
o = F("a b", "-a c", "-b -c", "b d")
red = F("-a c", "-b -c", "b d")
check("ch4 condition recon", recon_ok(o, red, [(lits("a b"), lits("a c"))])[0])
# instantiation
o = F("a b c", "-a d", "-a b -d")
check("ch4 instantiation equivalent", equiv(o, F("b c", "-a d", "-a b -d")))
# factorization
nine = F(*[f"{l} {k}" for l in "abc" for k in "def"])
six = F("a x", "b x", "c x", "-x d", "-x e", "-x f")
check("ch4 factor projection", proj(models(nine), list("abcdef")) == proj(models(six), list("abcdef")))
# BVE extension MiniSat-style
o = F("x a", "-x b", "-x c")
red = F("a b", "a c")
check("ch4 BVE ext", recon_ok(o, red, [(lits("x a"), lits("x")), (lits("-x"), lits("-x"))])[0])
# frozen example
check("ch4 frozen orig+assump unsat", not is_sat(F("x a", "-x b", "-x c", "-x", "-a")))
check("ch4 frozen reduced+assump sat", is_sat(F("a b", "a c", "-x", "-a")))

# ---- ch5 ----
f = F("-a b", "-a c", "-b -c d", "-b -d", "a e f")
check("ch5 failed literal: -a implied", implied(f, lits("-a")))
check("ch5 -a: a=0 sat", is_sat(f + F("-a")))
f = F("-a b", "-a c", "-b -c d", "a -d e")
check("ch5 HBR implied", implied(f, lits("-a d")))
others = F("a e", "-e -c", "b -e f", "b -e -f")
check("ch5 vivify (a b) implied by others", implied(others, lits("a b")))
o = F("-a b", "-b c", "-c a", "b d e", "-c -d", "b -c e")
red = F("a d e", "-a -d")
ok = True
for m in models(red, list("ade")):
    m = dict(m); m["b"] = m["a"]; m["c"] = m["a"]
    ok &= all(sat(c, m) for c in o)
check("ch5 SCC recon", ok and len(list(models(o))) == len(list(models(red, list("ade")))))
check("ch5 transred", implied(F("-a b", "-b c"), lits("-a c")))
xc = F("a b -c", "-a -b -c", "-a b c", "a -b c")
xd = F("a b -d", "-a -b -d", "-a b d", "a -b d")
check("ch5 XOR c table", all((m["c"] == (m["a"] != m["b"])) for m in models(xc)) and len(list(models(xc))) == 4)
check("ch5 ternary R1", implied(xc + xd, lits("b -c d")))
check("ch5 ternary (-c d) and (c -d)", implied(xc + xd, lits("-c d")) and implied(xc + xd, lits("c -d")))
f = F("-a b", "-a c", "-b -c", "a d", "-d e f", "-e -f")
ms = list(models(f))
bb = [(v, s) for v in "abcdef" for s in (True, False) if all(m[v] == s for m in ms)]
check("ch5 backbone {-a,d}: " + str(bb), sorted(bb) == sorted([("a", False), ("d", True)]))
bin_ = F("-a b", "-a c", "-b -c", "a d", "-e -f")
ms2 = list(models(bin_, list("abcdef")))
bb2 = [(v, s) for v in "abcdef" for s in (True, False) if all(m[v] == s for m in ms2)]
check("ch5 binary-part backbone same", sorted(bb2) == sorted(bb))
# congruence
cg = F("-g a", "-g b", "g -a -b", "-h a", "-h b", "h -a -b",
       "-p g", "-p c", "p -g -c", "-q h", "-q c", "q -h -c")
check("ch5 congruence g=h p=q", all(m["g"] == m["h"] and m["p"] == m["q"] for m in models(cg)))
# sweeping
sw = F("-x a b", "-x -a -b", "x -a b", "x a -b",
       "-u a", "-u -b", "u -a b",
       "-v -a", "-v b", "v a -b",
       "-y u v", "-u y", "-v y")
check("ch5 sweep 13 clauses", len(sw) == 13)
check("ch5 sweep x=y", all(m["x"] == m["y"] for m in models(sw)))
check("ch5 sweep x,-y unsat", not is_sat(sw + F("x", "-y")) and not is_sat(sw + F("-x", "y")))
rows = [dict(zip("abxuvy", map(bool, r))) for r in
        [(1, 0, 1, 1, 0, 1), (0, 0, 0, 0, 0, 0), (0, 1, 1, 0, 1, 1), (1, 1, 0, 0, 0, 0)]]
check("ch5 sweep rows are models", all(all(sat(c, r) for c in sw) for r in rows))
cls = [[("a", True), ("b", False), ("x", True), ("u", True), ("v", False), ("y", True)]]
def val(l, r): return r[l[0]] == l[1]
for i, r in enumerate(rows[1:], 2):
    new = []
    for k in cls:
        t = [l for l in k if val(l, r)]; fl = [l for l in k if not val(l, r)]
        new += [g for g in (t, fl) if len(g) > 1]
    cls = new
    print(f"     after model {i}: classes {cls}")

# ---- ch6 ----
f = F("-a b", "a b", "-a -b")
check("ch6 tie shirt only model", [tuple(m.values()) for m in models(f, list("ab"))] == [(False, True)])
f = F("-a c", "-b -c d", "-d e")
check("ch6 assumptions a,b -> all true", [m for m in models(f + F("a", "b"))] and all(all(m.values()) for m in models(f + F("a", "b"))))
f = F("-a -b c", "-a d c", "-a -d c")
check("ch6 core a,b,-c unsat", not is_sat(f + F("a", "b", "-c")))
check("ch6 b,-c sat", is_sat(f + F("b", "-c")))
check("ch6 a,-c unsat", not is_sat(f + F("a", "-c")))
check("ch6 enum (a or b) numVars=3 -> 6", len(list(models(F("a b"), list("abc")))) == 6)
f = F("a b", "-b c")
check("ch6 frozen orig unsat", not is_sat(f + F("-b", "-a")))
check("ch6 frozen reduced sat", is_sat(F("a c", "-b", "-a")))
f = F("a b c", "b d", "b -d", "-a -b", "-a -c", "-b -c")
ms = list(models(f, list("abcd")))
check("ch6 AMO models: a0 b1 c0 d free", len(ms) == 2 and all(not m["a"] and m["b"] and not m["c"] for m in ms))
f = F("a b", "a -b", "-a c", "-a -c")
check("ch6 DRAT unsat, (a) implied", not is_sat(f) and implied(f, lits("a")))
