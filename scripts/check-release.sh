#!/bin/bash
# Bramki release.sh na atrapach (T6): bez sieci, kluczy, prawdziwej budowy i bez rekurencyjnego test.sh.
# Repo testowe: tymczasowy klon z lokalnym bare „origin" (git ls-remote działa offline).
set -uo pipefail
cd "$(dirname "$0")/.."
SRC="$PWD"
T="$(mktemp -d "${TMPDIR:-/tmp}/mn-relcheck.XXXXXX")"
trap 'rm -rf "$T"' EXIT
FAILS=0
CASES=0

ok()   { CASES=$((CASES + 1)); }
fail() { CASES=$((CASES + 1)); FAILS=$((FAILS + 1)); echo "check-release: FAIL $1" >&2; }

# Atrapy wykonawców (bez żadnej sieci i kluczy).
mkdir -p "$T/fake"
cat > "$T/fake/test" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$T/fake/bundle" <<'EOF'
#!/bin/bash
# Składa atrapę paczki z kluczami wersji; FAKE_BUILD udaje odziedziczone YASCRIBE_BUILD.
APP="$FAKE_DIR/app/Yascribe.app"
rm -rf "$FAKE_DIR/app"; mkdir -p "$APP/Contents"
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "${FAKE_VERSION:-$(tr -d '[:space:]' < VERSION)}" "$APP/Contents/Info.plist"
plutil -insert CFBundleVersion -string "${FAKE_BUILD:-$(git rev-list --count HEAD)}" "$APP/Contents/Info.plist"
plutil -insert SUFeedURL -string "https://example.invalid/appcast.xml" "$APP/Contents/Info.plist"
echo "$APP"
EOF
cat > "$T/fake/identity" <<'EOF'
#!/bin/bash
[ "${FAKE_IDENTITY:-ok}" = "ok" ]
EOF
cat > "$T/fake/sign" <<'EOF'
#!/bin/bash
[ "${FAKE_SIGN:-ok}" = "empty" ] && exit 0
echo "sparkle:edSignature=\"test-fake-sig\" length=\"$(stat -f %z "$1")\""
EOF
cat > "$T/fake/fetch" <<'EOF'
#!/bin/bash
case "$1" in
    *appcast.xml)
        if [ -f "$FAKE_DIR/feed.published" ]; then cat "$FAKE_DIR/feed.published"
        elif [ -f "$FAKE_DIR/feed" ]; then cat "$FAKE_DIR/feed"
        else exit 22; fi ;;
    *) exit 0 ;;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/bin/bash
# Dziennik wywołań i symulacja szkicu wydania w katalogu tymczasowym.
echo "$*" >> "$FAKE_DIR/gh.log"
case "$1 $2" in
    "release create") TAG="$3"; mkdir -p "$FAKE_DIR/store/$TAG"
        for a in "$@"; do case "$a" in */Yascribe-*.zip|*/appcast.xml) cp "$a" "$FAKE_DIR/store/$TAG/";; esac; done ;;
    "release download") TAG="$3"; DIR=""; while [ "$#" -gt 0 ]; do [ "$1" = "--dir" ] && DIR="$2"; shift; done
        cp "$FAKE_DIR/store/$TAG/"* "$DIR/"
        [ "${FAKE_GH_TAMPER:-0}" = "1" ] && echo tampered >> "$DIR/Yascribe-"*.zip ;;
    "release edit") TAG="$3"; echo "$TAG" > "$FAKE_DIR/latest"; cp "$FAKE_DIR/store/$TAG/appcast.xml" "$FAKE_DIR/feed.published" ;;
    "api repos/sharezz1/yascribe/releases/latest") cat "$FAKE_DIR/latest" ;;
