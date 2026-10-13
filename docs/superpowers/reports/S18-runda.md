# S18-runda — poprawki po przeglądzie S18 (jedna runda, bez re-checku)

**Wejście:** `docs/superpowers/reports/S18-przeglad.md` (§1 BLOKUJĄCE #1, §2 poz. 1, §6 Q3), odpowiedzi w
`BACKLOG.md` („Aneks S18"). HEAD przed sesją: `b453e7d` (zlecenie mówiło `c187638`; nad nim jest jeszcze
commit runbooka `b453e7d` — tylko dokumentacja, kodu nie dotyka). Testy przed: 109/109.
Aplikacja nieuruchamiana (GUI); `swift build --product MeetNotesApp` → `Build complete!` (C się kompiluje —
`swift test` nie buduje targetu aplikacji).

## A) Test bramki „model i język żądań = migawka"

- **Zmiana:** `Tests/MeetNotesTranscriptionTests/RunnerTests.swift:110-119` — `requestsCarryTheSnapshotModelAndLanguage`:
  przebieg 300 s sesji, stub `SnapshotRecordingASR` (`RunnerTests.swift:142-158`) dekoduje `httpBody` każdego
  `URLRequest` i zapisuje `model`/`language`; asercje: żądania były (`!sent.isEmpty`) i każde
  `== Sent(model: snap.model, language: snap.language.rawValue)` — pola `RunSnapshot` użytej w przebiegu.
  Stub odpowiada przez `ListeningASR` (bez zmian w `SessionFixtures.swift`).
- **Mutacja:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift:122-123` →
  `model: "MUTANT-NOT-THE-SNAPSHOT", language: nil` (zmieniona linia 123, reszta bez zmian).
- **Komenda:** `scripts/test.sh` → kod 1;
  `✘ Test requestsCarryTheSnapshotModelAndLanguage() recorded an issue at RunnerTests.swift:118:5`
  (także `✘ resumeSendsTheSnapshotFromInputJSON()` na `:139`). Ostatnia linia test.sh:
  `  - MeetNotesTranscriptionTests (Swift Testing)` (podsumowanie: `✘ Test run with 34 tests in 0 suites failed … with 2 issues.`).
- **Cofnięcie:** `cp` pliku do `/tmp/TR.swift.bak` przed mutacją, przywrócenie z kopii; `shasum` przed i po
  identyczny (`f0a88b31…`), `git diff` pliku pusty.

## B) Test „resume wysyła dokładnie migawkę z input.json"

- **Zmiana:** `Tests/MeetNotesTranscriptionTests/RunnerTests.swift:121-140` — `resumeSendsTheSnapshotFromInputJSON`:
  1. przebieg `r1` pada na oknach ≥ 2 (jak w `interruptedRunResumesWithoutPayingAgain`), test czyta migawkę
     **z pliku** `runs/r1/input.json` (`saved`);
  2. drugi przebieg `r1` z **bieżącym presetem** o innym modelu (`other/model`) i języku (`.english`):
     nic wysłanego nie może mieć innych pól niż `saved` (dziś: `inputMismatch`, zero żądań);
  3. wznowienie jak `AppModel.resume` (`snapshot: saved`): brakujące okna wychodzą (`!sent.isEmpty`)
     i każde żądanie `== saved.model / saved.language`.
- **Zakres (uczciwie):** `TranscriptionRunner` sam nie czyta migawki z `input.json` — porównuje ją z argumentem
  (`TranscriptionRunner.swift:84-88`), a czytanie dla wznowienia leży w `AppModel.resume`
  (`AppModel.swift:267-275`, poza testTargetem). Test pinuje więc kontrakt runnera, na którym stoi ścieżka
  wznowienia: „drugi przebieg tego runID wysyła migawkę z `input.json` albo nic". Gdyby `AppModel.resume`
  podał bieżący preset zamiast `input.snapshot`, runner odmówi (krok 2 testu); samej linii w `AppModel`
  test nie obejmuje (STRUKTURALNE #1).
- **Mutacja:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift:84-88` (blok `if let saved … guard saved == input …
  else { save }`) → jedna linia `try JSONFile.save(input, to: dir.input)` — wejście/migawka z argumentu
  wygrywa z `input.json`.
- **Komenda:** `scripts/test.sh` → kod 1;
  `✘ Test resumeSendsTheSnapshotFromInputJSON() recorded an issue at RunnerTests.swift:134:5: Expectation failed: refused.sent.allSatisfy { $0 == expected }`
  oraz `:138:5` (`!resumed.sent.isEmpty`); czerwony także istniejący `resumingWithADifferentPresetIsRefused`.
  Ostatnia linia test.sh: `  - MeetNotesTranscriptionTests (Swift Testing)` (podsumowanie: `✘ Test run with 34 tests in 0 suites failed … with 4 issues.`).
- **Cofnięcie:** jak w A (kopia → przywrócenie, `shasum` `f0a88b31…` identyczny, `git status` bez tego pliku).

## C) `AppModel.load()` bez utraty danych konfiguracyjnych

- **Zmiana:** `Sources/MeetNotesApp/AppModel.swift:78-102`. Lokalna funkcja `read(_:_:)` — osobny `do/catch`
  na każdy z czterech plików (`providers.json`, `presets.json`, `settings.json`, `probe-cache.json`).
  Przy błędzie odczytu/dekodowania: `moveItem` na `<nazwa>.corrupt-<yyyyMMdd-HHmmss>` w tym samym katalogu
  (jeden znacznik czasu na całe `load()`), domyślna wartość tylko dla tego pliku, wpis do `lastError`:
  `Couldn't read presets.json (moved to presets.json.corrupt-20261013-142501): <błąd>` (kilka plików → linie
  rozdzielone `\n`). `load()` woła `save()` nigdzie, a przeniesienie dzieje się w `load()` (z `init`), więc
  przed każdym `save()`. `save()`, format plików i ścieżka zdrowych plików bez zmian (brak pliku = domyślna,
  jak dotąd — `JSONFile.load` nie rzuca).
- **Znany sufit (`ponytail:` w kodzie):** jeśli samo przeniesienie się nie uda (np. brak praw do katalogu),
  `lastError` mówi „couldn't move it aside", ale najbliższy `save()` nadpisze ten plik — blokada zapisu
  per plik dopiero, gdy to się zdarzy (wymagałaby zmiany `save()`, poza zakresem).
- **Sprawdzenie ręczne (orkiestrator), krok po kroku:**
  1. Zamknij aplikację. `ls .devdata/` — zanotuj `providers.json`, `presets.json`, `settings.json`, `probe-cache.json`;
     zrób kopię: `cp -R .devdata /tmp/devdata-bak`.
  2. Zepsuj cache sondy: `printf '{zepsute' > .devdata/probe-cache.json`.
  3. `scripts/run.sh`.
  4. Oczekiwane: komunikat błędu z `Couldn't read probe-cache.json (moved to probe-cache.json.corrupt-…)`;
     w Settings dostawcy są, w Presets presety są (a nie puste listy).
  5. Wywołaj zapis (np. sonda albo zmiana w Settings), zamknij aplikację.
  6. `ls .devdata/` → jest `probe-cache.json.corrupt-<data>` z treścią `{zepsute`; `probe-cache.json` = świeży
     (pusty) cache; `diff /tmp/devdata-bak/presets.json .devdata/presets.json` i to samo dla `providers.json`
     → bez różnic (settings mogą się różnić tylko o to, co zmieniłeś w kroku 5).
  7. Sprzątanie: `rm .devdata/probe-cache.json.corrupt-*` albo przywrócenie z `/tmp/devdata-bak`.

## Podsumowanie

- Zmienione pliki: `Sources/MeetNotesApp/AppModel.swift`, `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`,
  ten raport. `BACKLOG.md`, plany, speki — nietknięte. Kod runnera — bez zmian (tylko mutacje, cofnięte).
- Testy: 109 → 111 (+2: A i B).

test.sh: 111/111 testów uruchomionych i zaliczonych.
