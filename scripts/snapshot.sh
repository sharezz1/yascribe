#!/bin/bash
# Renderuje oba języki i wyglądy do .design/review/ z osobnych katalogów danych.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/.design/review"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
YASCRIBE_APP="$TMP/Yascribe.app" YASCRIBE_SIGN_IDENTITY=- scripts/bundle.sh >/dev/null
for language in pl en; do
    mkdir -p "$TMP/data-$language" "$OUT/$language"
    find "$OUT/$language" -maxdepth 1 -name '*.png' -delete
    YASCRIBE_DATA_DIR="$TMP/data-$language" YASCRIBE_SNAPSHOT_DIR="$OUT/$language" \
        YASCRIBE_SNAPSHOT_LANGUAGE="$language" "$TMP/Yascribe.app/Contents/MacOS/YascribeApp" \
        -AppleLanguages "($language)"
    find "$OUT/$language" -maxdepth 1 -name '*.png' -exec basename {} \; | LC_ALL=C sort > "$TMP/$language.txt"
    [ -s "$TMP/$language.txt" ] || { echo "snapshot.sh: brak migawek $language" >&2; exit 1; }
    grep -q -- '-light.png$' "$TMP/$language.txt"
    grep -q -- '-dark.png$' "$TMP/$language.txt"
done
cmp "$TMP/pl.txt" "$TMP/en.txt"
cat "$TMP/pl.txt"
