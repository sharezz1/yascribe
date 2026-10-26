# Poprawki po przeglądach S3 i S4 — przegląd (niezależny)

**Zakres:** `git diff 236d42b..13612d9` (commity: `e2b4bf9` raporty, `2b90cf8` S3-1…S3-9,
`13612d9` P1–P9, P12 + spec + po amendzie P10 i raport poprawek), raport wykonawcy
`docs/superpowers/reports/S3-S4-poprawki.md`, punkty źródłowe: `S3-przeglad.md` (1–9),
`S4-przeglad.md` (P1–P12), plan `2026-09-24-faza1-00-przeglad.md` §4.
**Gałąź:** `faza1`, bez przełączania. **Tryb:** przegląd — niczego nie naprawiono; kontrole
mutacyjne robione na chwilę i przywrócone (`git status --porcelain` po nich czysty).
**Nie uruchamiano:** nagrywanie, `check-system-audio`, wszystkiego wymagającego sprzętu/TCC.

## scripts/test.sh (wymagany)

Ostatnia linia:

```
test.sh: 52/52 testów uruchomionych i zaliczonych.
```

Zgodne z raportem poprawek (52). Smoke CLI powtórzony na binarce debug (bez sprzętu):
`fit /nie/ma/ref.aiff` → 64; `fit a b --max-lag-ms -3` → 64; `record /tmp/mn-x --seconds abc
--no-system --no-aec` → 64 (katalog nie powstaje); `record /tmp/mn-x --seconds` → 64;
`summarize /nie/ma` → 1. Zgodne z deklaracją w raporcie.

## Uwagi

### U1 — P6: `try?` + bezwarunkowe `stalledTracks.remove` gubi `track.recovered` bez ponowienia

- **Plik/miejsce:** `Sources/MeetNotesRecording/SessionRecorder.swift:149–152` (blok `.chunk`)
- **Problem:** `try? journal.append(.trackRecovered(...))` połyka błąd zapisu, a
  `stalledTracks.remove(trackID)` wykonuje się niezależnie od wyniku. Zdarzenie ginie
  bezpowrotnie (tor już nie jest w `stalledTracks`, więc `track.recovered` nie powstanie nigdy),
  a `SessionSummary` zostaje z `failure = "stalled30s"` przy żywym torze. To dokładnie klasa
  błędu z P3, naprawiona w tym samym commicie — ale tylko dla ścieżki stall w `tick()`.
  Przy pierwszej porcji po stallu ponowienie jest możliwe (kolejna porcja), więc wzorzec P3 da się
  zastosować 1:1.
- **Propozycja:** `do { try journal.append(.trackRecovered(...)); stalledTracks.remove(trackID) } catch {}`
  — przy błędzie zapisu tor zostaje w zbiorze i zdarzenie ponowi się przy następnej porcji.

### U2 — P6/P2: `track.recovered` czyści też późniejszą, prawdziwą awarię

- **Plik/miejsce:** `Sources/MeetNotesSessionFormat/SessionSummary.swift:119–120`; kolejność
  zdarzeń z `SessionRecorder.handle`/`tick`
