"""Brute-force checks for the examples in sat-techniques/06-incremental.typ (throwaway probe)."""
from itertools import product

V = {'a': 1, 'b': 2, 'c': 3, 'd': 4, 'e': 5}


def sat(clauses, n, units=()):
    return [m for m in product([0, 1], repeat=n)
            if all(any((m[abs(l) - 1] == 1) == (l > 0) for l in c) for c in list(clauses) + [[u] for u in units])]


def implied(clauses, n, lit, units=()):
    ms = sat(clauses, n, units)
    return all((m[abs(lit) - 1] == 1) == (lit > 0) for m in ms)


def up(clauses, assign):
    """Unit propagation; assign: dict var->bool. Returns (assign, conflict clause or None, reasons)."""
    assign = dict(assign); reasons = {}
    changed = True
    while changed:
        changed = False
        for c in clauses:
            vals = [assign.get(abs(l)) for l in c]
            if any(v is not None and v == (l > 0) for v, l in zip(vals, c)):
                continue
            free = [l for v, l in zip(vals, c) if v is None]
            if not free:
                return assign, c, reasons
            if len(free) == 1:
                l = free[0]; assign[abs(l)] = l > 0; reasons[l] = c; changed = True
    return assign, None, reasons


print("== 1. IPASIR tie/shirt (a=tie, b=shirt)")
F = [[-1, 2], [1, 2], [-1, -2]]
print("models", sat(F, 2))
print("assume a:", sat(F, 2, [1]), " assume -b:", sat(F, 2, [-2]))

print("== 2. assumptions as decisions: C1=(-a c) C2=(-b -c d) C3=(-d e) assume [a,b]")
F2 = [[-1, 3], [-2, -3, 4], [-4, 5]]
a1, conf, r = up(F2, {1: True}); print("level1", a1, conf, r)
a2, conf, r = up(F2, {**a1, 2: True}); print("level2", a2, conf, r)
print("models under a,b", sat(F2, 5, [1, 2]))
print("assume [a,b,-e] ->", sat(F2, 5, [1, 2, -5]))

print("== 3. failed core: C1=(-a -b c) C2=(-a d c) C3=(-a -d c); assume [a, b, -c]")
F3 = [[-1, -2, 3], [-1, 4, 3], [-1, -4, 3]]
l1, conf, r = up(F3, {1: True}); print("after a:", l1, conf)
l2, conf, r = up(F3, {**l1, 2: True}); print("after b:", l2, conf, r)
print("full assumptions SAT?", bool(sat(F3, 4, [1, 2, -3])))
print("reported core {a,b,-c} UNSAT?", not sat(F3, 4, [1, 2, -3]))
for core in ([1, -3], [2, -3], [1, 2], [-3], [1], [2]):
    print("  subset", core, "UNSAT?" , not sat(F3, 4, core))

print("== 4. add after solve: F=(a b); add (-a)")
print(sat([[1, 2]], 2), sat([[1, 2], [-1]], 2))

print("== 5. enumeration XOR")
X = [[1, 2], [-1, -2]]
print("models", sat(X, 2))
print("after block (-a b):", sat(X + [[-1, 2]], 2), " after both:", sat(X + [[-1, 2], [1, -2]], 2))
print("(a b) over 3 vars:", len(sat([[1, 2]], 3)))

print("== 6. elimination hazard: F=(a b)(-b c); eliminate b -> (a c); add (-b), (-a)")
orig = [[1, 2], [-2, 3]]
print("resolvent formula equisat, models of (a c) over a,c:", sat([[1, 3]], 3))
print("original + (-b)(-a):", sat(orig + [[-2], [-1]], 3))
print("eliminated + (-b)(-a):", sat([[1, 3], [-2], [-1]], 3))

print("== 7. AMO propagator: solver C1=(a b c) C2=(b d) C3=(b -d); hidden AMO(a,b,c)")
amo = [[-1, -2], [-1, -3], [-2, -3]]
direct = [[1, 2, 3], [2, 4], [2, -4]]
print("models of all:", sat(direct + amo, 4))
# step 1: decision a=1 ; propagator returns -b: implied by (-a -b) under a=1
print("-b implied under a by AMO clause (-a -b):", up([[-1, -2]], {1: True})[0])
s, conf, r = up(direct, {1: True, 2: False}); print("solver UP after a,-b:", s, "conflict", conf)
# learned clause: resolve C3=(b -d) with C2=(b d) on d -> (b)
print("(b) implied by direct alone?", implied(direct, 4, 2))
# root: b=1, propagator gives -a (reason -a -b), -c (reason -b -c)
print("-a under b:", up([[-1, -2]], {2: True})[0], " -c under b:", up([[-2, -3]], {2: True})[0])
print("check model [-1,2,-3]: at most one true:", sum(x > 0 for x in [-1, 2, -3]) <= 1)

print("== 8. phases: F=(-a -b), phase(a), phase(b)")
print(sat([[-1, -2]], 2))

print("== 9. fixed listener: (a b)(-b -c)(c d)(-a)")
FL = [[1, 2], [-2, -3], [3, 4], [-1]]
print(sat(FL, 4), up(FL, {})[0])

print("== 10. proof example F=(a b)(a -b)(-a c)(-a -c)")
P = [[1, 2], [1, -2], [-1, 3], [-1, -3]]
print("UNSAT?", not sat(P, 3))
def rup(clauses, lemma):
    _, conf, _ = up(clauses, {abs(l): l < 0 for l in lemma}); return conf is not None
print("(a) RUP:", rup(P, [1]), " empty RUP after (a):", rup(P + [[1]], []))
# LRAT hints: clause 5=(a): under -a, C1 -> b, C2 falsified ; clause 6=(): C5 -> a, C3 -> c, C4 falsified
print("hint chain 5:", up([[1, 2]], {1: False})[0], "C2 falsified by a=0,b=1:", up([[1, -2]], {1: False, 2: True})[1])
print("hint chain 6:", up([[1], [-1, 3]], {})[0], "C4 falsified:", up([[-1, -3]], {1: True, 3: True})[1])
