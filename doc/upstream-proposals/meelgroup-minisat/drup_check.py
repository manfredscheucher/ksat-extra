#!/usr/bin/env python3
"""Tiny forward DRUP checker for small instances (used by reproduce.sh, bug 03).

Usage: drup_check.py <cnf> <proof> [bin|ascii]

Reads a DIMACS CNF and a DRUP proof (MiniSat binary format by default: 'a'/'d', variable-length
literals, 0 terminator). Every added clause must be RUP (unit propagation on the current clause
set, with the clause negated, reaches a conflict); deletions remove one copy. The proof must
contain the empty clause. Naive propagation: only meant for tiny instances.
Prints "proof OK" (exit 0) or "proof INVALID: <reason>" (exit 1).
"""
import sys
from collections import Counter


def read_cnf(path):
    clauses, cur = [], []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line[0] in "cp%":
                continue
            for tok in line.split():
                x = int(tok)
                if x == 0:
                    clauses.append(tuple(sorted(cur)))
                    cur = []
                else:
                    cur.append(x)
    return clauses


def read_binary(path):
    data = open(path, "rb").read()
    steps, i = [], 0
    while i < len(data):
        op = chr(data[i])
        i += 1
        if op not in "ad":
            sys.exit("proof INVALID: bad op byte %r at offset %d" % (op, i - 1))
        lits = []
        while True:
            u, shift = 0, 0
            while True:
                if i >= len(data):
                    sys.exit("proof INVALID: truncated proof")
                b = data[i]
                i += 1
                u |= (b & 0x7F) << shift
                shift += 7
                if not b & 0x80:
                    break
            if u == 0:
                break
            lits.append(-(u >> 1) if u & 1 else (u >> 1))
        steps.append((op, tuple(sorted(lits))))
    return steps


def read_ascii(path):
    steps = []
    with open(path) as f:
        for line in f:
            toks = line.split()
            if not toks:
                continue
            op = "d" if toks[0] == "d" else "a"
            if op == "d":
                toks = toks[1:]
            steps.append((op, tuple(sorted(int(t) for t in toks if t != "0"))))
    return steps


def rup(db, clause):
    assign = set(-l for l in clause)
    changed = True
    while changed:
        changed = False
        for c in db:
            if any(l in assign for l in c):
                continue
            free = [l for l in c if -l not in assign]
            if not free:
                return True
            if len(free) == 1:
                assign.add(free[0])
                changed = True
    return False


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    fmt = sys.argv[3] if len(sys.argv) == 4 else "bin"
    db = Counter(read_cnf(sys.argv[1]))
    steps = read_binary(sys.argv[2]) if fmt == "bin" else read_ascii(sys.argv[2])
    for n, (op, c) in enumerate(steps, 1):
        if op == "d":
            if db[c] > 0:
                db[c] -= 1
            continue
        if not rup(list(db.elements()), c):
            print("proof INVALID: step %d (a %s) is not RUP" % (n, " ".join(map(str, c)) or "<empty>"))
            return 1
        if not c:
            print("proof OK (%d steps)" % n)
            return 0
        db[c] += 1
    print("proof INVALID: no empty clause")
    return 1


if __name__ == "__main__":
    sys.exit(main())
