# Faza 1.5 — poprawki P1, P2, P4 z przeglądu całości

2026-10-19, Sonnet. Źródło: `reports/F15-przeglad-calosci.md`, sekcja „Do poprawy” (P3 — dokumenty — osobno, Haiku).
Gałąź `claude/gracious-torvalds-37592c`, wycięta z `faza15` (`02ca8ae`) i przesunięta fast-forwardem o dwa commity
raportu przeglądu (`157d94b`). Nie scalone do `faza15`/`master`, bez pusha i tagów.

`scripts/test.sh` na końcu: `test.sh: 355/355 testów uruchomionych i zaliczonych.` (było 353; +2 nowe testy), `check-bundle: OK`.

## Tabela

| Poprawka | Commit | Test | Mutacja | Padający test |
|---|---|---|---|---|
| P1 `RecordingsMove.run`, `commit` rzuca | `ff2a229` | nowy `moveDeletesNothingWhenCommitThrows` (`RecordingsTests.swift`) | przed `do { try await commit() }` dopisana pętla kasująca stare wpisy | `moveDeletesNothingWhenCommitThrows` (`files(old) == before`); poza tym `moveCopiesVerifiesThenDeletes`, `moveDeletesNothingWhenVerificationFails` |
| P2 `RunDirectory.latestRunID` | `e42c6a8` (+ BACKLOG `2f9f07a`) | nowy `retentionIgnoresCliRunsWhenAppRunHasGaps`; rozszerzony `latestRunIgnoresTheNotesDirectory` (`debug`, `notes.txt`) | stary filtr `isValid(runID:)` | `retentionIgnoresCliRunsWhenAppRunHasGaps` (4 asercje: `latestRunID == run1`, `!transcriptionFinished`, `purged.isEmpty`, audio zostaje), `latestRunIgnoresTheNotesDirectory` |
| P4 tiki co 1 s w `OfferDetectorTests` | `ed629eb` (+ BACKLOG `165e00c`) | 6 poprawionych: `manualStopSilencesAutoStartForTheSameCall`, `manualStopDuringAMicBlipStaysQuiet`, `dismissedOfferStaysQuietForTheWholeMicSession`, `dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp`, `ignoredAppsNeverOffer`, `unknownAppsNeverOffer` | (A) bez `mutedFamilies.formUnion(lastInput.keys)` | `manualStopDuringAMicBlipStaysQuiet`, `manualStopSilencesAutoStartForTheSameCall` (+ `afterManualStopANewCallOffersAgain`) |
| P4 | — | — | (B) bez `mutedFamilies.insert(f)` w `dismiss()` | **żaden z poprawionych** — patrz „STOP” niżej; padają `dismissedOfferReturnsForANewMicSession` i `micSessionEndsAtExactlyReleaseSeconds` |

Wszystkie mutacje cofnięte `git checkout <plik>`; po każdej `git status` czysty. Wszystkie padnięcia są na asercjach
(`Expectation failed`), nie na budowaniu.

## Odstępstwa od opisu (do decyzji użytkownika)

**STOP 1 — mutacja B (P4) nie pada na poprawionych testach.** Usunięcie `mutedFamilies.insert(f)` w `dismiss()` nie
zmienia zachowania `dismissedOfferStaysQuietForTheWholeMicSession` ani `…AcrossHelperProcessesOfTheSameApp`, także przy
tikach co 1 s: po `dismiss()` kolejne `step` liczą tę samą ofertę co `current`, więc `step` nie zwraca żadnej akcji
(`.show` tylko przy zmianie oferty), a `.hide` nie jest `isOffering`. Wyciszenie rodziny zmienia obserwowalne zachowanie
dopiero, gdy oferta zniknie i wróci w tej samej sesji mikrofonu — tego pilnują `dismissedOfferReturnsForANewMicSession`
(blip 10 s, t0+111…200) i `micSessionEndsAtExactlyReleaseSeconds`, oba już z tikami co 1 s i niezmienione. Czyli
bramka `dismiss` ma strażnika, ale nie są nim testy z listy P4. Nic nie dopisywałem „na ślepo”. Do wyboru: zostawić (bramka
pokryta), albo dopisać do obu testów `dismissed…` krok, który zmusza ofertę do zniknięcia i powrotu (np. krótki blip
mikrofonu poniżej `releaseSeconds` w trakcie godziny).

**Uwaga 2 — P1: przegląd twierdził, że żaden test nie woła `commit`, który rzuca.** `moveCopiesVerifiesThenDeletes`
już to robi (`{ throw NoSave() }`) i pada przy mutacji „kasuj przed `commit`”. Nowy test dokłada to, czego tamten nie
sprawdza: komunikat `Failure` zawiera „Nothing was deleted” oraz zniknięcie folderu celu, gdy przebieg sam go utworzył
(tamten test startuje z folderem już istniejącym). Luka była węższa, niż opisano.

**Uwaga 3 — P2: skutki wzorca.**
- Fikstury `2026-10-14-1000` itp. w `RecordingsTests.swift` i `SearchAndLayoutTests.swift` nie pasują do wzorca
  `AppModel.sessionName`; zamieniłem je na `2026-10-01T10-00-00Z-aaaa` / `…-bbbb` (stałe `run1`/`run2`). Testy
  `Transcription*` używają `r1`, ale nie wołają `latestRunID`.
- Domyślny `runID` CLI (`ISO8601…`, `2026-10-14T10-00-00Z` bez `-xxxx`) też nie pasuje, więc jest pomijany tak samo jak
  `--run debug`. To zgodne z poleceniem (tylko wzorzec aplikacji); dla sesji z samym przebiegiem z CLI `latestRunID` zwróci
  `nil`, a retencja zostawi audio (kierunek bezpieczny).
- `isValid(runID:)` bez zmian (CLI z niego korzysta).

**Uwaga 4 — incydent proceduralny (bez skutku w repo).** Przy P2 pierwszy `git commit` nie przeszedł (zsh nie rozbił
zmiennej ze ścieżkami), a następny `git checkout` mutacji cofnął niezacommitowaną poprawkę. Przywróciłem ją, commit
zrobiłem z jawnymi ścieżkami, a mutację powtórzyłem na zacommitowanym stanie — wyniki w tabeli pochodzą z tego powtórzenia.

## Zakres zmian

- `Tests/MeetNotesNotesTests/RecordingsTests.swift`: +2 testy, stałe `run1`/`run2`.
- `Tests/MeetNotesNotesTests/SearchAndLayoutTests.swift`: nazwy przebiegów wg wzorca, + `debug` i `notes.txt`.
- `Sources/MeetNotesTranscription/TranscriptionRunner.swift`: `latestRunID` filtruje regexem `^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z-[0-9a-f]{4}$`.
- `Tests/MeetNotesMeetingsTests/OfferDetectorTests.swift`: 6 testów z tikami co 1 s.
- `docs/superpowers/BACKLOG.md`: odhaczone `latestRunID` (sekcja T5, `e42c6a8`) i „cisza przez godzinę” (`ed629eb`).
