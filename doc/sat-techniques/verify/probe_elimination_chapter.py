#!/usr/bin/env python3
"""Brute-force checks for every worked example in
ksat-extra/doc/sat-techniques/04-elimination.typ.

Literals are strings: 'a' (positive) or '-a' (negative). Clauses are tuples.
Run: python3 scripts/probe/probe_elimination_chapter.py  (exits 1 on any failure)
"""
import itertools
import sys

FAIL = []


def check(name, cond):
    print(("OK   " if cond else "FAIL ") + name)
    if not cond:
        FAIL.append(name)


def var(l):
    return l.lstrip('-')


def neg(l):
    return l[1:] if l.startswith('-') else '-' + l


def vars_of(*formulas):
    vs = set()
    for f in formulas:
        for c in f:
            for l in c:
                vs.add(var(l))
    return sorted(vs)


def lit_true(l, m):
    return (not m[var(l)]) if l.startswith('-') else m[var(l)]


def sat_clause(c, m):
    return any(lit_true(l, m) for l in c)


def sat(f, m):
    return all(sat_clause(c, m) for c in f)


def assignments(vs):
    for bits in itertools.product([False, True], repeat=len(vs)):
        yield dict(zip(vs, bits))


def models(f, vs):
    return [m for m in assignments(vs) if sat(f, m)]


def equivalent(f, g):
    vs = vars_of(f, g)
    return all(sat(f, m) == sat(g, m) for m in assignments(vs))


def implies(f, c):
    vs = vars_of(f, [c])
    return all(sat_clause(c, m) for m in assignments(vs) if sat(f, m))


def satisfiable(f, extra_vars=()):
    vs = sorted(set(vars_of(f)) | set(extra_vars))
    return any(sat(f, m) for m in assignments(vs))


def resolve(c, d, v):
    assert v in c and neg(v) in d
    r = set(c) - {v} | (set(d) - {neg(v)})
    taut = any(neg(l) in r for l in r)
    return tuple(sorted(r)), taut


def bve(f, v):
    pos = [c for c in f if v in c]
    ng = [c for c in f if neg(v) in c]
    rest = [c for c in f if v not in c and neg(v) not in c]
    res = []
    taut = 0
    for c in pos:
        for d in ng:
            r, t = resolve(c, d, v)
            if t:
                taut += 1
            else:
                res.append(r)
    return pos, ng, rest, res, taut


def projected_models(f, vs):
    out = set()
    allv = vars_of(f)
    for m in assignments(allv):
        if sat(f, m):
            out.add(tuple(m[x] for x in vs))
    return out


def extend(model, stack):
    """Extension stack: list of (witness_literals, clause), pushed in order.
    Processed from the end: if clause falsified, make every witness literal true."""
    m = dict(model)
    for wit, clause in reversed(stack):
        for l in clause:
            m.setdefault(var(l), False)
        for l in wit:
            m.setdefault(var(l), False)
        if not sat_clause(clause, m):
            for l in wit:
                m[var(l)] = not l.startswith('-')
    return m


def extension_ok(orig, reduced, stack, name):
    vo = vars_of(orig)
    vr = sorted(set(vars_of(reduced)))
    ok = True
    n = 0
    # free variables of orig that are neither in reduced nor in the stack get enumerated too
    extra = [v for v in vo if v not in vr and not any(var(l) == v for w, c in stack for l in tuple(c) + tuple(w))]
    for m in assignments(vr + extra):
        if not sat(reduced, m):
            continue
        n += 1
        e = extend(m, stack)
        if not sat(orig, e):
            ok = False
    check(f"{name}: every model of reduced formula ({n}) extends to a model of the original", ok and n > 0)
    check(f"{name}: equisatisfiable", satisfiable(orig) == satisfiable(reduced))


print("== Resolution ==")
r, t = resolve(('a', 'b'), ('-a', 'c'), 'a')
check("(a|b) x (-a|c) on a = (b|c), non-tautological", r == ('b', 'c') and not t)
check("(b|c) implied by {(a|b),(-a|c)}", implies([('a', 'b'), ('-a', 'c')], ('b', 'c')))
r, t = resolve(('a', 'b'), ('-a', '-b'), 'a')
check("(a|b) x (-a|-b) on a is tautological (b|-b)", t)

print("== Subsumption / strengthening ==")
F = [('a', 'b'), ('a', 'b', 'c'), ('-a', 'b', 'c'), ('-b', 'd')]
check("C2=(a|b|c) subsumed: F == F without C2",
      equivalent(F, [('a', 'b'), ('-a', 'b', 'c'), ('-b', 'd')]))
