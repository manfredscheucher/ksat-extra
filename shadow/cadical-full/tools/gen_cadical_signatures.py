"""Throwaway generator: member function declarations of 'Internal' / 'External' (CaDiCaL
internal.hpp / external.hpp) -> Kotlin extension function signatures + defining .cpp file.

Usage: gen_cadical_signatures.py <cadical/src>   (prints a Markdown table)
"""
import glob, os, re, sys

src = sys.argv[1]

def struct_body(path, name):
    text = open(path).read()
    start = text.index("struct %s {" % name)
    depth, i = 0, start
    while True:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i]
        i += 1

def strip_comments(t):
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return t

def top_level_statements(body):
    """Statements at brace depth 1 (skipping inline function bodies)."""
    body = body[body.index("{") + 1:]
    out, cur, depth = [], "", 0
    for c in body:
        if c == "{":
            if depth == 0:
                out.append(cur.strip() + " {INLINE}")
                cur = ""
            depth += 1
            continue
        if c == "}":
            depth -= 1
            continue
        if depth > 0:
            continue
        if c == ";":
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
    return out

# Patterns on the type with all white space removed.
TYPES = [
    (r"^signedchar$", "Int"),
    (r"^constFlags&$", "Flags"),
    (r"^conststd::vector<int>::reverse_iterator&$", "Int /* reverse_iterator */"),
    (r"^std::vector<int>::reverse_iterator&$", "IntRef /* reverse_iterator */"),
    (r"^std::vector<int>::reverse_iterator$", "Int /* reverse_iterator */"),
    (r"^(std::)?vector<int>::size_type$", "Int"),
    (r"^(const)?vector<int>::const_iterator&$", "Int /* const_iterator */"),
    (r"^(const)?(std::)?vector<int>&?$", "IntArrayList"),
    (r"^(const)?vector<bool>&$", "BooleanList"),
    (r"^vector<Clause\*>&?$", "ArrayList<Clause>"),
    (r"^(const)?vector<vector<Clause\*>>&$", "ArrayList<ArrayList<Clause>>"),
    (r"^vector<signedchar>&$", "ByteArray"),
    (r"^std::vector<std::tuple<int,Clause\*,bool>>&$", "ArrayList<VivifyLratEntry>"),
    (r"^(const)?vector<uint64_t>&$", "List<Long>"),
    (r"^(const)?Clause\*$", "Clause"),
    (r"^(int|unsigned|unsignedint|size_t)&$", "IntRef"),
    (r"^bool&$", "BoolRef"),
    (r"^int64_t&$", "LongRef"),
    (r"^(const)?(int|unsigned|unsignedint|size_t)$", "Int"),
    (r"^char$", "Char"),
    (r"^(const)?(int64_t|uint64_t|long)$", "Long"),
    (r"^double$", "Double"),
    (r"^bool$", "Boolean"),
    (r"^void$", "Unit"),
    (r"^constchar\*$", "String"),
    (r"^(CaDiCaL::)?CubesWithStatus$", "CubesWithStatus"),
    (r"^(\w+)[*&]?$", None),
]

def ktype(t):
    c = re.sub(r"\s+", "", t)
    for pat, res in TYPES:
        m = re.match(pat, c)
        if m:
            return res if res is not None else m.group(1)
    return "?" + t

def camel(n):
    p = n.split("_")
    return p[0] + "".join(x[:1].upper() + x[1:] for x in p[1:])

def split_params(s):
    out, cur, depth = [], "", 0
    for c in s:
        if c in "<(":
            depth += 1
        if c in ">)":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur)
    return out

TYPE_WORDS = {"int", "unsigned", "bool", "char", "double", "long", "size_t", "int64_t",
              "uint64_t", "signed", "const", "struct", "size_type", "reverse_iterator"}

def parse_param(p, idx, names):
    p = p.strip()
    default = None
    if "=" in p:
        p, default = [x.strip() for x in p.split("=", 1)]
    m = re.match(r"^(.*?[\s*&>])([a-z_]\w*)$", p)
    if m and m.group(2) not in TYPE_WORDS and m.group(1).strip():
        typ, name = m.group(1).strip(), m.group(2)
    else:
        typ, name = p, (names[idx] if idx < len(names) else "p%d" % idx)
    kt = ktype(typ)
    if default is not None:
        if default == "0" and kt == "Boolean":
            default = "false"
        kt += " = " + default
    return "%s: %s" % (camel(name), kt)

