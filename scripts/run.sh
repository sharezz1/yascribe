#!/bin/bash
# Buduje i uruchamia aplikację z danymi w .devdata/ (czysto na dysku, spec rdzenia §8).
set -euo pipefail
cd "$(dirname "$0")/.."
# Druga instancja nagrywałaby do tego samego .devdata, a bundle.sh skasowałby
# paczkę spod działającej — przerywamy przed budową.
if pgrep -x YascribeApp >/dev/null; then
    echo "run.sh: YascribeApp już działa (PID $(pgrep -x YascribeApp | xargs)) — zamknij ją i uruchom ponownie" >&2
    exit 1
fi
APP="$(scripts/bundle.sh)"
[ -d "$APP" ] || { echo "run.sh: bundle.sh nie zwrócił katalogu paczki: \"$APP\"" >&2; exit 1; }
mkdir -p .devdata
open -n --env YASCRIBE_DATA_DIR="$PWD/.devdata" "$APP"
# open oddaje zlecenie LaunchServices i wychodzi z 0 — sprawdzamy, czy proces wstał.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x YascribeApp >/dev/null && exit 0
    sleep 0.5
done
echo "run.sh: YascribeApp nie działa 5 s po open (nie wystartowała albo od razu się zakończyła)" >&2
exit 1
