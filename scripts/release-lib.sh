#!/bin/bash
# Orkiestracja wydania (T6). Wołana z scripts/release.sh; testowana przez scripts/check-release.sh na atrapach.
# Każdy krok kończy się `die` przed jakimkolwiek zapisem poza katalogiem tymczasowym, aż do kroku (8) (gh).
# NIGDY `set -x`: log nie może zawierać kluczy ani tokenów. Wykonawcy podstawialni zmiennymi środowiskowymi:
#   YASCRIBE_TEST_CMD (scripts/test.sh), YASCRIBE_BUNDLE_CMD (CONFIG=release scripts/bundle.sh), YASCRIBE_SIGN_UPDATE,
#   YASCRIBE_GH (gh), YASCRIBE_FETCH (curl -fsSL), YASCRIBE_IDENTITY_CHECK, YASCRIBE_REMOTE_HEAD_CMD.

REPO="sharezz1/yascribe"

die() { echo "release: $*" >&2; exit 1; }

# Kontrola tożsamości podpisu (S0, wersja z raportu): nie ad-hoc, designated requirement ma identifier i odcisk SHA-1
# certyfikatu „MeetNotes Dev" z `security find-identity` (bez `-v`: certyfikat samopodpisany jest NOT_TRUSTED);
# nie polegamy na `Authority=`.
default_identity_check() {
    local app="$1" dv dr want
    dv="$(codesign -dv "$app" 2>&1)" || return 1
    case "$dv" in *"Signature=adhoc"*) echo "podpis ad-hoc" >&2; return 1 ;; esac
    dr="$(codesign -dr - "$app" 2>&1)" || return 1
    case "$dr" in *'identifier "io.github.sharezz1.yascribe"'*) ;; *) echo "zły identifier w designated requirement" >&2; return 1 ;; esac
    want="$(security find-identity -p codesigning | awk '/"MeetNotes Dev"/ {print tolower($2); exit}')"
    [ -n "$want" ] || { echo "brak certyfikatu MeetNotes Dev w pęku" >&2; return 1; }
    case "$(echo "$dr" | tr 'A-Z' 'a-z')" in *"certificate leaf = h\"$want\""*) ;; *) echo "odcisk certyfikatu nie zgadza się z pękiem" >&2; return 1 ;; esac
    codesign --verify --strict --deep "$app" 2>/dev/null
}

# Pobranie feedu: 0 = treść na stdout, 22 = HTTP 404 (brak feedu), inny kod = błąd. Z atrapą (YASCRIBE_FETCH) kody idą wprost;
# domyślnie `curl` oddaje dla 404 po przekierowaniu kod 56, nie 22, więc czytamy kod HTTP z `-w`.
fetch_feed() {
    if [ -n "${YASCRIBE_FETCH:-}" ]; then $YASCRIBE_FETCH "$1"; return $?; fi
    local body code
    body="$(mktemp "${TMPDIR:-/tmp}/mn-feed.XXXXXX")"
    code="$(curl -sSL -o "$body" -w '%{http_code}' "$1")" || { rm -f "$body"; return 1; }
    case "$code" in 200) cat "$body"; rm -f "$body"; return 0 ;; 404) rm -f "$body"; return 22 ;; *) rm -f "$body"; return 1 ;; esac
}