G = [('a', 'b'), ('-a', 'b', 'c'), ('-b', 'd')]
r, _ = resolve(('a', 'b'), ('-a', 'b', 'c'), 'a')
check("self-subsuming resolvent of (a|b),(-a|b|c) is (b|c)", r == ('b', 'c'))
check("strengthening (-a|b|c) -> (b|c): formulas equivalent",
      equivalent(G, [('a', 'b'), ('b', 'c'), ('-b', 'd')]))

print("== BVE: pays ==")
F = [('x', 'a'), ('-x', 'b'), ('-x', 'c')]
pos, ng, rest, res, taut = bve(F, 'x')
check("BVE pays: 1 pos, 2 neg, 2 resolvents (a|b),(a|c)",
      len(pos) == 1 and len(ng) == 2 and sorted(res) == [('a', 'b'), ('a', 'c')])
check("BVE pays: 2 <= 1+2+0 (bound 0)", len(res) <= len(pos) + len(ng))
check("BVE pays: projection onto a,b,c equal",
      projected_models(F, ['a', 'b', 'c']) == projected_models(res, ['a', 'b', 'c']))

print("== BVE: does not pay ==")
F = [('x', 'a'), ('x', 'b'), ('x', 'c'), ('-x', 'd'), ('-x', 'e'), ('-x', 'f')]
pos, ng, rest, res, taut = bve(F, 'x')
check("BVE no-pay: 9 non-tautological resolvents > 6 clauses", len(res) == 9 and taut == 0 and len(pos) + len(ng) == 6)
check("BVE no-pay: projection still equal (elimination would be sound, just bigger)",
      projected_models(F, list('abcdef')) == projected_models(res, list('abcdef')))

print("== fastel ==")
F = [('x', 'a'), ('x', 'b'), ('-x', 'c'), ('-x', 'd'), ('-x', 'e'), ('-x', 'f')]
pos, ng, rest, res, taut = bve(F, 'x')
check("fastel: pos=2, neg=4, product 8 <= fastelim 8, 8 resolvents > 6 clauses",
      len(pos) * len(ng) == 8 and len(res) == 8 and len(pos) + len(ng) == 6)
check("fastel: CaDiCaL bound 0 would reject (8 > 6+0)", len(res) > len(pos) + len(ng))

print("== Gates ==")
AND = [('-x', 'a'), ('-x', 'b'), ('x', '-a', '-b')]
check("AND gate clauses <=> x = a & b",
      all(sat(AND, m) == (m['x'] == (m['a'] and m['b'])) for m in assignments(['a', 'b', 'x'])))
XOR = [('-x', 'a', 'b'), ('-x', '-a', '-b'), ('x', '-a', 'b'), ('x', 'a', '-b')]
check("XOR gate clauses <=> x = a xor b",
      all(sat(XOR, m) == (m['x'] == (m['a'] != m['b'])) for m in assignments(['a', 'b', 'x'])))
ITE = [('-x', '-c', 'a'), ('-x', 'c', 'b'), ('x', '-c', '-a'), ('x', 'c', '-b')]
check("ITE gate clauses <=> x = (c ? a : b)",
      all(sat(ITE, m) == (m['x'] == (m['a'] if m['c'] else m['b'])) for m in assignments(['a', 'b', 'c', 'x'])))
EQ = [('-x', 'a'), ('x', '-a')]
check("equivalence clauses <=> x = a",
      all(sat(EQ, m) == (m['x'] == m['a']) for m in assignments(['a', 'x'])))

# gate example used for BVE
NONGATE = [('x', 'c'), ('x', 'f'), ('-x', 'd'), ('-x', 'e')]
F = AND + NONGATE
pos, ng, rest, res, taut = bve(F, 'x')
check("gate BVE: full resolution 12 pairs, 2 tautological, 10 resolvents > 7 clauses",
      len(pos) * len(ng) == 12 and taut == 2 and len(res) == 10 and len(F) == 7)
gate_pos = [c for c in AND if 'x' in c]
gate_neg = [c for c in AND if '-x' in c]
ng_pos = [c for c in NONGATE if 'x' in c]
ng_neg = [c for c in NONGATE if '-x' in c]
gres = []
for c in gate_pos:
    for d in ng_neg:
        r, t = resolve(c, d, 'x'); assert not t; gres.append(r)
for c in ng_pos:
    for d in gate_neg:
        r, t = resolve(c, d, 'x'); assert not t; gres.append(r)
print("   gate resolvents:", gres)
check("gate BVE: 6 gate x non-gate resolvents <= 7 clauses", len(gres) == 6)
check("gate BVE: projection of F onto a..f equals gate resolvents",
      projected_models(F, list('abcdef')) == projected_models(gres, list('abcdef')))
