#!/bin/bash
# Składa Resources/AppIcon.icns z docs/design/marka/<svg> bez Xcode i Icon Composera:
# Chrome headless (SVG → PNG 1024 z przezroczystością) → sips (rozmiary) → iconutil.
# Rozmiary do 64 px bierze z wersji „małej” (mN.svg, grubsze słupki, bez szpary), większe z wN.svg.
# Użycie: docs/design/marka/zrob-icns.sh [w3.svg]
set -euo pipefail
cd "$(dirname "$0")/../../.."
SVG="docs/design/marka/${1:-w3.svg}"
SMALL="$(dirname "$SVG")/m${SVG##*/w}"
[ -f "$SVG" ] && [ -f "$SMALL" ] || { echo "zrob-icns: brak $SVG albo $SMALL" >&2; exit 1; }
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
render() { # $1 svg, $2 plik png
  printf '<!doctype html><meta charset=utf-8><style>html,body{margin:0;background:transparent}svg{display:block}</style>%s' "$(cat "$1")" > "$TMP/i.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=1024,1024 \
    --screenshot="$2" "file://$TMP/i.html" >/dev/null 2>&1
}
render "$SVG" "$TMP/1024.png"
render "$SMALL" "$TMP/small.png"
SET="$TMP/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  for n in $s $((s*2)); do
    src="$TMP/1024.png"; [ $n -le 64 ] && src="$TMP/small.png"
    [ $n = $s ] && out="icon_${s}x${s}.png" || out="icon_${s}x${s}@2x.png"
    sips -z $n $n "$src" --out "$SET/$out" >/dev/null
  done
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns ← $SVG"
