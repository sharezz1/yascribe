#!/bin/bash
# Buduje i uruchamia aplikację z danymi w .devdata/ (czysto na dysku, spec rdzenia §8).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(scripts/bundle.sh | tail -1)"
mkdir -p .devdata
open -n --env MEETNOTES_DATA_DIR="$PWD/.devdata" "$APP"
