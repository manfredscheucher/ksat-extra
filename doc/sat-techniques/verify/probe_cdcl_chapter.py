#!/usr/bin/env python3
"""Probe: verifies every worked example of sat-techniques/01-cdcl.typ by brute force."""
import itertools

V = "abcdefghijk"
def L(s):  # "-a" -> ('a', False), "a" -> ('a', True)
    return (s[1], False) if s[0] == '-' else (s, True)
def show(l): return ("~" if not l[1] else "") + l[0]
def neg(l): return (l[0], not l[1])

F = {
 "C1": "-a b", "C2": "-c d", "C3": "-c e", "C4": "-f g", "C5": "-h i",
 "C6": "-i j", "C7": "-i -a -d k", "C8": "-j -k -b -e",
}
F = {n: [L(x) for x in s.split()] for n, s in F.items()}
names = list(F)

def entails(clauses, cl, vars_=V):
    """True iff every model of clauses satisfies cl (brute force)."""
    for bits in itertools.product([0, 1], repeat=len(vars_)):
        m = dict(zip(vars_, bits))
        if all(any(m[v] == s for v, s in c) for c in clauses):
            if not any(m[v] == s for v, s in cl):
                return False
    return True

def models(clauses, vars_=V):
    out = []
    for bits in itertools.product([0, 1], repeat=len(vars_)):
        m = dict(zip(vars_, bits))
        if all(any(m[v] == s for v, s in c) for c in clauses):
            out.append(m)
    return out

class S:
    def __init__(s, cls):
        s.cls = dict(cls); s.val = {}; s.lvl = {}; s.rsn = {}; s.trail = []; s.level = 0; s.q = []; s.lim = []
    def value(s, l):
        if l[0] not in s.val: return None
        return s.val[l[0]] == l[1]
    def assign(s, l, r, lev=None):
        s.val[l[0]] = l[1]; s.lvl[l[0]] = s.level if lev is None else lev; s.rsn[l[0]] = r
        s.trail.append(l); s.q.append(l)
    def propagate(s):
        while s.q:
            p = s.q.pop(0)
            for n in s.cls:  # clauses containing ~p, in clause order
                c = s.cls[n]
                if neg(p) not in c: continue
                vals = [s.value(x) for x in c]
                if True in vals: continue
                un = [x for x, v in zip(c, vals) if v is None]
                if not un: s.q.clear(); return n
                if len(un) == 1: s.assign(un[0], n)
        return None
    def decide(s, l):
        s.level += 1; s.lim.append(len(s.trail)); s.assign(l, None)
    def backtrack(s, lev):
        keep = s.lim[lev] if lev < len(s.lim) else len(s.trail)
        for l in s.trail[keep:]:
            del s.val[l[0]]; del s.lvl[l[0]]; del s.rsn[l[0]]
        s.trail = s.trail[:keep]; s.lim = s.lim[:lev]; s.level = lev; s.q = []
    def tr(s):
        return " ".join(show(l) + "@" + str(s.lvl[l[0]]) + ("<-" + s.rsn[l[0]] if s.rsn[l[0]] else "") for l in s.trail)
    def next_decision(s):
        for v in V:
            if v not in s.val: return (v, True)
        return None

print("== Running example: SAT?", len(models(F.values())) > 0)
# sanity: no unit clauses at level 0
s = S(F)
assert s.propagate() is None and not s.trail
confl = None
while confl is None:
    d = s.next_decision(); s.decide(d); confl = s.propagate()
    print("after deciding", show(d), "level", s.level, ":", s.tr())
print("conflict clause:", confl, [show(l) for l in F[confl]])
print("conflict clause all false:", all(s.value(l) is False for l in F[confl]))

# implication graph edges
print("implication graph edges:")
for l in s.trail:
    r = s.rsn[l[0]]
    if r: print("  ", [show(neg(x)) for x in F[r] if x != l], "--", r, "-->", show(l))
print("   conflict", confl, "<-", [show(neg(x)) for x in F[confl]])

