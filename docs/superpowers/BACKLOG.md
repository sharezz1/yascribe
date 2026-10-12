# BACKLOG — kosmetyki i drobiazgi (bez rundy poprawek)

Zasada (decyzja użytkownika, 2026-10-12): uwagi kosmetyczne (komentarze, notki, nazwy, styl testów)
trafiają tutaj i czekają; rundy poprawek dotyczą wyłącznie błędów funkcjonalnych i brakujących
testów na bramkach. **Przed S18 jedna sesja K czyści ten plik.**

## Otwarte
- [ ] `scripts/test.sh` — linia `rm -f "$OUT"` po `trap` jest redundantna (nieszkodliwa) — sprzątnąć przy okazji. *(przegląd S11 r2)*
- [ ] `scripts/test.sh` — wzorzec sprzątania `mn-([a-z]+-)?UUID` złapie też hipotetyczny `mn-corpus-<UUID>` (komentarz to opisuje; ewentualne zacieśnienie wzorca — kosmetyka). *(przegląd S11 r2)*
- [ ] CLI `transcribe`: klient powstaje przed sprawdzeniem `--language` — kolejność błędów zależy od tego, który argument jest zły (K: uwaga, nie błąd). *(S12)*
- [ ] `session-from-file`: drugi przebieg w tym samym katalogu pada (`alreadyExists` na `journal.jsonl`) — przy pracy na korpusie każdy plik wymaga świeżego katalogu (albo później `--force`). *(check S12 #7)*
- [ ] CLI `transcribe` ze złym katalogiem sesji → surowy `NSCocoaErrorDomain` (zamiast czytelnego błędu użycia). *(check S12 #9)*
- [ ] CLI `probe`: `--language` bez wartości po cichu daje `nil` (ten sam problem, co `--shape`/`--run` przed S12fix; poza zakresem tamtej rundy). *(K po S12fix)*
- [ ] CLI `transcribe`: baseURL bez schematu (`openrouter.ai/api/v1`) → każde okno pada na `unsupported URL`, a powód widać tylko w `transcript.json` (`failedChunks[].error`); rozważyć walidację adresu z czytelnym błędem. *(S13 live)*

## Zapisane (dla kroniki)
- 2026-10-12 — `RunError.inputMismatch`: komentarz + „progi przesłuchu" → `0dd84ef`.
- 2026-10-12 — test przesłuchu: zakres z sekund + `#expect(mic.count >= …)` → `0dd84ef`.
