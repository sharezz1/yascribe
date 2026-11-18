#!/bin/bash
# Pokrycie skryptów składania (S18, BACKLOG): bundle.sh z podpisem ad-hoc, poprawny Info.plist z kluczami TCC
# i podpis, który się weryfikuje. Buduje do OSOBNEJ ścieżki (.build/check), żeby nie nadpisać pakietu
# podpisanego „Apple Development" (ad-hoc zmienia cdhash i TCC resetuje uprawnienia).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(YASCRIBE_APP=.build/check/Yascribe.app YASCRIBE_SIGN_IDENTITY=- scripts/bundle.sh 2>/dev/null | tail -1)"
[ "$APP" = ".build/check/Yascribe.app" ] || { echo "check-bundle: bundle.sh zwrócił nieoczekiwaną ścieżkę: $APP" >&2; exit 1; }
[ -d "$APP" ] || { echo "check-bundle: brak paczki $APP" >&2; exit 1; }
cmp Resources/ThirdPartyNotices/SpeexDSP.txt "$APP/Contents/Resources/ThirdPartyNotices/SpeexDSP.txt" || { echo "check-bundle: brak licencji SpeexDSP" >&2; exit 1; }
cmp Resources/ThirdPartyNotices/SpeakerDetection-CC-BY-4.0.txt "$APP/Contents/Resources/ThirdPartyNotices/SpeakerDetection-CC-BY-4.0.txt" || { echo "check-bundle: brak noty CC-BY-4.0 modelu mówców" >&2; exit 1; }
cmp Resources/MenuBarIcon.svg "$APP/Contents/Resources/MenuBarIcon.svg" || { echo "check-bundle: brak ikony paska menu" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
plutil -lint "$PLIST" >/dev/null
for key in CFBundleIdentifier LSMinimumSystemVersion NSMicrophoneUsageDescription NSAudioCaptureUsageDescription NSCalendarsFullAccessUsageDescription; do
    plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1 || { echo "check-bundle: brak klucza $key w Info.plist" >&2; exit 1; }
done
for lang in en pl; do
    table="$APP/Contents/Resources/$lang.lproj/Localizable.strings"
    [ -s "$table" ] || { echo "check-bundle: brak tabeli $table" >&2; exit 1; }
    plural_table="$APP/Contents/Resources/$lang.lproj/Localizable.stringsdict"
    [ -s "$plural_table" ] || { echo "check-bundle: brak tabeli $plural_table" >&2; exit 1; }
    plutil -extract CFBundleLocalizations json "$PLIST" | grep -q "\"$lang\"" || { echo "check-bundle: brak języka $lang" >&2; exit 1; }
done
PL_INFO="$APP/Contents/Resources/pl.lproj/InfoPlist.strings"
[ -s "$PL_INFO" ] || { echo "check-bundle: brak $PL_INFO" >&2; exit 1; }
for key in NSMicrophoneUsageDescription NSAudioCaptureUsageDescription NSCalendarsFullAccessUsageDescription; do
    value="$(plutil -extract "$key" raw "$PL_INFO")"
    [ -n "$(printf '%s' "$value" | tr -d '[:space:]')" ] || { echo "check-bundle: pusty opis $key" >&2; exit 1; }
done
while IFS= read -r -d '' file; do
    plutil -lint "$file" >/dev/null || { echo "check-bundle: błędny plik $file" >&2; exit 1; }
done < <(find "$APP/Contents/Resources" \( -name '*.strings' -o -name '*.stringsdict' \) -print0)
# Sparkle (T5): framework osadzony, rpath, brak XPC (bez sandboxa), podpis od środka, klucze aktualizacji, numer builda.
FW="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$FW" ] || { echo "check-bundle: brak $FW" >&2; exit 1; }
otool -l "$APP/Contents/MacOS/YascribeApp" | grep -q '@executable_path/../Frameworks' || { echo "check-bundle: brak rpath @executable_path/../Frameworks" >&2; exit 1; }
[ ! -e "$FW/Versions/B/XPCServices" ] && [ ! -e "$FW/XPCServices" ] || { echo "check-bundle: XPCServices zostały w frameworku" >&2; exit 1; }
for key in SUFeedURL SUPublicEDKey; do
    plutil -extract "$key" raw "$PLIST" >/dev/null 2>&1 || { echo "check-bundle: brak klucza $key w Info.plist" >&2; exit 1; }
done
[ "$(plutil -extract SUAllowsAutomaticUpdates raw "$PLIST" 2>/dev/null)" = "false" ] || { echo "check-bundle: SUAllowsAutomaticUpdates musi być false" >&2; exit 1; }
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
case "$BUILD" in ''|*[!0-9]*|0) echo "check-bundle: CFBundleVersion nie jest liczbą całkowitą >= 1: $BUILD" >&2; exit 1 ;; esac
# Reguła: jeden moduł importuje zewnętrzną bibliotekę (Sparkle tylko w YascribeUpdates).
OUTSIDE="$(git grep -l 'import Sparkle' -- Sources | grep -v '^Sources/YascribeUpdates/' || true)"
[ -z "$OUTSIDE" ] || { echo "check-bundle: import Sparkle poza YascribeUpdates: $OUTSIDE" >&2; exit 1; }
codesign --verify --strict --deep "$APP"
echo "check-bundle: OK ($APP)"
