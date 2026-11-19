#!/bin/bash
# Składa Yascribe.app z pliku wykonywalnego SwiftPM — bez Xcode.
#
# Podpis: certyfikat "Apple Development" (darmowe Apple ID, zespół 885WJQV8LG; TASK-99) z jawnym
# designated requirement wiążącym zespół. Pęk kluczy daje wtedy partycję teamid: zamiast cdhash:,
# więc nie pyta o hasło po każdym buildzie, a TCC i ACL pęku przeżyją odnowienie certyfikatu.
# Bez certyfikatu: podpis ad-hoc, cdhash zmienia się co build, TCC resetuje uprawnienia (spec rdzenia §8).
#   YASCRIBE_SIGN_IDENTITY=-   wymusza ad-hoc (np. w CI, bez pęku kluczy)
#   YASCRIBE_TEAM_ID           zespół w designated requirement (domyślnie 885WJQV8LG)
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
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.svg "$APP/Contents/Resources/MenuBarIcon.svg"
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

IDENTITY="${YASCRIBE_SIGN_IDENTITY:-Apple Development}"
TEAM="${YASCRIBE_TEAM_ID:-885WJQV8LG}"
APPLE=0
case "$IDENTITY" in "Apple Development"*|"Developer ID"*) APPLE=1 ;; esac
# Pełny odczyt do zmiennej zamiast `| grep -q`: grep kończy na pierwszym trafieniu,
# security dostaje SIGPIPE, a pipefail zamienia to w fałsz → cichy podpis ad-hoc.
# Certyfikat Apple: tylko ważne tożsamości (-v), a z nich pierwsza z certyfikatem zespołu $TEAM (stary i odnowiony
# certyfikat pasują do tej samej nazwy, a codesign -s odmawia przy kilku dopasowaniach), podpis po odcisku SHA-1.
# Inna nazwa (np. samopodpisany "MeetNotes Dev", NOT_TRUSTED) jak dotąd: bez -v, po nazwie.
SIGN="-"
if [ "$IDENTITY" != "-" ]; then
    if [ "$APPLE" = 1 ]; then CERTS="$(security find-identity -v -p codesigning || true)"; else CERTS="$(security find-identity -p codesigning || true)"; fi
    for h in $(printf '%s\n' "$CERTS" | awk -v id="\"$IDENTITY" 'index($0, id) {print $2}'); do
        if [ "$APPLE" = 1 ]; then
            PEM="$(security find-certificate -a -Z -p -c "$IDENTITY" | awk -v h="$h" '/^SHA-1 hash:/ {on = ($3 == h)} on && /BEGIN CERT/ {p = 1} p {print} /END CERT/ {p = 0}')"
            case "$(printf '%s\n' "$PEM" | openssl x509 -noout -subject 2>/dev/null)" in *"OU=$TEAM,"*|*"OU = $TEAM,"*) ;; *) continue ;; esac
        fi
        SIGN="$h"; break
    done
    [ "$SIGN" = "-" ] && echo "UWAGA: brak certyfikatu \"$IDENTITY\" (zespół $TEAM) — podpis ad-hoc; TCC zresetuje uprawnienia po każdej przebudowie, pęk zapyta o hasło" >&2
fi
# Podpis od środka, każdy element osobno, bez --deep: Autoupdate, Updater.app, framework, aplikacja.
for part in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
    codesign --force --sign "$SIGN" "$part" >&2
done
# Designated requirement aplikacji wiąże zespół, nie nazwę (CN) ani odcisk certyfikatu; tylko dla certyfikatu Apple.
if [ "$APPLE" = 1 ] && [ "$SIGN" != "-" ]; then
    codesign --force --sign "$SIGN" \
        "-r=designated => identifier \"io.github.sharezz1.yascribe\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\"" \
        "$APP" >&2
else
    codesign --force --sign "$SIGN" "$APP" >&2
fi
codesign --verify --strict --deep "$APP"
echo "$APP"
