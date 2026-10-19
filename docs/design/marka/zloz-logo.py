# Składa logotypy (znak + nazwa Yascribe + motto) z ikony wN i konturów New York.
# Wymaga: logotyp-krzywe.json (napis-na-krzywe.swift) i zloz-ikone.py. Zestaw kolorów ikony: V[2] (zestaw 3).
import json, importlib.util
spec=importlib.util.spec_from_file_location("z","zloz-ikone.py"); z=importlib.util.module_from_spec(spec); spec.loader.exec_module(z)
K=json.load(open("logotyp-krzywe.json")); N,M=K["nazwa"],K["motto"]
V=z.V[2][3]
def mark(h):  # znak: sam squircle (824 pt z kanwy 1024), wysokość h
    inner=z.icon(V,1024).replace('width="1024" height="1024" viewBox="0 0 1024 1024"','width="%d" height="%d" viewBox="100 100 824 824"'%(h,h))
    return inner
THEMES={"jasne":dict(bg="#F7F6F2",text="#22211E",sub="#666259"),"ciemne":dict(bg="#1C1C1B",text="#ECEBE6",sub="#9A978F")}
def poziome(t,c):
    H=320; k=1.25; capk=N["cap"]*k; gap=60; pad=80
    w=pad*2+H+gap+N["w"]*k; h=H+pad*2
    base=pad+H/2+capk/2
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h}" viewBox="0 0 {w:.0f} {h}"><rect width="100%" height="100%" fill="{c["bg"]}"/>
<g transform="translate({pad} {pad})">{mark(H)}</g>
<path transform="translate({pad+H+gap} {base:.1f}) scale({k})" d="{N["d"]}" fill="{c["text"]}"/></svg>'''
def pionowe(t,c):
    H=360; k=1.0; kk=0.34; pad=90
    w=max(M["w"]*kk,N["w"]*k)+pad*2; w=max(w,H+pad*2)
    y=pad; out=f'<g transform="translate({(w-H)/2:.1f} {y})">{mark(H)}</g>'
    y+=H+40+N["cap"]*k
    out+=f'<path transform="translate({(w-N["w"]*k)/2:.1f} {y:.1f}) scale({k})" d="{N["d"]}" fill="{c["text"]}"/>'
    y+=44+M["cap"]*kk
    out+=f'<path transform="translate({(w-M["w"]*kk)/2:.1f} {y:.1f}) scale({kk})" d="{M["d"]}" fill="{c["sub"]}"/>'
    h=y+pad
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" viewBox="0 0 {w:.0f} {h:.0f}"><rect width="100%" height="100%" fill="{c["bg"]}"/>{out}</svg>'
if __name__=="__main__":
    prev=""
    for t,c in THEMES.items():
        for n,f in (("poziome",poziome),("pionowe",pionowe)):
            s=f(t,c); open(f"logo-{n}-{t}.svg","w").write(s)
            prev+=f'<div class="b">{s}</div>'
    open("logo-podglad.html","w").write(f'<!doctype html><meta charset=utf-8><style>body{{margin:0;padding:24px;background:#EFEDE6}}.g{{display:grid;grid-template-columns:auto auto;gap:20px;align-items:start;width:max-content}}svg{{display:block;max-width:760px;height:auto}}.b{{border-radius:12px;overflow:hidden;border:1px solid #3C321424}}</style><div class="g">{prev}</div>')
