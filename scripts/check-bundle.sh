#!/bin/bash
# Pokrycie skryptów składania (S18, BACKLOG): bundle.sh z podpisem ad-hoc, poprawny Info.plist z kluczami TCC
# i podpis, który się weryfikuje. Buduje do OSOBNEJ ścieżki (.build/check), żeby nie nadpisać pakietu
# podpisanego „MeetNotes Dev" (ad-hoc zmienia cdhash i TCC resetuje uprawnienia).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(MEETNOTES_APP=.build/check/MeetNotes.app MEETNOTES_SIGN_IDENTITY=- scripts/bundle.sh 2>/dev/null | tail -1)"
[ "$APP" = ".build/check/MeetNotes.app" ] || { echo "check-bundle: bundle.sh zwrócił nieoczekiwaną ścieżkę: $APP" >&2; exit 1; }
[ -d "$APP" ] || { echo "check-bundle: brak paczki $APP" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
plutil -lint "$PLIST" >/dev/null
for key in CFBundleIdentifier LSMinimumSystemVersion NSMicrophoneUsageDescription NSAudioCaptureUsageDescription NSCalendarsFullAccessUsageDescription; do
    plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1 || { echo "check-bundle: brak klucza $key w Info.plist" >&2; exit 1; }
done
codesign --verify --strict "$APP"
echo "check-bundle: OK ($APP)"
