#!/bin/bash
# Użycie: scripts/release.sh <wersja> [--dry-run]
# Wydanie dopiero na jawne „wydaj" użytkownika. Cała logika: scripts/release-lib.sh (testowana przez check-release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/release-lib.sh
release_main "$@"
