import re, os, sys, collections
d = sys.argv[1]
sig = open(os.path.join(d, 'SIGNATURES.md')).read()
sec = sig.split('## Solver functions', 1)[1].split('\n## ', 1)[0]
rows = collections.OrderedDict()
for line in sec.splitlines():
    m = re.match(r'\| (\S+)\.cpp \| `.*?` \| `(.*)` \|$', line)
    if not m: continue
    rows.setdefault(m.group(1), []).append(m.group(2))
def ktname(f): return ''.join(p.capitalize() for p in f.split('_')) + '.kt'
made, skipped = [], []
for f, sigs in rows.items():
    path = os.path.join(d, ktname(f))
    if os.path.exists(path): skipped.append(ktname(f)); continue
    out = ['package org.bytefred.ksat.cadical.full', '',
           f'// STUB generated from SIGNATURES.md; to be replaced by the 1:1 translation of {f}.cpp.', '']
    for s in sigs:
        m = re.match(r'(\w+)\.(\w+)\((.*)\): (.+)$', s)
        if not m: sys.exit('cannot parse: ' + s)
        recv, name, params, ret = m.groups()
        out.append(f'internal fun {recv}.{name}({params}): {ret} = TODO("{f}.cpp: {name}")')
    open(path, 'w').write('\n'.join(out) + '\n'); made.append(ktname(f))
print('stubs:', len(made), made); print('skipped (exist):', skipped)
