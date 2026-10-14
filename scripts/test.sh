#!/bin/bash
# Uruchamia testy i sprawdza, że uruchomiło się DOKŁADNIE tyle testów, ile jest
# deklaracji @Test w Tests/. Nigdy nie uruchamiaj gołego `swift test`:
#
# 1. Na Swift 6.4 + samych Command Line Tools silnik budowania niedeterministycznie
#    gubi plugin makr biblioteki Testing ("plugin for module 'TestingMacros' not
#    found") — dlatego ładujemy go jawnie.
# 2. Po takim błędzie następny przebieg potrafi zameldować "Test run with 0 tests
#    ... passed", a inny uruchomił 11 testów z 23 bez żadnego błędu. Zielony wynik
#    bez sprawdzenia liczby testów nie dowodzi niczego (wnioski z forka, rozdz. 1).
#
# Użycie: scripts/test.sh [argumenty dla swift test, np. --filter NazwaTestu]
# Z --filter liczba nie jest sprawdzana (uruchamia się podzbiór).
set -uo pipefail
cd "$(dirname "$0")/.."

TOOLCHAIN_BIN="$(dirname "$(xcrun --find swift)")"
PLUGIN="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ ! -f "$PLUGIN" ]; then
    echo "test.sh: nie ma pluginu makr Testing: $PLUGIN" >&2
    exit 2
fi

# Katalogi testów: mn-[fit-|session-|tr-]<UUID wielkimi literami>, starsze niż godzina. Tylko prefiksy z Tests/
# (nowy prefiks w testach = dopisz tutaj); nagrania jak mn-s2, mn-corpus-1 czy mn-corpus-<UUID> nie pasują.
find -E "${TMPDIR:-/tmp}" -maxdepth 1 -regex '.*/mn-((fit|session|tr)-)?[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' -mmin +60 -exec rm -rf {} + 2>/dev/null
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@" 2>&1 | tee "$OUT"
STATUS=${PIPESTATUS[0]}

if grep -q "TestingMacros' not found" "$OUT"; then
    echo "test.sh: BŁĄD BUDOWANIA pluginu makr — to nie jest wynik testów. Uruchom: rm -rf .build && scripts/test.sh" >&2
    exit 3
fi
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi

for arg in "$@"; do
    case "$arg" in --filter|--skip) echo "test.sh: filtr — liczby testów nie sprawdzam"; exit 0 ;; esac
done

RAN=$(grep -oE 'Test run with [0-9]+ tests' "$OUT" | grep -oE '[0-9]+' | paste -sd+ - | bc)
EXPECTED=$(grep -rhE '^[[:space:]]*@Test' Tests | wc -l | tr -d ' ')
if [ "${RAN:-0}" -ne "$EXPECTED" ]; then
    echo "test.sh: uruchomiono $RAN testów, a w Tests/ jest $EXPECTED deklaracji @Test. Wynik NIEWAŻNY." >&2
    exit 4
fi
scripts/check-bundle.sh || { echo "test.sh: check-bundle nie przeszło (skrypty składania)" >&2; exit 5; }
echo "test.sh: $RAN/$EXPECTED testów uruchomionych i zaliczonych."
