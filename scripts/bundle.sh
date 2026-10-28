#!/bin/bash
# Składa Yascribe.app z pliku wykonywalnego SwiftPM — bez Xcode.
#
# Podpis: stały certyfikat "MeetNotes Dev" (plan D, zadanie D1). Bez niego podpis
# ad-hoc zmienia cdhash przy każdej przebudowie i TCC resetuje uprawnienia do
# mikrofonu i dźwięku systemowego (spec rdzenia §8).
#   YASCRIBE_SIGN_IDENTITY=-   wymusza ad-hoc (np. w CI, bez pęku kluczy)
#   CONFIG=release              budowa w trybie release
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-debug}"
# Logi budowy na stderr: stdout to wyłącznie ścieżka paczki (kontrakt z run.sh).
swift build --disable-keychain -c "$CONFIG" --product YascribeApp >&2
BIN="$(swift build --disable-keychain -c "$CONFIG" --show-bin-path)/YascribeApp"
APP="${YASCRIBE_APP:-.build/Yascribe.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/YascribeApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/ThirdPartyNotices "$APP/Contents/Resources/ThirdPartyNotices"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Wersja z VERSION, numer builda = liczba commitów (rośnie z każdym commitem; Sparkle porównuje `CFBundleVersion`).
# Tylko w paczce, nie w Resources/Info.plist; YASCRIBE_VERSION / YASCRIBE_BUILD nadpisują (testy release.sh).
plutil -replace CFBundleShortVersionString -string "${YASCRIBE_VERSION:-$(tr -d '[:space:]' < VERSION)}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${YASCRIBE_BUILD:-$(git rev-list --count HEAD)}" "$APP/Contents/Info.plist"

# Sparkle (S0 Yascribe): framework przez ditto (zachowuje symlinki), rpath do Frameworks, bez XPCServices (aplikacja
# nie jest w sandboxie; usuwamy też dowiązanie na korzeniu frameworka).
FW_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$FW_SRC" ] || { echo "bundle.sh: brak $FW_SRC (swift package --disable-keychain resolve)" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$FW_SRC" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/YascribeApp"
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

IDENTITY="${YASCRIBE_SIGN_IDENTITY:-MeetNotes Dev}"
# Pełny odczyt do zmiennej zamiast `| grep -q`: grep kończy na pierwszym trafieniu,
# security dostaje SIGPIPE, a pipefail zamienia to w fałsz → cichy podpis ad-hoc.
CERTS=""
[ "$IDENTITY" = "-" ] || CERTS="$(security find-identity -p codesigning || true)"
case "$CERTS" in
    *"\"$IDENTITY\""*) SIGN="$IDENTITY" ;;
    *)
        [ "$IDENTITY" != "-" ] && echo "UWAGA: brak certyfikatu \"$IDENTITY\" — podpis ad-hoc; TCC zresetuje uprawnienia po każdej przebudowie" >&2
        SIGN="-" ;;
esac
# Podpis od środka, każdy element osobno, bez --deep: Autoupdate, Updater.app, framework, aplikacja.
for part in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW" "$APP"; do
    codesign --force --sign "$SIGN" "$part" >&2
done
codesign --verify --strict --deep "$APP"
echo "$APP"
