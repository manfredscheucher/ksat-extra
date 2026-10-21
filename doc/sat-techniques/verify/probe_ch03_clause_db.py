#!/usr/bin/env python3
"""Verify the worked examples of sat-techniques/03-clause-database.typ.

Each check mirrors the upstream rule it illustrates (file named in the comment).
Run: python3 scripts/probe/probe_ch03_clause_db.py   (exits non-zero on any mismatch)
"""
import math
import sys

fails = 0


def check(name, got, want):
    global fails
    ok = got == want
    print(f"[{'OK ' if ok else 'BAD'}] {name}: got {got!r}, want {want!r}")
    if not ok:
        fails += 1


def lit_var(lit):
    return lit.lstrip("~")


# ---------------------------------------------------------------- 1. LBD
# Trail: a@1 (dec), b@1 <- C1, c@2 (dec), d@2 <- C2, e@3 (dec), f@3 <- C3, g@4 (dec)
level = dict(a=1, b=1, c=2, d=2, e=3, f=3, g=4)


def lbd(clause):  # Glucose definition: number of distinct decision levels
    return len({level[lit_var(l)] for l in clause})


L1 = ["~b", "~c", "~d", "~f"]
L2 = ["~a", "~c", "~e", "~g"]
check("LBD of L1", lbd(L1), 3)
check("LBD of L2", lbd(L2), 4)

# Learned clause at conflict level 3 with UIP f: (~b or ~d or ~f)
learned = ["~b", "~d", "~f"]
check("LBD of learned", lbd(learned), 3)
# CaDiCaL analyze.cpp: glue = levels.size() - 1 ; kissat deduce.c: only levels < conflict level pushed
check("CaDiCaL/kissat stored glue at learning", lbd(learned) - 1, 2)

# ---------------------------------------------------------------- 2. CaDiCaL 2.1.3 reduce
# reduce.cpp mark_useless_redundant_clauses_as_garbage, opts.reducetarget = 75,
# keep flag = glue <= reducetier1glue (2) at creation / promotion.
# (name, glue, size, used, keep, reason)
cad = [
    ("D1", 2, 3, 0, True, False),
    ("D2", 5, 7, 2, False, False),
    ("D3", 5, 6, 0, False, False),
    ("D4", 9, 11, 1, False, False),
    ("D5", 9, 10, 0, False, True),
    ("D6", 9, 12, 0, False, False),
    ("D7", 7, 8, 0, False, False),
    ("D8", 12, 15, 0, False, False),
    ("D9", 7, 10, 0, False, False),
]


def cadical_reduce(clauses, reducetarget=75):
    stack, new_used, kept_reason = [], {}, []
    for name, glue, size, used, keep, reason in clauses:
        if reason:
            new_used[name] = used
            continue
        new_used[name] = used - 1 if used else 0
        if used:
            continue
        if keep:
            continue
        stack.append((name, glue, size))
    # stable_sort with reduce_less_useful: glue desc, then size desc
    stack.sort(key=lambda t: (-t[1], -t[2]))
    target = min(int(1e-2 * reducetarget * len(stack)), len(stack))
    removed = [t[0] for t in stack[:target]]
    return [t[0] for t in stack], removed, new_used


cands, removed, new_used = cadical_reduce(cad)
check("CaDiCaL candidates (sorted)", cands, ["D8", "D6", "D9", "D7", "D3"])
check("CaDiCaL removed", removed, ["D8", "D6", "D9"])
check("CaDiCaL used after round", (new_used["D2"], new_used["D4"]), (1, 0))

# Second round with no further use: D2 (used now 1) and D4 (used now 0)
cad2 = [(n, g, s, new_used[n], k, r) for (n, g, s, u, k, r) in cad if n not in removed]
cands2, removed2, _ = cadical_reduce(cad2)
check("CaDiCaL round 2 candidates", cands2, ["D4", "D7", "D3"])
check("CaDiCaL round 2 removed (2 of 3)", removed2, ["D4", "D7"])

# new learned clause used value: analyze.cpp res->used = 1 + (glue <= reducetier2glue)
check("new tier2 clause used", 1 + (5 <= 6), 2)
check("new tier3 clause used", 1 + (9 <= 6), 1)