def cpp_param_names(cls, name, count):
    """Parameter names of the definition 'cls::name (...)' with 'count' parameters."""
    for f in sorted(glob.glob(os.path.join(src, "*.cpp"))):
        t = strip_comments(open(f).read())
        for m in re.finditer(r"\b%s::%s\s*\(([^)]*)\)" % (cls, name), t):
            if len([q for q in split_params(m.group(1)) if q.strip()]) != count:
                continue
            res = []
            for q in split_params(m.group(1)):
                q = q.split("=")[0].strip()
                q = re.sub(r"\s*([*&])\s*", r" \1 ", q)
                w = re.sub(r"\s+", " ", q).strip().split(" ")
                res.append(w[-1] if len(w) > 1 and re.match(r"^[a-z_]\w*$", w[-1]) and w[-1] not in TYPE_WORDS else "")
            return res
    return []

def defining_file(cls, name):
    hits = []
    for f in sorted(glob.glob(os.path.join(src, "*.cpp"))):
        t = open(f).read()
        if re.search(r"\b%s::%s\s*\(" % (cls, name), t):
            hits.append(os.path.basename(f))
    return ", ".join(hits) if hits else "(header / not defined)"

def table(cls, path):
    body = strip_comments(struct_body(path, cls))
    rows = []
    for st in top_level_statements(body):
        inline = st.endswith("{INLINE}")
        st = st.replace("{INLINE}", "").strip()
        st = re.sub(r"\s+", " ", st)
        st = re.sub(r"\bCADICAL_ATTRIBUTE_FORMAT \(.*\)$", "", st).strip()
        m = re.match(r"^(static |inline |virtual )*([\w:<>,* &]+?)\s*\b(\w+) \((.*)\)( const)?$", st)
        if not m or "(" not in st:
            continue
        ret, name, params = m.group(2).strip(), m.group(3), m.group(4)
        if name in (cls,) or ret.startswith("~"):
            continue
        names = cpp_param_names(cls, name, len([q for q in split_params(params) if q.strip() and q.strip() != "void"]))
        ps = [parse_param(p, i, names) for i, p in enumerate(split_params(params)) if p.strip() and p.strip() != "void"]
        kret = ktype(ret)
        where = "InternalHpp.kt / ExternalHpp.kt (inline)" if inline else defining_file(cls, name)
        rows.append((where, "%s %s (%s)" % (ret, name, params), "%s.%s(%s): %s" % (cls, camel(name), ", ".join(ps), kret)))
    return rows

NULLABLE_PARAMS = {("searchAssign", "reason"), ("assignmentLevel", "reason"),
                   ("vivifyAssign", "reason"), ("handleExternalClause", "res")}
NULLABLE_RETURNS = {"newDrivingClause", "onTheFlyStrengthen", "blockImpossible",
                    "findBinaryClause", "findTernaryClause", "findClause"}
LATER = ("proof.cpp",)
OUT = ("message.cpp", "report.cpp", "profile.cpp", "resources.cpp", "stats.cpp")

def fix(kt):
    m = re.match(r"^(\w+)\.(\w+)\((.*)\): (.*)$", kt, re.S)
    if not m:
        return kt
    cls, name, params, ret = m.groups()
    for fn, pn in NULLABLE_PARAMS:
        if fn == name:
            params = params.replace("%s: Clause" % pn, "%s: Clause?" % pn)
    if name in NULLABLE_RETURNS and ret == "Clause":
        ret = "Clause?"
    return "%s.%s(%s): %s" % (cls, name, params, ret)

main, later, out, undefined = [], [], [], []
for cls, hdr in (("Internal", "internal.hpp"), ("External", "external.hpp")):
    for where, up, kt in table(cls, os.path.join(src, hdr)):
        if where.startswith("InternalHpp.kt"):
            continue
        if where.startswith("(header"):
            undefined.append((where, up, kt))
            continue
        if "message.cpp, phases.cpp" == where:
            where = "phases.cpp" if re.match(r".*\.phase\(lit: Int\)", kt) else "message.cpp"
        if where in OUT:
            out.append((where, up, kt))
        elif where in LATER:
            later.append((where, up, fix(kt)))
        else:
            if kt.startswith("Internal.isValidLimit"):
                kt = "isValidLimit(name: String): Boolean  (static: top-level function)"
            main.append((where, up, fix(kt)))

def emit(rows):
    print("| upstream file | upstream declaration | Kotlin extension function |")
    print("|---|---|---|")
    for where, up, kt in sorted(rows, key=lambda r: r[0]):
        print("| %s | `%s` | `%s` |" % (where, up.replace("|", "\\|"), kt))

print("## Solver functions\n")
emit(main)
print("\n## Proof functions (later wave)\n")
emit(later)
print("\n## Not ported (messages, reports, profiling, resources)\n")
emit(out)
print("\n## Declared without upstream definition or defined in the headers\n")
emit(undefined)
