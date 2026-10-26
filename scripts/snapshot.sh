#!/bin/bash
# Renderuje ekrany aplikacji do PNG w .design/review/ (macos.md §9). Dane: świeży katalog fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=".design/review"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
swift build --disable-keychain --product YascribeApp >&2
BIN="$(swift build --disable-keychain --show-bin-path)/YascribeApp"
YASCRIBE_DATA_DIR="$DATA" YASCRIBE_SNAPSHOT_DIR="$OUT" "$BIN"
ls "$OUT"
