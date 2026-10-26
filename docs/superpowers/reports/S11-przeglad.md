# Przegląd S11 — E3 (a2a82f6) + E5 (f188934)

**Zakres:** `git diff c1ccf56..HEAD` (E3 = `a2a82f6`, E5 = `f188934`), raport `S11.md`, plan 00 §4, plan 05 §E3/E5.
**Testy:** `scripts/test.sh` → ostatnia linia: `test.sh: 109/109 testów uruchomionych i zaliczonych.` (kod 0). Liczba deklaracji `@Test` w `Tests/` = 109 — zgadza się z raportem i z runbookiem.

**Zgodność kod ↔ plan:** bloki literalne E3 (kroki 1–2, 4–6, (a)–(i)) i E5 krok 1 weszły znak w znak (porównane z planem 05 linia po linii). Kod spoza literali (E5 krok 2 — testy pisane samodzielnie) zgadza się z tabelą luk. Diff planu 05 to wyłącznie `- [ ]` → `- [x]`; diff runbooka zgodny z E5 krokiem 4 (S11 → `106, po E5: 109`, S12/S14/S15/S16/S18 → `109`, dopisek `> +3 po E5`). Odstępstwa 1–5 z raportu potwierdzone w diffie. Zapisy `run()` (input.json, chunks/, transcript.json, run.json) wszystkie w `sesja/runs/<runID>/`; walidacja `runID` idzie przed jakimkolwiek zapisem. Surowe bajty diffu skanowane pod literałami-podobnymi-do-tajemnic: tylko stałe UUID `000…001`/`000…002` i kontekst testowy (`key: "k"` w fixture, poza diftem) — nic kluczopodobnego.

**Mutacje — powtórzone w przeglądzie (każda osobno, potem `git checkout --`; drzewo po wszystkich czyste):**

| # | Mutacja | Test | Wynik |
|---|---|---|---|
| 1 | `requestCount: 0, audioSecondsSent: 0` w zapisie `RunMetadata` | `progressReachesOneAndMetadataCarriesTheSnapshot` | ✘ RunnerTests:88 (`requestCount`), :90 (`audioSecondsSent`) |
| 2 | usunięcie `, saved.chunk == item.chunk` | `interruptedRunResumesWithoutPayingAgain` | ✘ RunnerTests:71 (`third.requests == 1`) |
| 3 | `if let host = summary.hostTime(…), false` | `sessionTimeComesFromClockAnchorsNotJustTheOffset` | ✘ RunnerTests:217 |
| 4 | `utteranceGap = .infinity` | `utteranceBreaksOnlyAtTheGap` | ✘ RunnerTests:230 |
| 5 | `case .english: return nil` | `polishInEnglishMeetingIsFlagged` | ✘ LanguageGuardTests:30 |
| 6 | `correlationThreshold = 0.8 → 1.1` (mutacja E3 krok 8) | `crosstalkFromSpeakersIsDroppedBeforeASR` | ✘ RunnerTests:140 (`allSatisfy { $0.speaker == .them }`) |

Wszystkie sześć czerwieni tam, gdzie mówi raport — testy luk faktycznie łapią swoje mutacje.

## Uwagi