- **Problem:** `track.recovered` ustawia `failure = nil` bezwarunkowo. Scenariusz: tor wpada w
  stall → `track.failed("stalled30s")` (`stalledTracks`) → potem `.failed("reopen: …")` /
  `.failed("inputDeviceChanged…")` / `allZeros…` (prawdziwy powód zapisany, `failedTracks`) →
  porcja → `trackRecovered` → podsumowanie pokazuje `failure = nil`, mimo że tor zawiódł ponownie.
  Przeczy to decyzji P2 („podsumowanie dalej pokazuje ostatnią awarię, jeśli tor naprawdę zawiódł
  dwa razy") i P6 („podsumowanie nie może mówić »stalled«" — ale nie może też mówić „OK").
  Dziennik pozostaje kompletny (źródło prawdy), gubi tylko `session.json`.
- **Propozycja:** zgłaszać recovery tylko gdy tor nie jest w `failedTracks`
  (`&& !failedTracks.contains(trackID)`), albo w `SessionSummary.rebuild` zdejmować `failure`
  tylko gdy równa się `stalled…`.

### U3 — P1: test pokrywa wyłącznie predykat `shouldReport`, nie okablowanie

- **Plik/miejsce:** `Tests/MeetNotesRecordingTests/FormatConverterTests.swift:527–533` vs
  `Sources/MeetNotesRecording/HALCapture.swift:84` i `MicrophoneSources.swift:97`
- **Problem:** test `conversionFailuresAreReportedEvenWhenTheyComeInBursts` woła
  `FormatConverter.shouldReport` wprost. Żaden test nie dotyka `HALCapture` ani
  `VoiceProcessedMicrophoneSource` (0 wystąpień tych typów w `Tests/`), więc mutacja przywracająca
  stary warunek `conv.failures == 1 || % 1_000 == 0` w obu miejscach wywołań zostaje **zielona**.
  Raport nie zapisuje tego ograniczenia (a nazwa testu sugeruje pokrycie zgłaszania).
- **Propozycja:** dopisać w raporcie świadome ograniczenie (wymaga sprzętu — sprawdzi A10);
  ewentualnie mutację okablowania odhaczyć przy A10. Sam predykat jest dobrze przypięty
  (4 przypadki: `0→5` tak, `5→9` nie, `998→1001` tak, `3→3` nie — mutacje semantyki dają czerwień).

### U4 — P2: dwa z trzech miejsc `failedTracks.insert` bez pokrycia; `try?` + bezwarunkowy insert w `.failed`

- **Plik/miejsce:** `Sources/MeetNotesRecording/SessionRecorder.swift:162` (`handle`, `.failed`),
  `:187` (`watchZerosLocked`); test `stallDoesNotOverwriteEarlierFailure` pokrywa tylko `:104`
  (`catch` przy `source.start()`)
- **Problem:** (a) mutacja usunięcia insertu w `:104` daje czerwień (sprawdzone przebiegiem), ale
  usunięcie insertów w `:162`/`:187` zostaje zielone — test nie wysyła zdarzeń `.failed` do
  handlera (0 wystąpień `.failed(` w `Tests/`). (b) `handle .failed` ma `try?` + bezwarunkowy
  `failedTracks.insert` — przy błędzie zapisu dziennika zdarzenie ginie, a insert blokuje też
  późniejszy `stalled30s`, więc tor nie dostaje **żadnego** `track.failed` (przed poprawką stall
  zostawiał przynajmniej ślad). Przy `.failed` nie ma możliwości ponowienia (zdarzenie jednorazowe),
  więc insert winien być warunkowany zapisem albo opisany jako świadomy kompromis.
- **Propozycja:** test dla ścieżki `.failed` (źródło wysyła `.failed`, potem 40 s ticków — brak
  `stalled30s`); rozważyć wzorzec P3 dla `:162`/`:187`; zapisać kompromis w raporcie.

### U5 — P9: uzasadnienie decyzji jest odwrócone względem kolejności w kodzie

- **Plik/miejsce:** `docs/superpowers/reports/S3-S4-poprawki.md`, „Decyzje", P9;
  `Sources/MeetNotesRecording/TrackWriter.swift:60–68`
- **Problem:** decyzja broni kolejności „dziennik, potem plik" zdaniem „track.closed nie może
  wyprzedzić ostatnich ramek na dysku". Utrzymana kolejność robi coś przeciwnego:
  `journal.append(.trackClosed)` trafia do dziennika **przed** `caf.close()` (= `synchronize`),
  czyli zdarzenie wyprzedza fsync ramek. Kolejność odwrotna (propozycja P9) gwarantowałaby
  literalne spełnienie tego zdania. Sam kod jest bezpieczny po poprawce (przy błędzie dziennika
  CAF zostaje zamknięty, wyjątek idzie dalej) — błąd dotyczy tylko treści raportu.
- **Propozycja:** poprawić uzasadnienie w raporcie (np. „zdarzenie zamyka licznik ramek po
  wywołaniach `write`; synchronizacja jest już tylko kwestią trwałości"), albo faktycznie zamknąć
  plik przed `track.closed`.

### U6 — CLI: walidacja `number()` odrzuca wartości ≤ 0 — poza literą S3-3

- **Plik/miejsce:** `Sources/meetnotes-cli/CLI.swift:44–51`
- **Problem:** S3-3 proponował walidację obecności i parsowalności wartości; kod odrzuca też
  wartości nieujemne i nieskończone (`--max-lag-ms 0` — wcześniej poprawne „brak przeszukiwania
  opóźnienia" — teraz `exit(64)`, tak samo `--silence 0`, `--seconds 0`). Zmiana zachowania poza
  zakresem przeglądu, choć udokumentowana w raporcie i nieszkodliwa: grep planów nie znajduje
  wywołań z zerem (A10 używa `--seconds 12`, `--max-lag-ms 2000`, `--silence 60`).
- **Propozycja:** uznać za świadome rozszerzenie (dopisać jedno zdanie w „Odchyleniach") albo
  dopuścić `>= 0` dla `--max-lag-ms`. Bez pilności.

### U7 — P8: ścieżka spóźnionego `stop()` emituje `.deviceChanged("")`

- **Plik/miejsce:** `Sources/MeetNotesRecording/MicrophoneSources.swift:55` (`open()` zwraca `""`),
  `:62` (`reopen()` → `h?(.deviceChanged(try open()))`)
- **Problem:** gdy `open()` wykryje `stopped` (albo spóźniony `lateStop`), zwraca pusty string, a
  `reopen()` zgłasza `.deviceChanged("")` — zdarzenie z pustym UID-em. Dziś nieszkodliwe (gdy
  `stopped == true`, `finish()` już ustawił `finishing`, więc `handle` zdarzenie odrzuci), ale
  poprawność zależy od strażnika w innym module; `DeviceWatcher.stop()` nie gwarantuje braku
  callbacków w locie (blok na własnej kolejce). Drobna pułapka na przyszłość.
- **Propozycja:** na ścieżce `lateStop` zwracać bez zdarzenia (np. `reopen()` niech nie woła
  `h?(.deviceChanged(...))`, gdy `open()` zwróciło `""`).

## Punkty S3 (za `S3-przeglad.md` 1–9)

| Punkt | Plik / miejsce | Problem | Propozycja |
|---|---|---|---|
| S3-1 RAM bez limitu | `Sources/MeetNotesRecording/AudioFit.swift:33–55` (`readAnyAudio`), test `AudioFitTests.fitFilesFindsDelayedCopyInRealFiles` | OK — jawny limit 3600 s (wariant z propozycji), `reserveCapacity`, błąd przed czytaniem; test odrzuca plik ponad limit (`maxSeconds: 0.1`) i czyta bajt w bajt. Limit policzony poprawnie (~0,7 GB dla 48 kHz stereo zgadza się z raportem). Uwaga formalna: błąd zwracany jako `AudioSourceError.deviceUnavailable` (semantyka „urządzenia" dla pliku) — kosmetyka | Utrzymać; ewentualnie osobny przypadek błędu dla pliku |
| S3-2 ciche `break` | `AudioFit.swift:48–51` | OK — pusty odczyt / brak `int16ChannelData` przed końcem pliku = `throw` z numerem ramki; bez testu (trudno wywołać urwany odczyt; propozycja go nie wymagała) | Brak |
| S3-3 liczby w opcjach | `Sources/meetnotes-cli/CLI.swift:44–51` (`number`) | OK co do literały propozycji (obecność + parsowalność → komunikat, `usage`, 64), ale walidacja szersza — patrz **U6** | Patrz U6 |
| S3-4 walidacja po efekcie ubocznym | `CLI.swift:102–108` (`fit`) | OK — oba pozycyjne i `--max-lag-ms` pobrane przed otwarciem plików; powtórzony smoke: `fit /nie/ma/ref.aiff` → 64 | Brak |
| S3-5 `--seconds` > 4 h | `CLI.swift:66–69` + `EndCondition.standard` (`Silence(600), HardLimit(4 h), Stall(30)`) | OK — `removeAll { $0 is HardLimitCondition }` usuwa tylko limit 4 h, dokłada własny; wariant „nadpisać" zgodny z decyzją; `--silence` bez zmian (pierwszy na liście wygrywa) | Brak |
| S3-6 SIGINT | `CLI.swift:83–86` | OK — `sigint.cancel()` + `signal(SIGINT, SIG_DFL)` po zakończeniu; ścieżka błędu `try recorder.start()` zostawia źródło i `ticker` do wyjścia procesu (exit(1)) — nieszkodliwe w CLI | Brak |
| S3-7 ticker | `CLI.swift:78–84` | OK — `while (try? await Task.sleep(...)) != nil` + `await ticker.value`: po `cancel()` ani jednego nowego `tick()`, `summarize` nie ściga się z tickerem. Zachowanie z kontraktu, nie z implementacji `tick()` — zgodne z decyzją | Brak |
| S3-8 podwójne „koniec:" | `CLI.swift:82`, `:90–92` | OK — wydruk z pętli usunięty; zostaje `summarize` (daje też `koniec: BRAK (awaria)` potrzebny A10 krok 8 — potwierdzone w kodzie) | Brak |
| S3-9 brak testu `fit` | `Tests/MeetNotesRecordingTests/AudioFitTests.swift:494–517` | OK — `fitFilesFindsDelayedCopyInRealFiles`: wav przez `AVAudioFile` + CAF przez `CAFWriter` (240 ramek opóźnienia, gain 0,06), asercje `lagFrames == 240`, `gain ≈ 0,06`, odczyt bajt w bajt, odrzucenie pliku ponad limit; sprząta katalog tymczasowy | Brak |

## Punkty P (za `S4-przeglad.md` P1–P12)

| Punkt | Plik / miejsce | Problem | Propozycja |
|---|---|---|---|
| P1 wybuchy awarii konwersji | `FormatConverter.swift:65–70` (`shouldReport`), `HALCapture.swift:84`, `MicrophoneSources.swift:97` | OK w implementacji (pierwsza awaria + każde przekroczenie tysiąca na sumie; oba wywołania przez wspólny predykat). Pokrycie testowe niepełne — **U3** | Patrz U3 |
| P2 nadpisywanie przyczyny | `SessionRecorder.swift:35`, `:104`, `:122–123`, `:162`, `:187` | OK w mechanizmie (zbiór `failedTracks` w 3 miejscach, nadzór pomija); test `stallDoesNotOverwriteEarlierFailure` mutacyjnie czuły na ścieżce `catch`. Luki pokrycia i `try?` w `.failed` — **U4** | Patrz U4 |
| P3 `try?` + bezwarunkowy insert | `SessionRecorder.swift:126–130` | OK — `do { append; insert } catch {}`, niezapisane zdarzenie ponawia się przy następnym `tick()`; brak testu uzasadniony (wymaga wstrzyknięcia błędu zapisu). Wzorzec nie zastosowany w P6/`.failed` — **U1**, **U4** | Patrz U1, U4 |
| P4 test nie przypina 30 s | `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift` (`deadTrackIsFlaggedWhileOtherContinues`, pętla + asercje graniczne) | OK — granica przypięta z obu stron (k=29 → `nil`, k=30 → `stalled30s`) i `mic_raw` bez `failure` na końcu. Mutacje sprawdzone: `* 10` — **czerwień potwierdzona przebiegiem** (2 asercje padają), `* 100`, `/ 10`, `+ 9`, `>=`→`>` — czerwień analitycznie z asercji granicznych (3000 s → brak awarii przy k=30; 3 s → awaria przed k=29) | Brak |
| P5 „mic_aec stopped" bez stopu | `MicrophoneSources.swift:103–110` | OK — `removeTap` + `engine.stop()` przed zgłoszeniem; treść zdarzenia bez zmian (E3 opiera się na `failure != nil`) zgodnie z decyzją. Drobna współbieżność: callback watchera i `stop()` wołają `removeTap`/`engine.stop()` z dwóch wątków (`DeviceWatcher` ma własną kolejkę, `stop()` nie czeka na callbacki w locie) — operacje idempotentne, `handle` odrzuca zdarzenia po `finishing`; do obserwacji przy A10 | Brak pilny; rozważyć flagę `stopped` jak w P8 |
| P6 tor nie wraca do życia | `SessionRecorder.swift:149–152`, `JournalEvent.swift:15–16, 359–363`, `SessionSummary.swift:119–120`, test `stalledTrackThatResumesIsNotLeftFailed`, spec l. 152 | OK w wariancie (jawne `track.recovered`, dziennik źródłem prawdy — decyzja poprawna), ale implementacja: **U1** (utrata zdarzenia bez ponowienia) i **U2** (zdejmuje też późniejszą awarię) | Patrz U1, U2 |
| P7 30 s od startu sesji | `SessionRecorder.swift:70–73`, `:84–87` | OK — `lastChunkByTrack[trackID]` = czas `track.opened` (dosłownie propozycja); `?? startedAt` zostaje jako martwy fallback, bez wpływu | Brak |
| P8 wyścig `stop()`/przebudowa | `MicrophoneSources.swift:21–22, 48–57`, `SystemTapSource.swift:20–21, 87–98, 121–122` | OK — flaga `stopped` + podwójna kontrola (przed budową i przy przypisaniu `capture`), `rebuild()` po `stop()` sprząta tap/urządzenie zbiorcze (analiza przeplotów pokryta: każdy spóźniony `build()` jest sprzątany przez `teardown` w ścieżce `late` albo w `stop()`). Bez testu — wymaga Core Audio, zgodnie z raportem. Drobna zastrzeżenie — **U7** | Patrz U7 |
| P9 CAF otwarty po błędzie dziennika | `TrackWriter.swift:60–68` | OK w kodzie (`do/catch`, CAF zamknięty, wyjątek propagowany dalej; kolejność „dziennik, potem plik" utrzymana świadomie). Uzasadnienie decyzji odwrócone — **U5** | Patrz U5 |
| P10 hash w `S4.md` | `docs/superpowers/reports/S4.md` (tabela „Commity" + akapit o zakresie) | OK — `006e69b` → `236d42b` z opisem amendu, „9 plików" → 10; `git show 236d42b --stat` = 10 plików (6 źródeł, 2 testy, plan, raport) — zgadza się; `006e69b` i `823dc51` istnieją jako obiekty sprzed amendu | Brak |
| P11 fsync pod blokadą | `SessionRecorder.swift:120–121` (komentarz `ponytail:`) | OK — odłożenie świadome, uzasadnienie **poprawne**: `SessionJournal.append` ma własną blokadę i robi `write` + `synchronize`, a `finish()` zamyka dziennik pod blokadą rejestratora — przeniesienie appendów poza blokadę otwiera wyścig z `finish()` (zapis po `close()` to wyjątek ObjC `NSFileHandleOperationException`, nie do złapania w Swift) i kolejność `track.failed` po `session.ended`. Zysk pomijalny (≤ 1 zdarzenie na tor na sesję; `handle()` robi ten sam fsync przy każdej luce i kotwicy). Wyzwalacz z konsultacji (luki/kotwice w T6/T8) — rozsądny | Utrzymać w backlogu; wrócić przy A10, jeśli T6/T8 pokażą luki |
| P12 niesanityzowany `trackID` | `SessionRecorder.swift:61–65`, `:218–220`, test `unsafeTrackIDNeverLeavesSessionDirectory` | OK — walidacja `[A-Za-z0-9_-]+` w `start()` przed `prepare()` (wariant z propozycji; brak zmiany sygnatury `SessionDirectory.trackURL` zgodny z decyzją), zły tor → `track.failed("invalidTrackID")`, plik nie powstaje; test sprawdza brak `evil.caf` poza katalogiem i `.noSources`. Dwie drobiazgi bez wpływu: (a) tor odrzucony nie pojawia się w `session.json` (brak `trackOpened` → `index` go nie ma; `track.failed` zostaje tylko w dzienniku); (b) `isSafeTrackID` zgadza się z regexem `[A-Za-z0-9_-]+` | Brak; (a) rozważyć przy okazji widoczności błędów torów w UI (E4) |

## Oś 2 — zakres zachowania i mutacje

- **Poza zakresem przeglądów:** tylko **U6** (odrzucanie wartości ≤ 0). Poza tym zachowanie zmienia
  się tam, gdzie przegląd nakazał (P5 stop toru, P6 nowe zdarzenie — odnotowane w „Odchyleniach"
  raportu i w specu l. 152). Limit 1 h w `readAnyAudio` obejmuje też przyszłe `session-from-file`
  (plan C) — zgłoszone w „Odchyleniach", plan C używa krótkiego pliku — OK.
- **Odchylenia od planu (raport pkt 1–7) sprawdzone:** sygnatury `CLI.option`/`positional`/
  `readAnyAudio` bez zmian ✓ (plan B/C nie ruszony); `AudioFit` w bibliotece — graf `Package.swift`
  już miał `MeetNotesRecording → MeetNotesSessionFormat` ✓ (drobiazg: `Tests/MeetNotesRecordingTests`
  importuje teraz `MeetNotesSessionFormat` bez wpisania w zależności celu testowego — działa, ale
  nieformalne); zmiany literalnego kodu E1 zgodne z kolejnością „propozycja przeglądu ma
  pierwszeństwo" ✓; `track.recovered` — jedyny `switch` po `e.type` w kodzie obsłużony ✓ (kopia
  `SessionSummary.rebuild` w planie 01 l. 705 jest historyczna i nie zawiera nowego case — bez
  wpływu, plan wykonany); spec uzupełniony jednym zdaniem ✓; liczby testów 47 → 52 = +5 nowych
  `@Test` + rozszerzony `deadTrackIsFlaggedWhileOtherContinues` ✓.
- **Mutacje:** P4 — `* 10` czerwona przebiegiem (przywrócone), `* 100`, `/ 10`, `+ 9` czerwone
  analitycznie z asercji granicznych (raport podaje `* 100`, `* 10`, `/ 10` — wiarygodne).
  P2 — usunięcie `failedTracks.insert` w `catch` przy `source.start()` czerwone przebiegiem
  (przywrócone); mutacje insertów w `handle .failed`/`watchZerosLocked` zostają zielone — **U4**.
  P1 — mutacje semantyki `shouldReport` czerwone (4 przypięte przypadki); mutacja okablowania
  w `HALCapture`/`MicrophoneSources` zielona — **U3**. P6/P12 — mutacje (brak `track.recovered`,
  brak walidacji) czerwone z asercji testów.
- **Istniejące testy nie osłabły:** `deadTrackIsFlaggedWhileOtherContinues` rozszerzony (stare
  asercje zastąpione równoważnymi + granica + `mic_raw`); pozostałe pliki testowe tylko z
  dopiskami. `scripts/test.sh` bez zmian (kontrola liczby `@Test` działa: 52/52).

## Oś 3 — wycieki, wyścigi, połknięte błędy, zapisy

- **Połknięte błędy:** **U1** (P6 `try?` + bezwarunkowy remove), **U4** (P2 `.failed` `try?` +
  bezwarunkowy insert — tor bez żadnego `track.failed` przy błędzie zapisu). `catch {}` w P3 i
  `try? caf.close()` w P9 — zgodne z propozycjami/decyzją.
- **Wyścigi:** P8 zamknięty (analiza przeplotów `stop()`/`open()`/`startCapture()`/`rebuild()`
  pokryta podwójną kontrolą `stopped`); P5 — drobna współbieżność callback/`stop()` (idempotentne,
  patrz wiersz P5); P11 — świadome odłożenie z poprawnym uzasadnieniem. `failedTracks`/`stalledTracks`
  zawsze pod blokadą `lock` (`handle`, `tick`, `watchZerosLocked`, `start` catch) ✓.
- **Wycieki zasobów:** P9 zamknięty (CAF zamykany także przy błędzie dziennika); P5 zatrzymuje
  engine i tap; P8 sprząta spóźniony capture/tap/urządzenie zbiorcze. `sigint`/`ticker` — patrz S3-6
  (śmierć procesu). `VoiceProcessedMicrophoneSource` bez flagi `stopped` — bezpieczne (nie buduje
  zasobów od nowa; zdarzenia po `finishing` odrzucone).
- **Zapis poza katalogiem sesji:** nie znaleziono w zmienionym kodzie; P12 zamyka furtkę z `trackID`.
  Nowy test `fit` sprząta katalog tymczasowy; trzy nowe testy `SessionRecorderTests` używają
  `sessionDir()` bez sprzątania — jak reszta pliku (uwaga formalna S4, poza zakresem tych poprawek).

## Formalne

- W drzewie roboczym leży nieśledzony `docs/superpowers/reports/S3-S4-poprawki-decyzje.md`
  (konsultacja odpowiadająca na 4 pytania z raportu poprawek, „nic nie wdrożone"). Nie jest częścią
  diffu `236d42b..13612d9` ani tego przeglądu — odnotowuję dla porządku; jej wnioski (pkt 3+4 przed
  pkt 1, P11 do backlogu z wyzwalaczem A10) są spójne z oceną P11 powyżej.
- Raport poprawek nie zawiera odwołań do nieistniejących kroków; cytowane hashe sprawdzone w `git`.
