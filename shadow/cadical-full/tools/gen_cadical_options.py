"""Throwaway generator: CaDiCaL options.hpp OPTIONS table -> Kotlin option property lines.

Prints two sections separated by a line '----': the table entries and the typed properties.
LOGOPT entries are skipped (upstream release builds have no LOGGING), QUTOPT are kept
(QUIET is not defined).
"""
import re, sys

src = open(sys.argv[1]).read()
rows = re.findall(r'^(OPTION|LOGOPT|QUTOPT)\(\s*(\w+),\s*([\w.\-]+),\s*([\w.\-]+),\s*([\w.\-]+),(\d),(\d),(\d),\s*"([^"]*)"\s*\)', src, re.M)

def num(x):
    if x == "reportdefault":
        return "reportdefault"
    v = float(x)
    assert v == int(v), x
    return str(int(v))

table, props = [], []
idx = 0
for kind, n, v, l, h, o, p, r, d in rows:
    if kind == "LOGOPT":
        continue
    table.append(f'    Option("{n}", {num(v)}, {num(l)}, {num(h)}, {o}, {"true" if p == "1" else "false"}, '
                 f'{"true" if r == "1" else "false"}, "{d}"),')
    props.append(f"    var {n}: Int\n        get() = values[{idx}]\n        set(v) {{\n            values[{idx}] = v\n        }}\n")
    idx += 1
print("\n".join(table))
print("----")
print("\n".join(props))
print("----")
print(idx)
