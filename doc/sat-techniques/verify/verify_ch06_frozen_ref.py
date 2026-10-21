"""ch06 frozen section: original (x|a),(~x|b),(~x|c) + (~x),(~a) is UNSAT; reduced (a|b),(a|c) + (~x),(~a) is SAT."""
from itertools import product
def sat(F, n):
    return [m for m in product([False, True], repeat=n)
            if all(any(m[abs(l)-1] == (l > 0) for l in c) for c in F)]
x, a, b, c = 1, 2, 3, 4
orig = [[x, a], [-x, b], [-x, c], [-x], [-a]]
red = [[a, b], [a, c], [-x], [-a]]
print("original models:", sat(orig, 4))
print("reduced models:", sat(red, 4))
assert not sat(orig, 4) and sat(red, 4)
