# Ikona paska menu (TASK-106): pióro i cztery słupki znaku jako obraz-szablon (czarny + przezroczystość; system barwi go sam).
# Słupki zachodzące na pióro dostają szczelinę (maska), żeby w jednym kolorze nie zlały się z piórem.
# Użycie (z docs/design/marka): python3 zloz-pasek.py > ../../../Resources/MenuBarIcon.svg
import json
d=json.load(open("ksztalty.json")); outer=max(d["loops"],key=len); bars=d["bars"]
KEEP,BW,GAP=(3,4,6,7),24,9
def bar(i,gap=0):
    x0,y0,x1,y1=bars[i]; w=BW+2*gap
    return f'<rect x="{(x0+x1)/2-w/2:.1f}" y="{y0-gap:.1f}" width="{w:.1f}" height="{y1-y0+2*gap:.1f}" rx="{w/2:.1f}"/>'
fea="M"+" L".join(f"{x:.1f},{y:.1f}" for x,y in outer)+"Z"
print(f'''<svg viewBox="140 88 220 292" xmlns="http://www.w3.org/2000/svg"><defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="500" height="500"><rect width="500" height="500" fill="white"/><g fill="black">{"".join(bar(i,GAP) for i in KEEP)}</g></mask></defs><path d="{fea}" fill="#000" mask="url(#m)"/><g fill="#000">{"".join(bar(i) for i in KEEP)}</g></svg>''')
