import json, math
d=json.load(open("ksztalty.json"))
loops=sorted(d["loops"],key=len)[-2:]   # kontur zewnętrzny pióra i szpara
bars=d["bars"]; bb=d["bbox"]
def squircle(n=5,a=412,cx=512,cy=512,steps=240):
    pts=[]
    for i in range(steps):
        t=2*math.pi*i/steps;c,s=math.cos(t),math.sin(t)
        pts.append(f"{cx+a*math.copysign(abs(c)**(2/n),c):.1f},{cy+a*math.copysign(abs(s)**(2/n),s):.1f}")
    return "M"+" L".join(pts)+"Z"
SQ=squircle()
S=2.0; cx=(bb[0]+bb[2])/2; cy=(bb[1]+bb[3])/2
def T(p): return ((p[0]-cx)*S+512,(p[1]-cy)*S+512)
feather=" ".join("M"+" L".join(f"{T(p)[0]:.1f},{T(p)[1]:.1f}" for p in l)+"Z" for l in loops)
def barsvg(col):
    o=""
    w=15.5*S
    for x0,y0,x1,y1 in bars:
        X=T(((x0+x1)/2,0))[0]; Y0=T((0,y0-0.2))[1]; Y1=T((0,y1+0.2))[1]
        o+=f'<rect x="{X-w/2:.1f}" y="{Y0:.1f}" width="{w:.1f}" height="{Y1-Y0:.1f}" rx="{w/2:.1f}" fill="{col}"/>'
    return o
def icon(v,size):
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg"><path d="{SQ}" fill="{v["tile"]}" stroke="{v["edge"]}" stroke-width="3"/><path d="{feather}" fill="{v["f"]}" fill-rule="evenodd"/>{barsvg(v["b"])}</svg>'''
GOLD="#F2BD55"
V=[("1","Granat, złoto i turkus","dokładnie kolory z twojego obrazu",dict(tile="#0F1A33",f=GOLD,b="#2EC4B6",edge="#FFFFFF1F")),
   ("2","Ciepły tusz, złoto i mięta","te same kształty w palecie B (tło #22211E, mięta #7CC39C)",dict(tile="#22211E",f=GOLD,b="#7CC39C",edge="#FFFFFF1F")),
   ("3","Ciepły tusz, złoto i turkus","tylko tło zamienione na ciepły tusz",dict(tile="#22211E",f=GOLD,b="#2EC4B6",edge="#FFFFFF1F")),
   ("4","Zielone tło, złoto i krem","tło w kolorze akcentu #2F6B4F, słupki kremowe",dict(tile="#2F6B4F",f=GOLD,b="#F7F6F2",edge="#00000022"))]
if __name__=="__main__":
    cards=""
    for k,n,dsc,v in V:
        cards+=f'<div class="card"><div class="h"><b>{k}. {n}</b><span>{dsc}</span></div><div class="row">{icon(v,300)}<div class="sm">{icon(v,128)}{icon(v,64)}{icon(v,32)}{icon(v,16)}</div></div></div>'
        open(f"w{k}.svg","w").write(icon(v,1024))
    open("wersje.html","w").write(f'''<!doctype html><meta charset=utf-8><style>
body{{margin:0;background:#EFEDE6;font:13px -apple-system,system-ui;color:#22211E;padding:28px}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:22px;width:1280px}}
.card{{background:#E3E0D6;border:1px solid #3C321424;border-radius:14px;padding:18px}}
.h b{{font:600 15px -apple-system}}.h span{{display:block;color:#666259;margin:2px 0 14px}}
.row{{display:flex;gap:22px;align-items:flex-end}}.sm{{display:flex;gap:14px;align-items:flex-end}}</style><div class="grid">{cards}</div>''')
