#!/bin/bash
# Składa Resources/AppIcon.icns z docs/design/marka/<svg> bez Xcode i Icon Composera:
# Chrome headless (SVG → PNG 1024 z przezroczystością) → sips (rozmiary) → iconutil.
# Użycie: docs/design/marka/zrob-icns.sh [w3.svg]
set -euo pipefail
cd "$(dirname "$0")/../../.."
SVG="docs/design/marka/${1:-w3.svg}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '<!doctype html><meta charset=utf-8><style>html,body{margin:0;background:transparent}svg{display:block}</style>%s' "$(cat "$SVG")" > "$TMP/i.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot="$TMP/1024.png" "file://$TMP/i.html" >/dev/null 2>&1
SET="$TMP/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns ← $SVG"
