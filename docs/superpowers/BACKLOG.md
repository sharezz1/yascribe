# BACKLOG — kosmetyki i drobiazgi (bez rundy poprawek)

Zasada (decyzja użytkownika, 2026-10-12): uwagi kosmetyczne (komentarze, notki, nazwy, styl testów)
trafiają tutaj i czekają; rundy poprawek dotyczą wyłącznie błędów funkcjonalnych i brakujących
testów na bramkach. **Przed S18 jedna sesja K czyści ten plik.**

## Otwarte
- [ ] `scripts/test.sh` — linia `rm -f "$OUT"` po `trap` jest redundantna (nieszkodliwa) — sprzątnąć przy okazji. *(przegląd S11 r2)*
- [ ] `scripts/test.sh` — wzorzec sprzątania `mn-([a-z]+-)?UUID` złapie też hipotetyczny `mn-corpus-<UUID>` (komentarz to opisuje; ewentualne zacieśnienie wzorca — kosmetyka). *(przegląd S11 r2)*
- [ ] CLI `transcribe`: klient powstaje przed sprawdzeniem `--language` — kolejność błędów zależy od tego, który argument jest zły (K: uwaga, nie błąd). *(S12)*
- [ ] CLI `--shape` z literówką po cichu przechodzi na `audioTranscriptions` (tak mówi plan; K proponuje zamiast tego kod 64) — **propozycja zmiany zachowania, czeka na decyzję użytkownika**. *(S12)*

## Zapisane (dla kroniki)
- 2026-10-12 — `RunError.inputMismatch`: komentarz + „progi przesłuchu" → `0dd84ef`.
- 2026-10-12 — test przesłuchu: zakres z sekund + `#expect(mic.count >= …)` → `0dd84ef`.
