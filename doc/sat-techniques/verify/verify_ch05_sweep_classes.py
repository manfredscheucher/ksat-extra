"""Brute-force check of the ch05 SAT-sweeping example (models table + class evolution)."""
from itertools import product

V = "a b x u v y".split()
def lit(n, s): return (n, s)  # s=True positive
def cl(*ls): return [(l.lstrip('-'), not l.startswith('-')) for l in ls]
F = [cl('a','b','-x'), cl('-a','-b','-x'), cl('-a','b','x'), cl('a','-b','x'),       # x = XOR(a,b)
     cl('-u','a'), cl('-u','-b'), cl('u','-a','b'),                               # u = AND(a,-b)
     cl('-v','-a'), cl('-v','b'), cl('v','a','-b'),                                # v = AND(-a,b)
     cl('y','-u'), cl('y','-v'), cl('-y','u','v')]                                 # y = OR(u,v)
assert len(F) == 13
def sat(m, F=F): return all(any(m[n] == s for n, s in c) for c in F)
models = [dict(zip(V, bits)) for bits in product([0, 1], repeat=6) if sat(dict(zip(V, bits)))]
table = [dict(zip(V, r)) for r in [(1,0,1,1,0,1),(0,0,0,0,0,0),(0,1,1,0,1,1),(1,1,0,0,0,0)]]
for t in table: assert sat(t), t
print("all models:", len(models))
# x == y in every model
assert all(m['x'] == m['y'] for m in models)
# class evolution
val = lambda m, L: m[L[0]] if L[1] else 1 - m[L[0]]
name = lambda L: L[0] if L[1] else '~' + L[0]
classes = [[(n, bool(table[0][n])) for n in V]]
print("after model 1:", [[name(L) for L in c] for c in classes])
for i, m in enumerate(table[1:], start=2):
    new = []
    for c in classes:
        for b in (0, 1):
            part = [L for L in c if val(m, L) == b]
            if len(part) >= 2: new.append(part)
    classes = new
    print(f"after model {i}:", [[name(L) for L in c] for c in classes])
backbone = [n for n in V if len({m[n] for m in table}) == 1]
print("literals constant over table:", backbone)