release_main() {
    unset YASCRIBE_BUILD YASCRIBE_VERSION
    local VERSION="" DRY=0 arg
    for arg in "$@"; do
        case "$arg" in --dry-run) DRY=1 ;; -*) die "nieznana opcja $arg" ;; *) VERSION="$arg" ;; esac
    done
    [ -n "$VERSION" ] || die "użycie: scripts/release.sh <wersja> [--dry-run]"

    local TEST_CMD="${YASCRIBE_TEST_CMD:-scripts/test.sh}"
    local BUNDLE_CMD="${YASCRIBE_BUNDLE_CMD:-CONFIG=release scripts/bundle.sh}"
    local SIGN_UPDATE="${YASCRIBE_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
    local GH="${YASCRIBE_GH:-gh}"
    local FETCH="${YASCRIBE_FETCH:-curl -fsSL}"
    local REMOTE_HEAD_CMD="${YASCRIBE_REMOTE_HEAD_CMD:-git ls-remote origin refs/heads/master}"

    # (1) stan repozytorium
    [ -z "$(git status --porcelain)" ] || die "drzewo robocze nie jest czyste"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "master" ] || die "wydanie tylko z gałęzi master"
    [ "$VERSION" = "$(tr -d '[:space:]' < VERSION)" ] || die "wersja $VERSION różni się od pliku VERSION"
    git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION już istnieje lokalnie"
    [ -z "$(git ls-remote --tags origin "refs/tags/v$VERSION")" ] || die "tag v$VERSION już istnieje zdalnie"
    local SHA REMOTE
    SHA="$(git rev-parse HEAD)"
    REMOTE="$($REMOTE_HEAD_CMD | awk '{print $1; exit}')"
    [ "$SHA" = "$REMOTE" ] || die "lokalny HEAD ($SHA) nie jest zdalnym masterem (${REMOTE:-brak}): najpierw push"

    # (2) testy
    bash -c "$TEST_CMD" >&2 || die "testy nie przeszły"

    # (3) klucz publiczny i paczka
    local KEY
    KEY="$(plutil -extract SUPublicEDKey raw Resources/Info.plist 2>/dev/null)" || die "brak SUPublicEDKey w Resources/Info.plist"
    [ "$KEY" != "REPLACE_WITH_PUBLIC_KEY" ] || die "SUPublicEDKey to wciąż REPLACE_WITH_PUBLIC_KEY (T8)"
    local APP
    APP="$(bash -c "$BUNDLE_CMD" | tail -1)" || die "budowa paczki nie powiodła się"
    [ -d "$APP" ] || die "paczka $APP nie istnieje"

    # (4) wersje czytane z gotowej paczki
    local PLIST="$APP/Contents/Info.plist" BUILD
    [ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" = "$VERSION" ] || die "CFBundleShortVersionString paczki ≠ $VERSION"
    BUILD="$(git rev-list --count HEAD)"
    [ "$(plutil -extract CFBundleVersion raw "$PLIST")" = "$BUILD" ] || die "CFBundleVersion paczki ≠ liczba commitów ($BUILD)"

    # (5) tożsamość podpisu
    if [ -n "${YASCRIBE_IDENTITY_CHECK:-}" ]; then $YASCRIBE_IDENTITY_CHECK "$APP"; else default_identity_check "$APP"; fi \
        || die "podpis paczki nie przeszedł kontroli tożsamości (ad-hoc albo obcy certyfikat)"

    # (6) numer builda większy od opublikowanego
    local FEED_URL FEED rc MAXV
    FEED_URL="$(plutil -extract SUFeedURL raw "$PLIST")"
    set +e; FEED="$(fetch_feed "$FEED_URL")"; rc=$?; set -e
    case "$rc" in 0) ;; 22) FEED="" ;; *) die "nie udało się pobrać feedu ($rc)" ;; esac # 22 = HTTP 404: pierwsze wydanie
    MAXV="$(printf '%s' "$FEED" | grep -oE 'sparkle:version(="|>)[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -1 || true)"
    [ -z "$MAXV" ] || [ "$BUILD" -gt "$MAXV" ] || die "numer builda $BUILD nie jest większy od opublikowanego ($MAXV)"
    # Pusty feed (404 przy prywatnym repo, zła odpowiedź) nie może wyłączać kontroli, gdy wydania v* już istnieją.
    if [ -z "$MAXV" ] && [ -n "$(git ls-remote --tags origin 'refs/tags/v*')" ]; then
        die "feed nie zawiera żadnego sparkle:version, a zdalnie są już tagi v*: nie da się sprawdzić numeru builda"
    fi

    # (7) zip, podpis EdDSA, appcast
    local OUT="${YASCRIBE_OUT_DIR:-}" ZIP SIGOUT SIG LENGTH
    if [ -z "$OUT" ]; then OUT="$(mktemp -d "${TMPDIR:-/tmp}/mn-release.XXXXXX")"; trap "rm -rf '$OUT'" EXIT; else mkdir -p "$OUT"; fi
    ZIP="$OUT/Yascribe-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    SIGOUT="$($SIGN_UPDATE "$ZIP")" || die "sign_update zawiódł"
    SIG="$(printf '%s' "$SIGOUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)"
    LENGTH="$(printf '%s' "$SIGOUT" | sed -n 's/.*length="\([0-9]*\)".*/\1/p' | head -1)"
    [ -n "$SIG" ] && [ -n "$LENGTH" ] || die "brak podpisu EdDSA albo długości z sign_update: odmowa wydania bez podpisu"
    "$(dirname "${BASH_SOURCE[0]}")/make-appcast.sh" "$ZIP" "$VERSION" "$BUILD" "$SIG" "$LENGTH" > "$OUT/appcast.xml"
    xmllint --noout "$OUT/appcast.xml" || die "appcast.xml nie jest poprawnym XML"

    if [ "$DRY" -eq 1 ]; then
        echo "release: --dry-run: gotowe (1)-(7). NIE wysłano: draft wydania v$VERSION, $ZIP, appcast.xml (gh nie wołany)." >&2
        echo "release: appcast: $OUT/appcast.xml"
        return 0
    fi

    # (8) szkic, pobranie, porównanie bajt w bajt, dopiero publikacja
    local DL="$OUT/download"
    mkdir -p "$DL"
    "$GH" release create "v$VERSION" --repo "$REPO" --draft --target "$SHA" --title "Yascribe $VERSION" \
        --notes "Yascribe $VERSION (build $BUILD)" "$ZIP" "$OUT/appcast.xml" >&2 || die "gh release create nie powiodło się"
    "$GH" release download "v$VERSION" --repo "$REPO" --dir "$DL" --pattern "Yascribe-$VERSION.zip" --pattern appcast.xml >&2 \
        || die "nie udało się pobrać szkicu wydania (szkic zostaje: do decyzji użytkownika)"
    [ "$(shasum -a 256 < "$ZIP")" = "$(shasum -a 256 < "$DL/Yascribe-$VERSION.zip")" ] || die "zip w szkicu różni się od lokalnego: NIE publikuję"
    [ "$(shasum -a 256 < "$OUT/appcast.xml")" = "$(shasum -a 256 < "$DL/appcast.xml")" ] || die "appcast w szkicu różni się od lokalnego: NIE publikuję"
    "$GH" release edit "v$VERSION" --repo "$REPO" --draft=false --latest >&2 || die "publikacja nie powiodła się (szkic zostaje)"

    # (9) po publikacji
    [ "$("$GH" api "repos/$REPO/releases/latest" --jq .tag_name)" = "v$VERSION" ] || die "latest ≠ v$VERSION (wydanie opublikowane, sprawdź ręcznie)"
    # Feed `releases/latest/download/…` bywa 404 przez kilkanaście sekund po publikacji (propagacja GitHuba): ponawiamy.
    local tries="${YASCRIBE_FEED_RETRIES:-12}" i=0 same=0
    while [ "$i" -lt "$tries" ]; do
        if [ "$(set +e; $FETCH "$FEED_URL" 2>/dev/null)" = "$(cat "$OUT/appcast.xml")" ]; then same=1; break; fi
        i=$((i + 1)); sleep "${YASCRIBE_FEED_SLEEP:-5}"
    done
    [ "$same" -eq 1 ] || die "feed różni się od lokalnego appcast.xml po $tries próbach (wydanie opublikowane, sprawdź ręcznie)"
    $FETCH "https://github.com/$REPO/releases/download/v$VERSION/Yascribe-$VERSION.zip" >/dev/null || die "zasób zip nie odpowiada (wydanie opublikowane, sprawdź ręcznie)"
    echo "release: v$VERSION opublikowane (build $BUILD, $SHA)" >&2
}
