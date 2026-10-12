#!/bin/bash
# Składa MeetNotes.app z pliku wykonywalnego SwiftPM — bez Xcode.
#
# Podpis: stały certyfikat "MeetNotes Dev" (plan D, zadanie D1). Bez niego podpis
# ad-hoc zmienia cdhash przy każdej przebudowie i TCC resetuje uprawnienia do
# mikrofonu i dźwięku systemowego (spec rdzenia §8).
#   MEETNOTES_SIGN_IDENTITY=-   wymusza ad-hoc (np. w CI, bez pęku kluczy)
#   CONFIG=release              budowa w trybie release
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-debug}"
swift build -c "$CONFIG" --product MeetNotesApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MeetNotesApp"
APP=".build/MeetNotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetNotesApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="${MEETNOTES_SIGN_IDENTITY:-MeetNotes Dev}"
if [ "$IDENTITY" != "-" ] && security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    [ "$IDENTITY" != "-" ] && echo "UWAGA: brak certyfikatu \"$IDENTITY\" — podpis ad-hoc; TCC zresetuje uprawnienia po każdej przebudowie" >&2
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "$APP"
