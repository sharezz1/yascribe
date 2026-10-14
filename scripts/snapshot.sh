#!/bin/bash
# Renderuje ekrany aplikacji do PNG w .design/review/ (macos.md §9). Dane: świeży katalog fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=".design/review"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
swift build --product MeetNotesApp >&2
BIN="$(swift build --show-bin-path)/MeetNotesApp"
MEETNOTES_DATA_DIR="$DATA" MEETNOTES_SNAPSHOT_DIR="$OUT" "$BIN"
ls "$OUT"
