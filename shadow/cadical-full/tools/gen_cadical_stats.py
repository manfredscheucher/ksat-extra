"""Throwaway generator: CaDiCaL stats.hpp -> Kotlin StatsHpp.kt body (nested structs as classes)."""
import re, sys

src = open(sys.argv[1]).read()
body = src[src.index("struct Stats {") + len("struct Stats {"):src.index("Stats ();")]
# remove comments but keep trailing comment text
lines = body.split("\n")

out = []
counter = [0]
stack = []  # list of (fields list)
cur = []
# Tokenize: join continuation lines like 'int64_t\n  name; // ...'
text = []
pending = ""
for ln in lines:
    s = ln.strip()
    if not s:
        continue
    if s.startswith("//"):
        continue
    if pending:
        s = pending + " " + s
        pending = ""
    if s in ("int64_t",):
        pending = s
        continue
    text.append(s)

def emit_fields(items, indent):
    res = []
    for it in items:
        res.append(indent + it)
    return res

# parse recursively
pos = [0]
def parse_block():
    items = []
    while pos[0] < len(text):
        s = text[pos[0]]
        pos[0] += 1
        if s.startswith("struct {"):
            inner = parse_block()
            # closing line is like '} name;' or '} a, b;'
            close = text[pos[0] - 1]
            m = re.match(r"\}\s*([\w ,]+);", close)
            names = [n.strip() for n in m.group(1).split(",")]
            items.append(("struct", inner, names))
        elif s.startswith("}"):
            return items
        elif s.startswith("Internal *internal"):
            continue
        else:
            m = re.match(r"(int64_t|double)\s+([\w ,]+);\s*(//\s*(.*))?", s)
            if not m:
                raise SystemExit("cannot parse: " + s)
            typ, names, _, comment = m.groups()
            for n in names.split(","):
                items.append(("field", typ, n.strip(), comment))
    return items

items = parse_block()
classes = []
def render(items, indent, prefix):
    res = []
    for it in items:
        if it[0] == "field":
            _, typ, name, comment = it
            init = "0L" if typ == "int64_t" else "0.0"
            c = f" // {comment}" if comment else ""
            res.append(f"{indent}var {camel(name)} = {init}{c}")
        else:
            _, inner, names = it
            cname = "".join(x.capitalize() for x in names[0].split("_"))
            cname = prefix + cname
            res.append(f"{indent}class {cname} {{")
            res.extend(render(inner, indent + "    ", cname))
            res.append(f"{indent}}}")
            for n in names:
                res.append(f"{indent}val {camel(n)} = {cname}()")
    return res

def camel(n):
    parts = n.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])

print("\n".join(render(items, "    ", "")))