# ---------------------------------------------------------------- 3. kissat dynamic tiers
# tiers.c compute_tier_limits, tier1relative = 500, tier2relative = 900 (per mille)
used_hist = {1: 10, 2: 25, 3: 20, 4: 15, 5: 10, 6: 8, 7: 5, 8: 4, 9: 3}


def kissat_tiers(hist, r1=0.5, r2=0.9, maxg=127):
    u = [hist.get(g, 0) for g in range(maxg + 1)]
    total = sum(u)
    t1 = t2 = -1
    if total:
        lim1 = int(total * r1)  # uint64 = uint64 * double  (truncation)
        lim2 = int(total * r2)
        acc = 0
        g = 0
        while g <= maxg:
            acc += u[g]
            if acc >= lim1:
                t1 = g
                break
            g += 1
        if acc < lim2:
            g = t1 + 1
            while g <= maxg:
                acc += u[g]
                if acc >= lim2:
                    t2 = g
                    break
                g += 1
    if t1 < 0:
        t1, t2 = 2, max(6, 2)
    elif t2 < 0:
        t2 = t1
    return t1, t2


check("kissat total used", sum(used_hist.values()), 100)
check("kissat tier limits", kissat_tiers(used_hist), (3, 7))

# kissat reduce.c collect_reducibles with tier1=3, tier2=7, MAX_USED=31
MAX_USED = 31
kis = [  # (name, glue, size, used, reason)
    ("K1", 2, 4, 31, False),
    ("K2", 3, 5, 0, False),
    ("K3", 6, 9, 31, False),
    ("K4", 6, 8, 29, False),
    ("K5", 9, 14, 31, False),
    ("K6", 12, 20, 0, True),
]


def kissat_candidates(clauses, t1, t2):
    out = []
    for name, glue, size, used, reason in clauses:
        if reason:
            continue
        if glue <= t1 and used:
            continue
        if glue <= t2 and used >= MAX_USED - 1:
            continue
        out.append((name, glue, size))
    out.sort(key=lambda t: (-t[1], -t[2]))  # rank = ~size | ~glue << 32, ascending
    return [t[0] for t in out]


check("kissat candidates", kissat_candidates(kis, 3, 7), ["K5", "K4", "K2"])


def kissat_fraction(reductions, high=900, low=500):
    hi, lo = high * 0.1, low * 0.1
    return (hi - (hi - lo) / math.log10(reductions + 9)) if lo < hi else lo


check("kissat reduce percent at reduction 1", round(kissat_fraction(1), 6), 50.0)
check("kissat reduce percent at reduction 91", round(kissat_fraction(91), 6), 70.0)
check("kissat target with 3 candidates at reduction 1", int(3 * kissat_fraction(1) / 100), 1)

# tier1 clause in kissat survives while used > 0 before decrement: used 31 at last use
u, rounds = 31, 0
while True:
    old = u
    if old:
        u = old - 1
    if not (old > 0):  # glue <= tier1 && used -> keep
        break
    rounds += 1
check("kissat tier1 rounds kept without use", rounds, 31)
u, rounds = 31, 0
while True:
    old = u
    if old:
        u = old - 1
    if not (old >= MAX_USED - 1):
        break
    rounds += 1
check("kissat tier2 rounds kept without use", rounds, 2)

