# S18 — przegląd całej gałęzi `faza1`

**Zakres:** cała gałąź fazy 1 (`git diff master..HEAD`, 88 commitów), ocena stanu kodu na HEAD
(`bfcf36c`) i dokumentacji. Pliki: `Sources/**`, `Tests/**`, `scripts/**`, `Package.swift`,
`Resources/Info.plist`, `docs/superpowers/{plans,specs,reports}`.

**Testy:** `scripts/test.sh` → ostatnia linia: `test.sh: 109/109 testów uruchomionych i zaliczonych.`
(kod 0). Zgodne z runbookiem §2 (S18 = 109).

**Metoda:** kod czytany plik po pliku (wszystkie `Sources/**` i `Tests/**`); bramki sprawdzane
przez odczyt + mutacje (patrz BLOKUJĄCE #1 — mutacja cofnięta, `git status --porcelain` pusty);
literały kluczopodobne sprawdzone na surowych bajtach (`od -c`): to fixture testowe
(`sk-or-v1-abcdef1234`, `sk-or-v1-SECRET123`), nie prawdziwe klucze; hasha w docs sprawdzone
`scripts/check-hashes.sh` (kod 0) oraz ręcznie. `scripts/run.sh` ani aplikacja nie uruchamiane.

**Czego nie zgłaszam (rozstrzygnięte wcześniej):** check S15 #1–#5 zamknięty przez S15fix
(`77e4978`: blokady startu nagrania i transkrypcji, `preset.json` czytany przez `presetFor`,
odtwarzanie bez `try?`, klucz z Keychain bez cichej awarii — potwierdzone na HEAD); check S15
#6–#10 → BACKLOG (pozycje strukturalne i D3); S11 #1–#5 + runda 2 #1–#4 zamknięte przez E6/S16
(`RunInput.crosstalk`, `-mmin +60`, `trap`, komentarze, zakres testu przesłuchu); uwaga o wersji
formatu `input.json` — świadome odłożenie zapisane w planie 05 (linia 779); pozycje BACKLOG-a
(5 D3/odbiór → faza 1.5, 5 strukturalnych → ocena niżej).

---

## 1. BLOKUJĄCE (runda)

1. **Brak testu na bramce „transkrypcja idzie tym samym modelem i językiem co migawka" —
   mutacja przechodzi 109/109.**
   - **Plik:** `Sources/MeetNotesTranscription/TranscriptionRunner.swift:122-123`
     (`client.transcribe(wav:…, model: snapshot.model, language: snapshot.language, shape: snapshot.shape)`).
   - **Dowód (mutacja, cofnięta):** podmieniłem linie 122–123 na
     `model: "MUTANT-NOT-THE-SNAPSHOT", language: nil` (reszta bez zmian) i uruchomiłem
     `scripts/test.sh` → ostatnia linia: `test.sh: 109/109 testów uruchomionych i zaliczonych.`
     (kod 0). Czyli **cała suita jest zielona, gdy żądania ASR idą innym modelem i bez języka**
     niż migawka zapisana w `run.json`.
   - **Dlaczego tak jest:** testy klienta sprawdzają tylko to, co klient dostanie
     (`Tests/MeetNotesProvidersTests/ClientTests.swift:17-31` — język i `timestamp_granularities`),
     a testy runnera sprawdzają wyłącznie **zapisaną** migawkę (`Tests/MeetNotesTranscriptionTests/RunnerTests.swift:84-85`
     — `meta?.snapshot.model/.language`) i blokadę `inputMismatch` przy wznowieniu
     (`RunnerTests.swift:156`). Żaden test nie zagląda do ciała żądania wysyłanego przez
     `TranscriptionRunner` — stuby (`ListeningASR`, `EnglishASR`) ignorują pola `model`/`language`.
   - **Skutek:** bramka z listy BLOKUJĄCYCH („transkrypcja idzie innym modelem/językiem niż
     migawka"; P7 „profil nagrania zawsze podaje język", P12 migawka) nie jest chroniona.
     Regresja typu „wznowienie wysyła bieżący preset zamiast migawki" albo „model z innego pola"
     przeszłaby 109/109 i checki.
   - **Stan kodu na HEAD jest poprawny** (linie 122–123 przekazują pola migawki; `resume` bierze
     migawkę z `input.json`, `AppModel.swift:253-261`). Runda poprawkowa = **dodanie testu**
     (stub z nagrywaniem `model`/`language` z ciała żądania, asercja == pola `RunSnapshot`),
     nie zmiana kodu.
   - Po sprawdzeniu mutację cofnąłem: `git checkout -- Sources/…/TranscriptionRunner.swift`,
     `git status --porcelain` pusty; ponowny pełny przebieg zielony (109/109).

## 2. DO PLANU 1.5

1. `Sources/MeetNotesApp/AppModel.swift:78-88` + `:90-99` — **jeden uszkodzony plik ustawień
   kasuje pozostałe:** `load()` ma jeden blok `do/catch` dla czterech plików, więc odczyt
   (np. `presets.json`) rzucający (`JSONFile.load` rzuca przy uszkodzonym pliku —
   `Sources/MeetNotesProviders/Stores.swift:37-41`, komentarz „nie kasujemy cudzych danych")
   zostawia `settings`/`probeCache` (albo wszystkie cztery) jako **puste domyślne**, a najbliższy
   `save()` (wołany z `SettingsView.swift:48` `onChange`, po każdej sondzie `AppModel.swift:167`,
   `addProvider`, `savePreset`) zapisuje **wszystkie cztery pliki** — czyli podmienia nieodczytane
   pliki pustymi (utrata presetów, ustawień, cache'u sondy; to dane konfiguracyjne, nie sesji —
   dlatego poza kategoriami BLOKUJĄCYCH wg decyzji 2026-10-13, patrz pytanie 2).
2. `Sources/MeetNotesRecording/SystemAudioCheck.swift:24-35` — gdy `tap.start()` rzuci,
   funkcja wraca przed `defer { tap.stop() }`, więc tap procesu i urządzenie zbiorcze utworzone
   w `prepare()` (`SystemTapSource.swift:26-31`, `build()` tworzy je w systemie) nie są niszczone
   (`teardown()` wchodzi tylko przez `stop()`) — każdy nieudany „Test" w setupie zostawia w systemie
   `AudioHardwareCreateProcessTap` + `AudioHardwareCreateAggregateDevice` do końca życia procesu.
3. `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md:106` i
   `docs/superpowers/plans/2026-09-24-faza1-04-powloka-aplikacji.md:1190` (D3 krok 2) — nadal
   zakładają obecność `mic_aec.caf` w każdej sesji („mic_raw i mic_aec z `permissionDenied`"),
   a aplikacja nagrywa tylko `system` + `mic_raw` (`RecordingController.swift:28-29`, decyzja S5,
   korekta w specu rdzenia §2) — kryterium odbioru kroku 2 było nie do spełnienia w tej buildzie.
4. `Sources/MeetNotesApp/SettingsView.swift:25` — `try? model.secrets.get(p.id)` zamienia błąd
   pęku kluczy w etykietę „No key" (użytkownik może sądzić, że klucz zniknął i dodać dostawcę
   ponownie); wystarczy rozróżnić „brak" od „nie odczytano".

## 3. STRUKTURALNE (5 pozycji z BACKLOG-a)

1. **Brak testTargetu aplikacji (`MeetNotesApp`) — rekomendacja: faza 2.** Przebudowa pakietu
   (biblioteka + testTarget) dotyka bramki liczby testów w `scripts/test.sh` i grafu zależności,
   a faza 1.5 ma zamknięty zakres (design + notatka, decyzja 2026-10-13); blokady i `preset.json`
   mają dziś pokrycie ręczne z D3.
2. **Pokrycie skryptów składania w `test.sh` (`bundle.sh`/`run.sh`/`Info.plist`) — rekomendacja:
   faza 1.5.** Tanio (ad-hoc `MEETNOTES_SIGN_IDENTITY=-`, `plutil -lint`, grep kluczy
   `*UsageDescription`), a bramka D1/TCC nie ma dziś żadnego zabezpieczenia przed cichą regresją
   (check S14 #3) — warto ją domknąć przed fazą 2.
3. **`AppModel.reloadSessions()` na MainActorze + `SettingsView.onChange` zapis przy każdym
   znaku — rekomendacja: faza 2.** Czysto wydajnościowe, przy obecnej liczbie sesji niewidoczne
   (BACKLOG), a sensowne przetestowanie wymaga pozycji 1.
4. **`.macOS(15.0)` w `Package.swift` vs `LSMinimumSystemVersion 27.0` — rekomendacja: faza 2.**
   Rozstrzygnięcie wymaga decyzji produktowej o minimalnej wersji i weryfikacji na starszym macOS
   (tej maszyny nie da się zestarzeć); rozjazd jest tolerowany (bramka ostrzejsza od binarki) i nie
   blokuje użycia.
5. **`Info.plist`/TCC — mapowanie process tap na usługi TCC, brak `NSScreenCaptureUsageDescription`
   — rekomendacja: faza 2.** D3 (krok 9: uprawnienia wiszą na podpisie; nagrywanie systemowe
   działa z obecnym plistem) pokazuje, że na macOS 27 obecny zestaw kluczy wystarcza; rozstrzygnięcie,
   której usługi wymaga process tap przy innych wersjach/dystrybucji, bez pomiaru byłoby zgadywaniem.
   Pozycja „TCC — odzyskiwanie odmówionej zgody" (BACKLOG): **faza 2** — potwierdzam.

## 4. FAZA 2 / NIGDY

1. `Sources/MeetNotesRecording/CoreAudioDevices.swift:34` — `uid(of:)` używa `takeRetainedValue()`
   dla obiektu CF z reguły Get (+0), teoretycznie przepełnione zwolnienie. **Nigdy (przy tym
   sprzęcie):** pomiar — 400 000 zapytań UID w pętli (także z `autoreleasepool`) bez awarii
   w obu wariantach („BuiltInMicrophoneDevice" to obiekt stały CF); zostawić albo zmienić na
   `takeUnretainedValue` przy okazji innej pracy.
2. `docs/superpowers/reports/S0.md:23` cytuje martwy hash `08892c4` (po amendzie: `86f4c27`) —
   raport wyjaśnia amend zdaniem obok, hash strzeże `scripts/check-hashes.sh` + wpis w
   `scripts/check-hashes.allow`. **Nigdy** — kosmetyka; jedyna nieścisłość to etykieta wpisu
   w allow („bez opisu") i brak finalnego hasha w tekście raportu.

## 5. Bramki fazy 1

| Bramka | Spełniona | Dowód |
|---|---|---|
| Nagranie — dwa tory | tak | `SessionRecorderTests.swift:21` (`twoSourcesProduceTwoFilesAndAClosedSession`: dwa pliki, 48 000/16 000 ramek); `TrackWriterTests` (jeden pisarz = jedna ścieżka); D3: prawdziwe spotkanie Teams, oba tory bez luk |
| Nagranie — oś sesji | tak | `SessionRecorderTests.swift:38` (T2, offset mierzony), `SessionSummaryTests.swift:59` (T8, kotwice zegara; mutacja czerwona w przeglądzie S11), `RunnerTests.swift:217` (czas z kotwic, nie z offsetu) |
| Nagranie — uprawnienia/odmowa | tak | `SessionRecorderTests.swift:66` (T9: `permissionDenied` jawny, sesja trwa), `:135` (`allZeros60s`), `:119` (brak nadpisywania sesji); D3 krok 2 (mikrofon wyłączony — odmowa odnotowana) |
| Transkrypcja — cięcie na okna | tak | `GateAndPackerTests.swift:39,48,55` (pakowanie, limit 59 s, cięcie w najcichszej ramce), `RunnerTests.swift:203` (85 min, wiele granic okien, bez nakładek) |
| P5 — wznowienie bez ponownego płacenia | tak | `RunnerTests.swift:51` (`interruptedRunResumesWithoutPayingAgain`: licznik żądań stuba, drugi przebieg = tylko brakujące; mutacja `saved.chunk == item.chunk` czerwona — S11 runda 1); D3: `Resume` — `requestCount` = `chunkCount` = brakujące okna, ten sam `runID` |
| P6 — bramka energii (cisza bez żądań) | tak | `RunnerTests.swift:42` (`silentSessionSendsNothing`, `asr.requests == 0`), `GateAndPackerTests.swift:15` |
| P11 — strażnik języka | tak | `LanguageGuardTests` (5 testów; mutacja `case .english: return nil` czerwona — S11), `RunnerTests.swift:94` (flaga + `excludedFromNotes`) |
| Migawka przebiegu (P12) | tak (z zastrzeżeniem planu §7) | `RunnerTests.swift:173` (`snapshotCarriesTheWholePreset`: pełny preset, odmowa kształtu czatowego), `:74` (`run.json` niesie migawkę); świadoma luka z planu 00 §7: brak testu „edytuj preset po przebiegu" (run.json to kopia, nie referencja) |
| P7 — preset bez języka / nigdy auto | tak | `PresetTests.swift:7,14,70` (auto z typu niemożliwe; `missingLanguage`/`missingASR` w `PresetsFile.upsert`) |
| Kształt czatu — blokada | tak (migawka) | `RunnerTests.swift:180` (`chatShapeNotForMeetings`), `ClientTests.swift:33`; blokada zapisu presetu = `AppModel.swift:174` — kod aplikacji poza testTargetem (STRUKTURALNE #1) |
| Blokady równoległego przebiegu | tak (w kodzie), bez testu | `AppModel.swift:61,263-269` (`transcribing`), `:195` (guard startu), `RecordingController.swift:24,27` (`StartError.alreadyRecording`); D3: drugie nagranie z UI niemożliwe; test niemożliwy bez STRUKTURALNEJ #1 |
| **Model i język żądań = migawka** | **nie** | brak testu — mutacja `model: "MUTANT…", language: nil` daje 109/109 (BLOKUJĄCE #1) |
| CLI | tak (ręcznie); brak testów automat. | przebiegi S12 (`--language` obowiązkowe, kod 64; `autoIsForbidden`), S13 (24/24 okien, wznowienie P5 przez CLI), S16 (kolejność błędów użycia, `session-from-file`); brak testTargetu CLI — klasa STRUKTURALNEJ #1/#2 |
| Składanie paczki i podpis (D1) | tak (ręcznie); brak testów | plan 04 D1: DR stabilne po przebudowie (S14fix), `codesign --verify --strict` rc=0; D3 krok 9A–C (cert: brak monitów, ad-hoc: arkusz wraca); pokrycie = STRUKTURALNA #2 |
| Uprawnienia TCC (spec rdzenia §8) | tak | D3 krok 9 (uprawnienia wiszą na podpisie, nie na ścieżce paczki), krok 1 (monit z tekstem `NSMicrophoneUsageDescription`); `Resources/Info.plist:29-32` oba klucze obecne; pytanie o usługę process tap = STRUKTURALNA #5 |

## 6. Pytania do orkiestratora

1. **Wiersz „Recovered" (BACKLOG, faza 1.5) — zawężenie przyczyny.** Powtórzyłem eksperyment D3
   dokładną konstrukcją URL-i z kodu (env `MEETNOTES_DATA_DIR=$PWD/.devdata` →
   `URL(fileURLWithPath:)` → `appendingPathComponent` vs `contentsOfDirectory`) na prawdziwych
   katalogach z `.devdata`: `==` **true**, `absoluteString` identyczne (tak jak w D3). Przy tym
   kodzie wiersz nie może się pojawić, gdy `recording.directory` jest ustawione — filtr
   `MeetingsView.swift:17-20` działa, a `directory` jest przypisywane synchronicznie przed
   `reloadSessions()` (`AppModel.swift:205-218`). Pytanie: czy na zrzucie z 12:27 był też wiersz
   „Recording" u góry tej samej listy (ta sama instancja aplikacji)? Jeśli nie — wiersz mógł pochodzić
   z drugiej instancji (`open -n` uruchamia nową; `run.sh` ma co prawda blokadę `pgrep`
   od `0e2fa49`, ale obejście np. `swift run` zostawiłoby dwie instancje na jednym `.devdata`).
   Bez odpowiedzi nie rozstrzygam między tymi dwiema hipotezami.
2. **Klasyfikacja pozycji 2.1 (utrata danych konfiguracyjnych przez `load()`/`save()`).**
   Literal decyzji 2026-10-13 mówi „utrata lub zepsucie danych **sesji**" — pliki
   `presets.json`/`providers.json`/`settings.json`/`probe-cache.json` danymi sesji nie są,
   więc umieściłem ją w DO PLANU 1.5. Jeśli „utrata danych" ma szerszy sens (presetów używa się
   do każdego nagrania), podnieść do rundy — proszę o decyzję.
3. **Runda poprawkowa dla BLOKUJĄCEGO #1 to wyłącznie testy** (kod na HEAD jest poprawny).
   Czy dopisać testy także dla drugiej połowy tej samej bramki — że `resume` wysyła dokładnie
   migawkę z `input.json` (dziś chroni ją tylko `inputMismatch`, `RunnerTests.swift:156`)?
