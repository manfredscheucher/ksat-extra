import math
# EVSIDS
s={'a':0,'b':0,'c':0,'d':0}; inc=1.0
for bumped in [('a','b'),('b','c'),('a','c')]:
    for v in bumped: s[v]+=inc
    inc/=0.95
    print(bumped, {k:round(v,4) for k,v in s.items()}, round(inc,4))
# EMA
def ema(window, seq):
    a=1/window; beta=1-a; biased=0; exp=1.0; out=[]
    for y in seq:
        biased += a*(y-biased); exp*=beta; out.append(biased/(1-exp))
    return out
seq=[4]*1000+[8]*6
f=ema(33,seq); s_=ema(1e5,seq)
for t in range(999,1006): print(t+1, round(f[t],3), round(s_[t],3), round(1.1*s_[t],3), f[t]>=1.1*s_[t])
# toy
x=0
for g in [4,4,8]: x+=0.5*(g-x); print('toy',x)
# kissat formulas
for n in range(1,5): print('rephase',n, 1000*n*math.log10(n+9)**3, 'mode', 1000*n*math.log10(n+9)**4, 'randlen', math.floor(10*math.log10(n+9)), 'randint', 500*math.log10(n+9))
# rephase cadical cumulative
lim=1000; pts=[]
for k in range(1,5): pts.append(lim); lim+=1000*(k+1)
print('cad rephase',pts)
# luby / reluctant
u=v=1; vals=[1]
for _ in range(14):
    if (u & -u)==v: u,v=u+1,1
    else: v*=2
    vals.append(v)
print(vals)
# walk probs
for cb in [2,2+0.5*2.25/3]:
    w=[1,cb**-2]; print(cb, w[0]/sum(w), w[1]/sum(w))
