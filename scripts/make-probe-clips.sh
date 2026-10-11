#!/bin/bash
# Generuje nagrania próbne sondy ASR (spec fazy 1, §1.5): „raz, dwa, trzy" po
# polsku (rozdz. 4 daje tę frazę) i „one, two, three" po angielsku, 16 kHz mono,
# i zapisuje je jako base64 w pliku źródłowym. Zasoby SwiftPM odpadają: przy
# ręcznie składanym .app lądują w korzeniu paczki i psują podpis.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
say -v Zosia -o "$T/pl.aiff" "raz, dwa, trzy"
say -v Samantha -o "$T/en.aiff" "one, two, three"
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/pl.aiff" "$T/pl.wav"
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/en.aiff" "$T/en.wav"
OUT=Sources/MeetNotesProviders/ProbeClips+Data.swift
{
  echo "// WYGENEROWANE przez scripts/make-probe-clips.sh — nie edytuj ręcznie."
  echo "extension ProbeClips {"
  echo "    static let polishBase64 = \"$(base64 -i "$T/pl.wav" | tr -d '\n')\""
  echo "    static let englishBase64 = \"$(base64 -i "$T/en.wav" | tr -d '\n')\""
  echo "}"
} > "$OUT"
rm -rf "$T"
echo "zapisano $OUT"