# ---------------------------------------------------------------- 4. MiniSat reduceDB
# Solver.cc reduceDB: sort by reduceDB_lt, remove if size>2 && !locked && (i < n/2 || act < cla_inc/n)
ms = [  # (name, size, activity, locked)
    ("L1", 3, 0.5, False),
    ("L2", 2, 0.1, False),
    ("L3", 5, 4.0, False),
    ("L4", 4, 0.9, False),
    ("L5", 6, 0.97, False),
    ("L6", 3, 7.0, False),
    ("L7", 4, 0.3, True),
    ("L8", 5, 0.95, False),
]
cla_inc = 8.0
extra_lim = cla_inc / len(ms)
check("MiniSat extra_lim", extra_lim, 1.0)
srt = sorted(ms, key=lambda t: (t[1] == 2, t[2]))  # binaries last, then activity ascending
check("MiniSat sort order", [t[0] for t in srt], ["L7", "L1", "L4", "L8", "L5", "L3", "L6", "L2"])
rem, kept = [], []
for i, (n, sz, act, lk) in enumerate(srt):
    if sz > 2 and not lk and (i < len(srt) // 2 or act < extra_lim):
        rem.append(n)
    else:
        kept.append(n)
check("MiniSat removed", rem, ["L1", "L4", "L8", "L5"])
check("MiniSat kept", kept, ["L7", "L3", "L6", "L2"])

# ---------------------------------------------------------------- 5. promotion (CaDiCaL)
# D = (~a or ~b or ~c or ~d) learned with a@1 b@2 c@3, UIP d@4 -> stored glue 4-1 = 3 (tier2)
lv_learn = dict(a=1, b=2, c=3, d=4)
D = ["~a", "~b", "~c", "~d"]
stored = len({lv_learn[lit_var(l)] for l in D}) - 1
check("promotion: stored glue", stored, 3)
# later: a@1, b@1 <- C5, c@2, ~d@2 <- D  ; recompute_glue counts all distinct levels
lv_later = dict(a=1, b=1, c=2, d=2)
rec = len({lv_later[lit_var(l)] for l in D})
check("promotion: recomputed glue", rec, 2)
check("promotion: goes to tier1 (keep)", rec < stored and rec <= 2, True)

# ---------------------------------------------------------------- 6. arena compaction
# illustrative layout: 1 header word + 1 word per literal
arena = [("C1", 3, False), ("C2", 4, True), ("C3", 2, False), ("C4", 5, True), ("C5", 3, False)]
off, before = 0, {}
for n, sz, g in arena:
    before[n] = off
    off += 1 + sz
total_before = off
off, after = 0, {}
for n, sz, g in arena:
    if g:
        continue
    after[n] = off
    off += 1 + sz
check("arena offsets before", before, {"C1": 0, "C2": 4, "C3": 9, "C4": 12, "C5": 18})
check("arena size before", total_before, 22)
check("arena offsets after", after, {"C1": 0, "C3": 4, "C5": 7})
check("arena size after", off, 11)

# ---------------------------------------------------------------- 7. variable compaction
# kissat compact.c / CaDiCaL compact.cpp Mapper: active vars renumbered in order, the first
# fixed var gets a slot, other fixed vars map to it (negated if their value differs).
vars_ = [1, 2, 3, 4, 5, 6, 7, 8]
fixed = {3: True, 6: False}
elim = {5}
new, nxt, first_fixed = {}, 0, None
for v in vars_:
    if v in elim:
        continue
    if v in fixed:
        if first_fixed is None:
            nxt += 1
            first_fixed = (v, nxt)
            new[v] = f"+{nxt}"
        else:
            same = fixed[v] == fixed[first_fixed[0]]
            new[v] = f"{'+' if same else '-'}{first_fixed[1]}"
        continue
    nxt += 1
    new[v] = f"+{nxt}"
check("compact map", new, {1: "+1", 2: "+2", 3: "+3", 4: "+4", 6: "-3", 7: "+5", 8: "+6"})
check("compact new max var", nxt, 6)

# ---------------------------------------------------------------- 8. root-level simplification
root = {"a": True, "b": False}
cls = {
    "C1": ["a", "c", "d"],
    "C2": ["b", "c", "~e"],
    "C3": ["~a", "d", "e", "f"],
    "C4": ["~b", "g"],
    "C5": ["c", "d"],
}


def val(l):
    v = lit_var(l)
    if v not in root:
        return None
    return root[v] if not l.startswith("~") else not root[v]


res = {}
for n, c in cls.items():
    if any(val(l) is True for l in c):
        res[n] = "deleted"
    else:
        res[n] = [l for l in c if val(l) is not False]
check("root simplification", res, {
    "C1": "deleted",
    "C2": ["c", "~e"],
    "C3": ["d", "e", "f"],
    "C4": "deleted",
    "C5": ["c", "d"],
})

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
