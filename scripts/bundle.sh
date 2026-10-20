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
# Logi budowy na stderr: stdout to wyłącznie ścieżka paczki (kontrakt z run.sh).
swift build --disable-keychain -c "$CONFIG" --product MeetNotesApp >&2
BIN="$(swift build --disable-keychain -c "$CONFIG" --show-bin-path)/MeetNotesApp"
APP="${MEETNOTES_APP:-.build/MeetNotes.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetNotesApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="${MEETNOTES_SIGN_IDENTITY:-MeetNotes Dev}"
# Pełny odczyt do zmiennej zamiast `| grep -q`: grep kończy na pierwszym trafieniu,
# security dostaje SIGPIPE, a pipefail zamienia to w fałsz → cichy podpis ad-hoc.
CERTS=""
[ "$IDENTITY" = "-" ] || CERTS="$(security find-identity -p codesigning || true)"
case "$CERTS" in
    *"\"$IDENTITY\""*)
        codesign --force --sign "$IDENTITY" "$APP" ;;
    *)
        [ "$IDENTITY" != "-" ] && echo "UWAGA: brak certyfikatu \"$IDENTITY\" — podpis ad-hoc; TCC zresetuje uprawnienia po każdej przebudowie" >&2
        codesign --force --sign - "$APP" ;;
esac
codesign --verify --strict "$APP"
echo "$APP"
