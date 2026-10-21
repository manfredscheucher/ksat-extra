import itertools
V='abcdefghijk'
def L(s): return [(-1 if t[0]=='-' else 1)*(V.index(t.lstrip('-'))+1) for t in s.split()]
C=[L(x) for x in ['-a b','-c d','-c e','-f g','-h i','-i j','-i -a -d k','-j -k -b -e']]
def implied(cl, cls, n=11):
    for bits in itertools.product([0,1],repeat=n):
        val=lambda l: bits[abs(l)-1]==(l>0)
        if all(any(val(l) for l in c) for c in cls) and not any(val(l) for l in cl): return False
    return True
print('L1',implied(L('-i -a -b -d -e'),C),'L2',implied(L('-i -a -d -e'),C),'L3',implied(L('-i -a -c'),C),'dec',implied(L('-h -a -c'),C))
# models count
def models(cls,n):
    r=[]
    for bits in itertools.product([0,1],repeat=n):
        val=lambda l: bits[abs(l)-1]==(l>0)
        if all(any(val(l) for l in c) for c in cls): r.append(bits)
    return r
m=[1,1,1,1,1,1,1,0,0,1,0]
print('model ok', tuple(m) in models(C,11))
# queue-based propagation trace for decisions a c f h
def run(decs, cls):
    assign={}; trail=[]
    def val(l):
        v=assign.get(abs(l)); 
        return None if v is None else (v[0]==(l>0))
    for lvl,d in enumerate(decs,1):
        assign[abs(d)]=(d>0,lvl,None); trail.append(d); q=len(trail)-1
        while q<len(trail):
            x=trail[q]; q+=1
            for ci,c in enumerate(cls):
                if -x not in c: continue
                vals=[val(l) for l in c]
                if any(v is True for v in vals): continue
                un=[l for l,v in zip(c,vals) if v is None]
                if not un: return trail,('conflict',ci+1)
                if len(un)==1:
                    u=un[0]; assign[abs(u)]=(u>0,lvl,ci+1); trail.append(u)
    return trail,None
nm=lambda l:('-' if l<0 else '')+V[abs(l)-1]
t,cf=run(L('a c f h'),C); print([nm(l) for l in t],cf)
# OTFS toy
D=[L('-b c'),L('-a -c d'),L('-c -d')]
t,cf=run(L('a b'),D); print('otfs',[nm(l) for l in t],cf, implied(L('-a -c'),D,4))