esac
exit 0
EOF
chmod +x "$T"/fake/*

# Świeże repo testowe: bare origin + klon z jednym commitem na master (z kopiami skryptów wydania).
mkrepo() {
    local n="$1"; W="$T/$n/work"; export FAKE_DIR="$T/$n/fake-state"
    mkdir -p "$T/$n" "$FAKE_DIR"
    git init -q --bare -b master "$T/$n/origin.git"
    git init -q -b master "$W"
    git -C "$W" config user.email "test@example.invalid"; git -C "$W" config user.name test
    git -C "$W" remote add origin "$T/$n/origin.git"
    mkdir -p "$W/scripts" "$W/Resources"
    cp "$SRC"/scripts/release.sh "$SRC"/scripts/release-lib.sh "$SRC"/scripts/make-appcast.sh "$W/scripts/"
    echo "0.1.0" > "$W/VERSION"
    plutil -create xml1 "$W/Resources/Info.plist"
    plutil -insert SUPublicEDKey -string "test-fake-public-key" "$W/Resources/Info.plist"
    git -C "$W" add scripts VERSION Resources; git -C "$W" commit -q -m "init"
    git -C "$W" push -q origin master
}

# Uruchamia release.sh w repo testowym z atrapami; wynik: RC i dziennik gh.
run_release() {
    ( cd "$W" && env FAKE_DIR="$FAKE_DIR" YASCRIBE_TEST_CMD="$T/fake/test" YASCRIBE_BUNDLE_CMD="$T/fake/bundle" \
        YASCRIBE_SIGN_UPDATE="$T/fake/sign" YASCRIBE_GH="$T/fake/gh" YASCRIBE_FETCH="$T/fake/fetch" \
        YASCRIBE_IDENTITY_CHECK="$T/fake/identity" "$@" scripts/release.sh "${ARGS[@]}" ) > "$T/out.log" 2>&1
    RC=$?
}
gh_called() { [ -f "$FAKE_DIR/gh.log" ]; }

expect_refused() { # nazwa; reszta: wywołanie jest przygotowane przez wołającego (RC i brak gh)
    if [ "$RC" -ne 0 ] && ! gh_called; then ok; else fail "$1 (RC=$RC, gh wołany: $(gh_called && echo tak || echo nie))"; fi
}

ARGS=(0.1.0 --dry-run)

mkrepo dirty; echo x > "$W/dirty.txt"; run_release; expect_refused dirty-tree-rejected
mkrepo branch; git -C "$W" checkout -q -b feature; run_release; expect_refused wrong-branch-rejected
mkrepo version; ARGS=(0.2.0 --dry-run); run_release; expect_refused version-mismatch-rejected; ARGS=(0.1.0 --dry-run)
mkrepo unpushed; echo y > "$W/y.txt"; git -C "$W" add y.txt; git -C "$W" commit -q -m local; run_release; expect_refused head-not-pushed-rejected
mkrepo adhoc; run_release FAKE_IDENTITY=adhoc; expect_refused adhoc-signature-rejected
# feed z build równym bieżącemu (granica: `>` nie `>=`) i większym od bieżącego
for published in 1 999; do
    mkrepo "build$published"
    echo "<rss xmlns:sparkle=\"x\"><channel><item><sparkle:version>$published</sparkle:version></item></channel></rss>" > "$FAKE_DIR/feed"
    run_release; expect_refused "non-increasing-build-rejected (feed=$published)"
done
mkrepo bundlever; run_release FAKE_BUILD=999; expect_refused bundle-version-mismatch-rejected
mkrepo nosig; run_release FAKE_SIGN=empty; expect_refused missing-signature-rejected

# puste źródło feedu (np. 404 przy prywatnym repo) nie wyłącza kontroli, gdy zdalnie są już wydania v*
mkrepo emptyfeed; git -C "$W" tag v0.0.9; git -C "$W" push -q origin v0.0.9; run_release; expect_refused empty-feed-with-existing-releases-rejected

# appcast: poprawny XML z podpisem i długością zgodną z zipem (dry-run zachowuje wyniki w YASCRIBE_OUT_DIR)
mkrepo appcast; OUT="$T/appcast/out"
run_release YASCRIBE_OUT_DIR="$OUT"
LEN="$(stat -f %z "$OUT/Yascribe-0.1.0.zip" 2>/dev/null || echo -1)"
if [ "$RC" -eq 0 ] && ! gh_called && xmllint --noout "$OUT/appcast.xml" 2>/dev/null \
    && grep -q 'sparkle:edSignature="test-fake-sig"' "$OUT/appcast.xml" && grep -q "length=\"$LEN\"" "$OUT/appcast.xml" \
    && grep -q '<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>' "$OUT/appcast.xml"; then ok; else fail "appcast-is-valid-xml-with-signature (RC=$RC)"; fi

# kolejność: create --draft --target <SHA> → download → edit --draft=false → feed i latest
mkrepo order; ARGS=(0.1.0); run_release
SHA="$(git -C "$W" rev-parse HEAD)"; LOG="$FAKE_DIR/gh.log"
L1="$(grep -n "^release create v0.1.0 .*--draft --target $SHA" "$LOG" | head -1 | cut -d: -f1)"
L2="$(grep -n '^release download v0.1.0' "$LOG" | head -1 | cut -d: -f1)"
L3="$(grep -n '^release edit v0.1.0 .*--draft=false' "$LOG" | head -1 | cut -d: -f1)"
if [ "$RC" -eq 0 ] && [ -n "$L1" ] && [ -n "$L2" ] && [ -n "$L3" ] && [ "$L1" -lt "$L2" ] && [ "$L2" -lt "$L3" ]; then ok
else fail "upload-download-validate-publish-order (RC=$RC, linie: ${L1:-?} ${L2:-?} ${L3:-?})"; fi

# publikacja odmówiona, gdy bajty szkicu się różnią
mkrepo tamper; ARGS=(0.1.0); run_release FAKE_GH_TAMPER=1
if [ "$RC" -ne 0 ] && gh_called && ! grep -q 'draft=false' "$FAKE_DIR/gh.log"; then ok; else fail "publish-refused-when-draft-bytes-differ (RC=$RC)"; fi

[ "$FAILS" -eq 0 ] || { echo "check-release: $FAILS z $CASES przypadków nie przeszło" >&2; exit 1; }
echo "check-release: OK ($CASES przypadków)"
