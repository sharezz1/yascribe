import json, math
from PIL import Image
im=Image.open("zrodlo-chatgpt-zlote-pioro.png").convert("RGB"); W,H=im.size; px=im.load()
# pole złota: kanał R (granat ~15, złoto ~245)
f=[[min(1,max(0,(px[x,y][0]-15)/230)) for x in range(W)] for y in range(H)]
def interp(a,b,p,q,L=0.5):
    t=(L-a)/(b-a) if b!=a else .5
    return (p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t)
segs=[]
for y in range(H-1):
    for x in range(W-1):
        v=[f[y][x],f[y][x+1],f[y+1][x+1],f[y+1][x]]
        c=[(x,y),(x+1,y),(x+1,y+1),(x,y+1)]
        idx=sum((1<<i) for i in range(4) if v[i]>=.5)
        if idx in (0,15): continue
        def e(i):
            j=(i+1)%4; return interp(v[i],v[j],c[i],c[j])
        tab={1:[(3,0)],2:[(0,1)],3:[(3,1)],4:[(1,2)],5:[(3,0),(1,2)],6:[(0,2)],7:[(3,2)],8:[(2,3)],9:[(0,2)],10:[(0,1),(2,3)],11:[(1,2)],12:[(1,3)],13:[(0,1)],14:[(3,0)]}
        for a,b in tab[idx]: segs.append((e(a),e(b)))
# łączenie odcinków w kontury
key=lambda p:(round(p[0],3),round(p[1],3))
nxt={}
for a,b in segs:
    nxt.setdefault(key(a),[]).append((a,b)); nxt.setdefault(key(b),[]).append((b,a))
used=set(); loops=[]
for a,b in segs:
    if (key(a),key(b)) in used or (key(b),key(a)) in used: continue
    loop=[a]; cur,prev=b,a; used.add((key(a),key(b)))
    while key(cur)!=key(loop[0]):
        loop.append(cur)
        cand=[s for s in nxt[key(cur)] if key(s[1])!=key(prev) or False]
        if not cand: break
        n=cand[0][1]
        used.add((key(cur),key(n))); prev,cur=cur,n
    loops.append(loop)
loops=[l for l in loops if len(l)>30]
def rdp(p,eps):
    if len(p)<3: return p
    (x1,y1),(x2,y2)=p[0],p[-1]; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1
    dm,im_=0,0
    for i in range(1,len(p)-1):
        d=abs(dy*p[i][0]-dx*p[i][1]+x2*y1-y2*x1)/L
        if d>dm: dm,im_=d,i
    if dm>eps: return rdp(p[:im_+1],eps)[:-1]+rdp(p[im_:],eps)
    return [p[0],p[-1]]
res=[]
for l in loops:
    h=len(l)//2; s=rdp(l[:h+1],0.7)[:-1]+rdp(l[h:]+[l[0]],0.7)[:-1]
    res.append(s)
# słupki: komponenty teal po bbox (BFS)
teal=[[1 if (px[x,y][1]>140 and px[x,y][2]>130 and px[x,y][0]<110) else 0 for x in range(W)] for y in range(H)]
seen=[[0]*W for _ in range(H)]; bars=[]
for y in range(H):
    for x in range(W):
        if teal[y][x] and not seen[y][x]:
            st=[(x,y)]; seen[y][x]=1; x0=x1=x; y0=y1=y; n=0
            while st:
                a,b=st.pop(); n+=1; x0=min(x0,a);x1=max(x1,a);y0=min(y0,b);y1=max(y1,b)
                for da,db in((1,0),(-1,0),(0,1),(0,-1)):
                    c,d=a+da,b+db
                    if 0<=c<W and 0<=d<H and teal[d][c] and not seen[d][c]: seen[d][c]=1; st.append((c,d))
            if n>40: bars.append((x0,y0,x1+1,y1+1))
bars.sort()
gx=[p[0] for l in res for p in l]; gy=[p[1] for l in res for p in l]
bb=[min([b[0] for b in bars]+gx),min([b[1] for b in bars]+gy),max([b[2] for b in bars]+gx),max([b[3] for b in bars]+gy)]
json.dump({"loops":res,"bars":bars,"bbox":bb},open("ksztalty.json","w"))
print([len(l) for l in res],len(bars),bars,bb)