# 1-UIP analysis, step by step
cl = set(F[confl]); steps = []
cur = lambda c: [x for x in c if s.lvl[x[0]] == s.level]
pos = {l[0]: i for i, l in enumerate(s.trail)}
while len(cur(cl)) > 1:
    p = max(cur(cl), key=lambda x: pos[x[0]])  # last assigned current-level literal
    r = s.rsn[p[0]]
    new = (cl - {p}) | (set(F[r]) - {neg(p)})
    # OTFS condition (CaDiCaL/kissat): resolvent smaller than antecedent (non-root lits)
    otfs = len(F[r]) > 2 and len(new) < len(F[r])
    steps.append((show(neg(p)), r, sorted(show(x) for x in new), otfs))
    cl = new
for st in steps: print("resolve on", st[0][1:] if st[0][0]=='~' else st[0], "with", st[1], "->", st[2], "OTFS fires:", st[3])
uip = cur(cl)[0]
print("1-UIP literal (true on trail):", show(neg(uip)), " learned:", sorted(show(x) for x in cl))
learned = sorted(cl, key=lambda x: -s.lvl[x[0]])
print("levels:", {show(x): s.lvl[x[0]] for x in learned})
print("learned implied by F:", entails(F.values(), learned))
# each intermediate resolvent implied
for st in steps: assert entails(F.values(), [L(x.replace('~','-')) for x in st[2]])

# recursive minimization (MiniSat litRedundant semantics)
def redundant(lit, inclause, memo=None):
    v = lit[0]; r = s.rsn[v]
    if r is None: return False
    for q in F[r]:
        if q[0] == v or s.lvl[q[0]] == 0: continue
        if q in inclause: continue
        if not redundant(q, inclause): return False
    return True
mini = [x for x in learned if x == uip or not redundant(x, set(learned))]
print("minimized:", [show(x) for x in mini], " removed:", [show(x) for x in learned if x not in mini])
print("minimized implied by F:", entails(F.values(), mini))
for x in learned:
    if x != uip: print("   ", show(x), "reason", s.rsn[x[0]], "redundant:", redundant(x, set(learned)))

# shrinking: per level block (excluding conflict level), find block UIP by resolving within the level
def shrink(clause):
    out = [uip]
    for lev in sorted({s.lvl[x[0]] for x in clause if x != uip}, reverse=True):
        blk = [x for x in clause if s.lvl[x[0]] == lev]
        if len(blk) < 2: out += blk; continue
        open_ = set(blk); ok = True
        while len(open_) > 1:
            p = max(open_, key=lambda x: pos[x[0]]); r = s.rsn[p[0]]
            open_.remove(p)
            for q in F[r]:
                if q == neg(p): continue
                if s.lvl[q[0]] == lev: open_.add(q)
                elif q in clause or redundant(q, set(clause)): pass
                else: ok = False
        out += (list(open_) if ok else blk)
    return out
sh = shrink(mini)
print("shrunken:", [show(x) for x in sh], " implied by F:", entails(F.values(), sh))
sh2 = shrink(learned)
print("shrink applied to unminimized clause:", [show(x) for x in sh2])

# backjump level
bj = max(s.lvl[x[0]] for x in mini if x != uip)
print("backjump level:", bj, "(from", s.level, ")")
undone = [show(l) for l in s.trail if s.lvl[l[0]] > bj]
print("undone:", undone)
s.cls["L"] = mini
s.backtrack(bj)
print("trail after backjump:", s.tr())
print("learned clause literal values:", [(show(x), s.value(x)) for x in mini])
s.assign(uip, "L"); c2 = s.propagate()
print("after asserting:", s.tr(), "conflict:", c2)
while True:
    d = s.next_decision()
    if d is None: break
    s.decide(d); c2 = s.propagate(); print("decide", show(d), "->", s.tr(), "conflict:", c2)
    assert c2 is None
m = {v: int(s.val[v]) for v in V}
print("final model:", m, "satisfies F:", all(any(m[v] == sg for v, sg in c) for c in F.values()))