check("gate BVE: skipped non-gate x non-gate resolvent (c|d) implied by gate resolvents",
      implies(gres, ('c', 'd')))
# kissat definition.c idea: drop x from gate clauses -> UNSAT
check("definition: gate clauses with x removed {(a),(b),(-a|-b)} are UNSAT",
      not satisfiable([('a',), ('b',), ('-a', '-b')]))
check("definition: non-gate clauses with x removed {(c),(f),(d),(e)} are SAT",
      satisfiable([('c',), ('f',), ('d',), ('e',)]))
# equivalence substitution
F = EQ + [('x', 'c'), ('-x', 'd')]
pos, ng, rest, res, taut = bve(F, 'x')
gres = [resolve(('x', '-a'), ('-x', 'd'), 'x')[0], resolve(('x', 'c'), ('-x', 'a'), 'x')[0]]
check("equivalence: gate resolvents = substitution a for x: (a|c),(-a|d)",
      sorted(gres) == [('-a', 'd'), ('a', 'c')])
check("equivalence: projection equal",
      projected_models(F, ['a', 'c', 'd']) == projected_models(gres, ['a', 'c', 'd']))

print("== BCE ==")
F = [('a', '-b'), ('-a', 'b'), ('a', 'c')]
r, t = resolve(('a', '-b'), ('-a', 'b'), 'a')
check("BCE: C1=(a|-b) blocked on a (only resolvent with C2 is tautological)", t)
# also check C1 not blocked on -b: clauses with b: C2 (-a|b) -> resolvent (a|-a) taut, so it is blocked on -b too
reduced = [('-a', 'b'), ('a', 'c')]
m = {'a': False, 'b': True, 'c': True}
check("BCE: a=0,b=1,c=1 is a model of reduced but falsifies C1", sat(reduced, m) and not sat_clause(('a', '-b'), m))
e = extend(m, [(('a',), ('a', '-b'))])
check("BCE: after flipping a -> model of original", e == {'a': True, 'b': True, 'c': True} and sat(F, e))
extension_ok(F, reduced, [(('a',), ('a', '-b'))], "BCE")

print("== Covered clause elimination ==")
C1 = ('a', 'b')
F = [C1, ('-a', 'c', 'd'), ('-a', 'c', '-d'), ('-c', '-b')]
# C1 not blocked on a or b
check("CCE: C1 not blocked on a", not all(resolve(C1, d, 'a')[1] for d in F if '-a' in d))
check("CCE: C1 not blocked on b", not all(resolve(C1, d, 'b')[1] for d in F if '-b' in d))
inter = set(('-a', 'c', 'd')) & set(('-a', 'c', '-d')) - {'-a'}
check("CCE: intersection of resolution candidates on a is {c}", inter == {'c'})
ext = ('a', 'b', 'c')
check("CCE: extended (a|b|c) blocked on c",
      all(resolve(ext, d, 'c')[1] for d in F if '-c' in d))
check("CCE: adding c to C1 is NOT equivalence-preserving (only equisat)",
      not equivalent(F[1:] + [C1], F[1:] + [ext]) and satisfiable(F[1:] + [ext]) == satisfiable(F))
reduced = F[1:]
stack = [(('a',), ('a', 'b')), (('c',), ('a', 'b', 'c'))]
extension_ok(F, reduced, stack, "CCE")
m = {'a': False, 'b': False, 'c': False, 'd': False}
check("CCE: a=b=c=d=0 is a model of reduced", sat(reduced, m))
e = extend(m, stack)
print("   extended:", e)
check("CCE: extension of a=b=c=d=0 gives a=1 (c=1 by first step), model of F", sat(F, e))

print("== Conditioning (globally blocked) ==")
C1 = ('a', 'b')
F = [C1, ('-a', 'c'), ('-b', '-c'), ('b', 'd')]
alpha = {'b': False}
omega = {'a': True, 'c': True}


def lt(l, asg):
    v = var(l)
    if v not in asg:
        return None
    return (not asg[v]) if l.startswith('-') else asg[v]


# alpha subset of negation of C1
check("GBC: alpha = {b=0} is part of the negation of C1",
      all(neg(k if v else '-' + k) in C1 for k, v in alpha.items()))
check("GBC: omega satisfies a literal of C1", any(lt(l, omega) for l in C1))
okgb = True
for d in F[1:]:
    touched = any(var(l) in omega for l in d)
    sat_alpha = any(lt(l, alpha) for l in d)
    sat_omega = any(lt(l, omega) for l in d)
    if touched and not sat_alpha and not sat_omega:
        okgb = False