### 1. `RunInput` nie obejmuje konfiguracji `CrosstalkFilter`, choć deklaruje kompletność
- **Plik:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift`
- **Miejsce:** `RunInput` (linie 11–17, komentarz „Wszystko, od czego zależą zapisane okna"), zapis/porównanie `input.json` (linie 80–86); wywołanie `crosstalk.keep(…)` (linie 98–101)
- **Problem:** granice okien zależą teraz też od `crosstalk.correlationThreshold` i `maxLagSeconds` — to pola publiczne, konfigurowalne przez `TranscriptionRunner.init(…, crosstalk:)`. `RunInput` zawiera migawkę, `gate.config`, `maxChunkSeconds` i ramki ścieżek, ale nie parametry filtra. Wznowienie z innym filtrem przechodzi bez `inputMismatch` i miesza w jednym `runID` okna policzone z dwóch konfiguracji (inna liczba przesłuchów → inne regiony → inne granice okien). Komentarz „Wszystko, od czego zależą zapisane okna" jest więc nieprawdziwy dla nowego składnika.
- **Propozycja:** dodać do `RunInput` progi filtra (np. `crosstalkThreshold: Double`, `crosstalkMaxLagSeconds: Double`) i porównywać je w `guard saved == input`; alternatywnie — jeśli filtr ma być stałą sesji — zawęzić komentarz i udokumentować, że niestandardowy `crosstalk` unieważnia wznawianie.

### 2. Sprzątanie w `test.sh` kasuje katalogi równoległego, żywego przebiegu testów
- **Plik:** `scripts/test.sh`
- **Miejsce:** linia 25 (`find … -exec rm -rf {} +`)
- **Problem:** `find` nie rozróżnia katalogów po poprzednich przebiegach od katalogów przebiegu, który właśnie trwa. Dwa równoległe `scripts/test.sh` (albo `scripts/test.sh` obok ręcznego `swift test` czy sesji z `mn-tr-*` w trakcie) → drugi start usuwa katalogi pierwszego w trakcie zapisu; testy padają na błędach I/O, nie na swoim temacie. Sprzątanie jest celowo „na początku przebiegu", ale bez ograniczenia wiekiem nie jest bezpieczne przy współbieżności (raport S11 też odnotowuje 45 katalogów żywego przebiegu w `$TMPDIR`).
- **Propozycja:** dodać `-mmin +60` (katalogi starsze niż godzina) albo inny próg wieku; tanie i nie rusza bieżącego przebiegu ani ręcznych `mn-s2`, `mn-corpus-*`.

### 3. `OUT="$(mktemp)"` wycieka przy każdym przebiegu poza pełnym zielonym
- **Plik:** `scripts/test.sh`
- **Miejsce:** linia 26 (`mktemp`), linia 44 (`rm -f "$OUT"`), wyjścia wcześniejsze: linie 32 (exit 3), 35 (exit `$STATUS`), 39 (exit 0 przy `--filter`)
- **Problem:** plik wyniku jest sprzątany wyłącznie na ścieżce pełnego przebiegu z zgodną liczbą testów. Przy `--filter`, przy padniętym teście (exit 1 — m.in. przy wszystkich mutacjach z przeglądu) i przy błędzie pluginu (exit 3) plik zostaje w `$TMPDIR` na zawsze. E5 zamyka wycieki katalogów `mn-*`, ale tego pliku nie obejmuje żaden wzorzec — cel E5 („sprzątanie katalogów tymczasowych") nie jest tu domknięty. Zachowanie jest starsze niż S11, ale zostało w zakresie zadania.
- **Propozycja:** `trap 'rm -f "$OUT"' EXIT` po `mktemp` (sprząta przy każdym wyjściu), albo rozszerzyć wzorzec sprzątania o pliki `tmp.*` starsze niż godzina.

### 4. Komentarz wzorca sprzątania obiecuje więcej, niż wzorzec robi
- **Plik:** `scripts/test.sh`
- **Miejsce:** linie 24–25 (komentarz „Wzorzec omija mn-s2, mn-corpus-* itp." + regex)
- **Problem:** sprawdzone empiricznie na katalogach próbnych: regex dopasowuje `mn-corpus-<UUID>` (prefiks `[a-z]+-` zjada `corpus-`) — czyli nie omija `mn-corpus-*`, tylko omija sufiksy nie-UUID (planowe `/tmp/mn-corpus-1` faktycznie przeżywa). Odwrotnie: `mn-Xy-<UUID>`, `mn-a-b-<UUID>` i UUID z małymi hexami nie są sprzątane (wyciek, nie nad-usuwanie). Dziś wszystkie katalogi testowe to `mn-`, `mn-fit-`, `mn-tr-`, `mn-session-` + `UUID().uuidString` (wersaliki) — wszystkie sprzątane, wszystkie ręczne (`mn-s2`, `mn-s5`, `mn-mic-a`) nietknięte, więc skutku błędnego brak. Precyzja komentarza myli jednak przy ocenie bezpieczeństwa regexu (punkt 4 recenzji).
- **Propozycja:** poprawić komentarz na „omija sufiksy inne niż UUID" albo zacieśnić wzorzec o wykluczenie `corpus-` (`mn-((?!corpus)[a-z]+-)?…` nie w ERE — wtedy lepiej wymienić dozwolone prefiksy: `mn-(fit-|tr-|session-)?UUID`).

### 5. Komentarz `tracks(in:)` nie opisuje nowej reguły dla martwego `mic_aec`
- **Plik:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift`
- **Miejsce:** linia 64 (doc comment) vs linie 69–71 (nowy warunek `aecFailed`)
- **Problem:** komentarz mówi „'ja' = mikrofon po AEC, a gdy go brak — surowy", a po E3 obowiązuje też trzeci przypadek: `mic_aec` obecny, ale z zapisaną awarią (`failure != nil`) → bierzemy `mic_raw`. Komentarz (i opis w spec §3, jeśli go powtarza) zostaje w tyle za zachowaniem.
- **Propozycja:** „…mikrofon po AEC, a gdy go brak albo gdy jego ścieżka zanotowała awarię — surowy".

### 6. Brak wersji formatu `run.json` / `input.json` — starsze zapisy przestają się dekodować
- **Plik:** `Sources/MeetNotesTranscription/Transcript.swift` + `Sources/MeetNotesProviders/Stores.swift`
- **Miejsce:** `RunSnapshot` (linie 53–85 — nowe obowiązkowe `preset`), `JSONFile.load` (Stores:38–41), `TranscriptionRunner.run` linia 82
- **Problem:** dodanie obowiązkowego `preset: Preset` zmienia kształt JSON-a `run.json` (przez `RunMetadata.snapshot`) i `input.json`. Pliki zapisane przed E3 (devdata ze wcześniejszych sesji, patrz plan 00 §4) nie dekodują się, a `JSONFile.load` przy błędzie dekodowania **rzuca** (zwraca `default` tylko przy braku pliku) — czytanie starego runu skończy się surowym `DecodingError` bez wskazania przyczyny. W fazie 1 brak w drzewie czytnika `run.json`, więc dziś bez skutku; ale to artefakt sesji użytkownika i wejście przyszłej powłoki (D). Żadne z pól (`RunSnapshot`, `RunInput`, `RunMetadata`) nie ma wersji formatu.
- **Propozycja:** dodać `formatVersion: Int` do `RunMetadata`/`RunInput` i przy dekodowaniu starej wersji albo migrację (brak `preset` → odtworzenie z `presetID`/`presetName`), albo czytelny komunikat „run zapisany przed E3 — przelicz od nowa".