# chronological backtracking: go to level current-1 = 3 instead of 2
s3 = S(F)
for v in "acfh": s3.decide((v, True)); s3.propagate()
s3.cls["L"] = mini
s3.backtrack(3)
lev_uip = max(s3.lvl[x[0]] for x in mini if x != uip)
s3.assign(uip, "L", lev=lev_uip); c3 = s3.propagate_chrono = None
# propagate with assignment level = max level of reason's other lits (CaDiCaL chrono rule)
while s3.q:
    p = s3.q.pop(0)
    for n, c in s3.cls.items():
        if neg(p) not in c: continue
        vals = [s3.value(x) for x in c]
        if True in vals: continue
        un = [x for x, v in zip(c, vals) if v is None]
        if len(un) == 1:
            lv = max(s3.lvl[x[0]] for x in c if x != un[0]); s3.assign(un[0], n, lev=lv)
print("chrono: trail after backtrack to 3 + asserting:", s3.tr())

# 2WL simulation of C7 MiniSat-style, watches on first two literals as written
print("== Two watched literals on C7")
c = list(F["C7"]); w = {0: c[0], 1: c[1]}
blk = {c[0]: c[1], c[1]: c[0]}  # watcher(lit) -> blocker
asg = {}
def val(l): return None if l[0] not in asg else asg[l[0]] == l[1]
def assign_and_visit(l):
    asg[l[0]] = l[1]
    false_lit = neg(l)
    if false_lit not in (c[0], c[1]): print("  ", show(l), "true: C7 not visited, watches", show(c[0]), show(c[1])); return
    b = blk[false_lit]
    if val(b) is True: print("   blocker true, skip"); return
    if c[0] == false_lit: c[0], c[1] = c[1], c[0]
    first = c[0]
    if val(first) is True: blk[false_lit] = first; print("   first true"); return
    for k in range(2, len(c)):
        if val(c[k]) is not False:
            c[1], c[k] = c[k], c[1]; del blk[false_lit]; blk[c[1]] = first
            print("  ", show(l), "true: watch moves", show(false_lit), "->", show(c[1]), "; clause now", [show(x) for x in c]); return
    blk[false_lit] = first
    print("  ", show(l), "true: no replacement; first", show(first), "value", val(first), "-> unit, blocker of", show(false_lit), "now", show(first))
for v in ["a", "b", "c", "d", "e", "f", "g", "h", "i"]:
    assign_and_visit((v, True))

# OTFS toy
print("== OTFS toy")
T = {"D1": "-b c", "D2": "-a -c d", "D3": "-c -d"}
T = {n: [L(x) for x in s_.split()] for n, s_ in T.items()}
t = S(T)
for v in "ab":
    t.decide((v, True)); cc = t.propagate(); print("decide", v, t.tr(), "conflict", cc)
cl = set(T[cc]); p = ("d", True)
res = (cl - {neg(p)}) | (set(T["D2"]) - {p})
print("resolvent of", cc, "and D2 on d:", sorted(show(x) for x in res), "size", len(res), "< |D2| =", len(T["D2"]))
print("strengthened D2 = D2 minus d:", sorted(show(x) for x in T["D2"] if x != p),
      "equals resolvent:", res == set(x for x in T["D2"] if x != p))
print("strengthened implied by D1..D3:", entails(T.values(), [x for x in T["D2"] if x != p], "abcd"))
print("current-level lits in strengthened:", [show(x) for x in res if t.lvl[x[0]] == t.level])
print("toy SAT models:", models(T.values(), "abcd")[:3])

# extras referenced in the text
print("== extras")
print("decision clause (~a v ~c v ~h) implied:", entails(F.values(), [L("-a"), L("-c"), L("-h")]))
print("L2 = resolvent of L1 and C1 on b:",
      sorted(show(x) for x in (set(learned) - {L("-b")}) | (set(F["C1"]) - {L("b")})))
print("F without C8 has", len(models([c for n, c in F.items() if n != "C8"])), "models; F has", len(models(F.values())))