check("GBC: omega is an autarky of (F \\ C1) restricted by alpha", okgb)
check("GBC: C1 not blocked on a", not all(resolve(C1, d, 'a')[1] for d in F if '-a' in d))
check("GBC: C1 not blocked on b", not all(resolve(C1, d, 'b')[1] for d in F if '-b' in d))
reduced = F[1:]
stack = [(('a', 'c'), C1)]
extension_ok(F, reduced, stack, "GBC")
m = {'a': False, 'b': False, 'c': False, 'd': True}
check("GBC: a=0,b=0,c=0,d=1 model of reduced, falsifies C1", sat(reduced, m) and not sat_clause(C1, m))
e = extend(m, stack)
check("GBC: flipping a,c gives model a=1,b=0,c=1,d=1", e == {'a': True, 'b': False, 'c': True, 'd': True} and sat(F, e))
# flipping only a (classic single-literal witness) would not suffice
e2 = extend(m, [(('a',), C1)])
check("GBC: flipping only a would break (-a|c)", not sat(F, e2))

print("== Instantiation ==")
F = [('a', 'b', 'c'), ('-a', 'd'), ('-a', 'b', '-d')]
check("inst: F implies (b|c)", implies(F, ('b', 'c')))
G = [('b', 'c'), ('-a', 'd'), ('-a', 'b', '-d')]
check("inst: strengthened formula equivalent", equivalent(F, G))
# propagation: a=1,b=0,c=0 -> d=1 from C2 -> C3 falsified
m = {'a': True, 'b': False, 'c': False, 'd': True}
check("inst: a=1,b=0,c=0 forces d=1 and falsifies C3", not sat_clause(('-a', 'b', '-d'), m))
check("inst: afterwards a occurs only negatively (pure -a)", all('a' not in c for c in G))

print("== Factorization (BVA) ==")
F = [(p, q) for p in 'abc' for q in 'def']
G = [(p, 'x') for p in 'abc'] + [('-x', q) for q in 'def']
check("BVA: 9 clauses -> 6", len(F) == 9 and len(G) == 6)
check("BVA: projection of new formula onto a..f equals original models",
      projected_models(G, list('abcdef')) == set(tuple(m[v] for v in 'abcdef') for m in models(F, list('abcdef'))))
pos, ng, rest, res, taut = bve(G, 'x')
check("BVA: eliminating x again gives back the 9 clauses (9 > 6+bound)",
      sorted(res) == sorted(tuple(sorted(c)) for c in F))

print("== Model reconstruction (BVE, MiniSat-style stack) ==")
F = [('x', 'a'), ('-x', 'b'), ('-x', 'c')]
reduced = [('a', 'b'), ('a', 'c')]
# MiniSat: smaller side (pos: 1 clause) stored with x first, then unit -x (default)
stack = [(('x',), ('x', 'a')), (('-x',), ('-x',))]
# extend() processes from the end: unit (-x) first sets x=0, then (x|a) sets x=1 if a=0
m = {'a': False, 'b': True, 'c': True}
e = extend(m, stack)
check("extend: a=0,b=1,c=1 -> x=1 and model of F", e['x'] is True and sat(F, e))
m = {'a': True, 'b': False, 'c': False}
e = extend(m, stack)
check("extend: a=1,b=0,c=0 -> x=0 and model of F", e['x'] is False and sat(F, e))
extension_ok(F, reduced, stack, "BVE extend (MiniSat style)")
# CaDiCaL style: all clauses of both sides
stack2 = [(('x',), ('x', 'a')), (('-x',), ('-x', 'b')), (('-x',), ('-x', 'c'))]
extension_ok(F, reduced, stack2, "BVE extend (CaDiCaL style, all clauses)")

print("== Frozen variables ==")
F = [('x', 'a'), ('-x', 'b'), ('-x', 'c')]
reduced = [('a', 'b'), ('a', 'c')]
check("frozen: original with assumptions x=0,a=0 is UNSAT", not satisfiable(F + [('-x',), ('-a',)]))
check("frozen: reduced with assumptions x=0,a=0 is SAT (spurious)", satisfiable(reduced + [('-x',), ('-a',)], extra_vars=['x']))
m = {'a': False, 'b': True, 'c': True, 'x': False}
e = extend({k: v for k, v in m.items() if k != 'x'}, stack)
check("frozen: reconstruction flips x to 1, violating the assumption x=0", e['x'] is True)

print()
if FAIL:
    print(f"{len(FAIL)} FAILURES")
    sys.exit(1)
print("all checks passed")
