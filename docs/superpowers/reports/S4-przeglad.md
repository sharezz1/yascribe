# Przegląd S4 — E1 (rdzeń: dziennik, nadzór torów, sprzątanie Core Audio)

**Zakres:** `git diff 3024eb3..236d42b`, plan `docs/superpowers/plans/2026-09-24-faza1-05-poprawki-po-recenzjach.md`
zadanie E1 (kroki 1–10), wymagania `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md` §4,
raport wykonawcy `docs/superpowers/reports/S4.md`. Gałąź `faza1`.
Recenzja szuka błędów, nie ocenia. Niczego nie naprawiono — poniżej tylko opis.

## scripts/test.sh

Ostatnia linia:

```
test.sh: 47/47 testów uruchomionych i zaliczonych.
```

Zgodne z oczekiwaniem planu (krok 8) i z raportem S4.

## Kontrole

### 1. Kod vs plan i komentarze

Bloki planu (kroki 3–7) weszły dosłownie — `SessionJournal.read`, `tick()`, `FormatConverter.failures`
(3 miejsca), `HALCapture.init/start`, `SystemTapSource.build/startCapture`, `MicrophoneSources`
(w tym `watcher` w `VoiceProcessedMicrophoneSource`) pokrywają się 1:1 z treścią planu. Zmiany
zgłoszone jako „minimalne" nie wystąpiły; zachowanie względem `3024eb3` zmienia się tylko tam,
gdzie plan to przewiduje. Rozjazdy komentarz/zachowanie: **P1**, **P5**.

### 2. Testy vs wymagania; mutacja z planu

- `tickBeforeStartDoesNothing` — wymaganie „`tick()` przed `start()` nic nie robi" (Hermes 2.1).
  Na `3024eb3` czerwony (stary `tick()` wywoływał `evaluateLocked` → `SilenceCondition(1)` przy
  t = 10 s → `endReason == .silence`). Test sprawdza dokładnie to wymaganie. OK.
- `completeButCorruptLastLineIsAnError` — ChatGPT #12. Na `3024eb3` czerwony (stary warunek
  `isLast` tolerował zakończoną niepoprawną ostatnią linię). OK.
- `deadTrackIsFlaggedWhileOtherContinues` — ChatGPT #9. Na `3024eb3` czerwony na
  `sys.failure == "stalled30s"` (kompiluje się — nie używa nowych parametrów). Sprawdza
  „sesja trwa" (`endReason == nil`) i `track.failed` z powodem `stalled30s`. Nie sprawdza
  granicy 30 s ani tego, że mikrofon nie został oznaczony — patrz **P4**.
- **Mutacja `>= trackStallSeconds * 100` (krok 9):** stan bieżący jest niemutowany
  (`SessionRecorder.swift:109` ma `>= trackStallSeconds`). Analitycznie mutacja daje czerwień:
  próg = 3000 s, pętla testu przesuwa zegar o 40 s, `lastChunkByTrack["system"]` puste →
  `last = startedAt = 0`, `secondsBetween(40 s, 0) = 40 < 3000` → brak `track.failed` →
  `sys.failure == nil ≠ "stalled30s"` → `#expect` pada; `scripts/test.sh --filter …` zwraca
  kod 1 (`test.sh:32–34`). Czerwień potwierdzona rozumowaniem; samego przebiegu z kroku 9 nie da
  się powtórnić bez naruszenia zakazu zmiany plików, więc pozostaje to zgodność z twierdzeniem S4,
  a nie dowód. Jednostronność testu (mutacja `* 10` / `/ 10` nie dałaby czerwieni) — **P4**.
- Liczba deklaracji `@Test`: 44 przed, 47 po — zgadza się z raportem S4 i z kontrolą `test.sh`.

### 3. Wycieki zasobów, wyścigi, połknięte błędy, zapis poza katalogiem sesji

- Poprawki z diffu w punktach „wyciek" są poprawne: `AudioDeviceDestroyIOProcID` przy nieudanym
  `AudioDeviceStart` (`HALCapture.swift:45–49`, `procID = nil`, `stop()` bezpieczne) oraz sprzątanie
  `aggID`/`tapID` przy wyjątku z `tapFormat(of:)` (`SystemTapSource.swift:73–80`).
- Połknięte błędy i wynikające z nich zachowanie: **P3**, **P9**.
- Wyścigi: **P8** (istniejący wcześniej, w kodzie dotkniętym diffem), **P11**.
- Zapis poza katalogiem sesji: **nie znaleziono**. `SessionRecorder`/`TrackWriter`/`CAFWriter`/
  `SessionSummary.write` piszą wyłącznie pod `SessionDirectory.url`; CLI (`record`, `summarize`)
  pisze pod katalog podany przez użytkownika; testy pod `temporaryDirectory/mn-session-<uuid>`.
  Dwa zastrzeżenia: nazwy plików nie są sanityzowane (**P12**) i testy nie sprzątają swoich
  katalogów tymczasowych (śmiecenie $TMPDIR przy każdym przebiegu; poza diffem).

---

## Punkty

### P1 — raportowanie błędów konwersji nie zgłasza wybuchów awarii

- **Plik:** `Sources/MeetNotesRecording/HALCapture.swift` (i to samo w `Sources/MeetNotesRecording/MicrophoneSources.swift`)
- **Miejsce:** `HALCapture.swift:35–39`, `MicrophoneSources.swift:92–96`; komentarz przy
  `FormatConverter.swift:11–12`
- **Problem:** warunek `conv.failures > before && (conv.failures == 1 || conv.failures % 1_000 == 0)`
  sprawdza **sumę**, nie przyrost. `convert()` tnie bufor na plasterki po 1024 ramki — bufor 4800
  ramek z `installTap` to 5 plastrów. Gdy w jednym wywołaniu padną ≥ 2 konwersje, licznik skacze
  np. 0 → 5 i nie zachodzi ani `== 1`, ani `% 1000 == 0` → zdarzenie `.failed` nigdy nie wychodzi.
  Także przyrost 998 → 1001 omija „co 1000.". W efekcie dźwięk bywa gubiony po cichu, wbrew
  komentarzowi: „źródło zgłasza je jako .failed zamiast po cichu gubić dźwięk".
- **Propozycja:** raportować po przekroczeniu progu na sumie, np.
  `if conv.failures > before && (before == 0 || conv.failures / 1_000 > before / 1_000)`.
  Litera planu (krok 5) zostaje naruszona — do decyzji, ale komentarz i zachowanie muszą się zgadzać.

### P2 — drugi `track.failed` nadpisuje właściwą przyczynę awarii

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`, `Sources/MeetNotesSessionFormat/SessionSummary.swift`
- **Miejsce:** `SessionRecorder.swift:107–112` (nowa pętla w `tick()`), `:91` (`catch` przy
  `source.start()`), `:137–138` (`handle`, `.failed`); `SessionSummary.swift:118`
  (`failure = e.reason` — wygrywa ostatnie zdarzenie)
- **Problem:** pętla nadzoru pomija tory w `ended` i `stalledTracks`, ale nie pomija torów, które
  **już dostały** `track.failed`. Tor, którego `start()` rzucił (np. `CreateIOProc`,
  `engine.start()`), po 30 s dostaje drugi `track.failed("stalled30s")` i w `session.json`
  **nadpisuje** rzeczywisty powód. To samo dotyczy `.failed("inputDeviceChanged…")`,
  `.failed("convert failures: N")` i `allZeros60s` (choć tor zerowy zazwyczaj dalej dostarcza porcje,
  więc stall go nie łapie). Diagnostyka w podsumowaniu staje się myląca.
- **Propozycja:** trzeci zbiór `failedTracks` (dodawać w `catch` przy `source.start()` i w `handle`
  przy `.failed`) i pomijanie go w pętli `tick()`; albo w `SessionSummary.rebuild` nie nadpisywać
  istniejącego `failure` (zachować pierwszy, ewentualnie dopisać listę przyczyn).

### P3 — `try?` przy zapisie `track.failed` + bezwarunkowe `stalledTracks.insert`

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`
- **Miejsce:** `:110–111`
- **Problem:** `try? journal.append(.trackFailed(...))` połyka błąd zapisu (brak miejsca, zamknięty
  uchwyt), a `stalledTracks.insert(s.trackID)` wykonuje się niezależnie od wyniku. Zdarzenie ginie
  i tor jest już trwale wyłączony z nadzoru — `track.failed` nie powstanie nigdy, mimo że sesja trwa.
  `try?` jest zgodny z planem (krok 4d), ale skutek (blokada ponownego zgłoszenia przy niezapisanym
  zdarzeniu) już nie.
- **Propozycja:** `do { try journal.append(...); stalledTracks.insert(...) } catch { }` — brak insertu
  przy błędzie daje ponowną próbę przy następnym `tick()`; ewentualnie zliczać próby i po N odpuścić.

### P4 — test nadzoru toru nie przypina progu 30 s ani czystości drugiego toru

- **Plik:** `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift`
- **Miejsce:** `:163–193` (`deadTrackIsFlaggedWhileOtherContinues`), pętla `:184–188`, asercje `:189–192`
- **Problem:** test kończy się po 40 s i sprawdza wyłącznie `sys.failure == "stalled30s"` oraz
  `endReason == nil`. Nie ma asercji w trakcie pętli, więc `trackStallSeconds` respektowane jako
  0,3 s (mutacja `/ 10`) albo 39 s (mutacja `+ 9`) też dałoby zielony wynik — czerwień daje tylko
  mutacja całkiem wyłączająca wykrywanie, jak `* 100` z planu. Nie ma też asercji, że `mic_raw`
  **nie** dostał `failure` — implementacja oznaczająca wszystkie tory przeszłaby test. Wymaganie
  „track.failed **po 30 s**" jest sprawdzone w połowie; wzór granicy już w tym pliku jest
  (`stallIsDetectedByTick`: 29 s → nil, 31 s → `sourceStalled`).
- **Propozycja:** w pętli sprawdzać stan: po `k == 29` → `sys.failure == nil`; po `k == 30` →
  `sys.failure == "stalled30s"`; na końcu dodatkowo `mic_raw` bez `failure`. Wtedy mutacje
  `* 100`, `* 10`, `/ 10` dają czerwień.

### P5 — zdarzenie mówi „mic_aec stopped", ale nic nie zatrzymuje toru

- **Plik:** `Sources/MeetNotesRecording/MicrophoneSources.swift`
- **Miejsce:** `:100` (`watcher.start { handler(.failed("inputDeviceChanged: mic_aec stopped, mic_raw continues")) }`)
- **Problem:** callback watchera zgłasza awarię o treści „mic_aec stopped", lecz ani tap, ani
  `engine` nie są zatrzymywane (`stop()` nie jest wywoływane). Tor dalej pisze `mic_aec.caf`,
  jeśli engine jeszcze dostarcza dane — w `session.json` `failure` stoi obok niepustego `frames`.
  Jeśli przestaje dostarczać, 30 s później dochodzi `stalled30s` (P2). Komunikat nie odpowiada
  stanowi. Kod jest literalnie zgodny z planem (krok 7) — rozjazd jest między opisem intencji
  a implementacją.
- **Propozycja:** w callbacku faktycznie zatrzymać tor (`removeTap(onBus: 0)` + `engine.stop()`),
  albo zmienić treść zdarzenia na zgodną ze stanem (np. „inputDeviceChanged: mic_aec invalid").
  Przy drugim wariancie warto od razu rozstrzygnąć P2, żeby dalsze porcje nie zgłaszały się po
  `track.failed`.

### P6 — tor oznaczony `stalled30s` nie wraca do życia w podsumowaniu

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`, `Sources/MeetNotesSessionFormat/SessionSummary.swift`
- **Miejsce:** `SessionRecorder.swift:107–112` (`stalledTracks` tylko rośnie), `:129`
  (`lastChunkByTrack` aktualizowane dalej); `SessionSummary.swift:118`
- **Problem:** po wznowieniu dostawy porcji tor nadal ma `failure = "stalled30s"` przy niepustym
  pliku ścieżki; brak zdarzenia o odzyskaniu, `stalledTracks` nie pozwala zgłosić ponownie.
  To samo pytanie podnosi raport S4 („Pytania do orkiestratora" pkt 1) — tu jako błąd spójności
  stanu dziennika i podsumowania.
- **Propozycja:** przy pierwszym `.chunk` toru ze `stalledTracks` zdjąć flagę i dopisać zdarzenie
  odzyskania (nowy typ `track.recovered`); w `SessionSummary` czyścić `failure`, gdy po
  `track.failed` występują jeszcze dane (niezerowe `frames` z `track.closed`).

### P7 — pomiar 30 s dla toru startuje od początku `prepare()`, nie od otwarcia toru

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`
- **Miejsce:** `:53` (`let now = clock.now()` przed pętlą `prepare`), `:77` (`startedAt = now`),
  `:108` (`last = lastChunkByTrack[...] ?? startedAt`)
- **Problem:** `startedAt` jest sprzed przygotowania wszystkich źródeł, a budowa tapu i urządzenia
  zbiorczego (`SystemTapSource.build()`) potrafi trwać setki milisekund. Tor bez porcji dostaje
  `track.failed` po `trackStallSeconds` od startu sesji, realnie wcześniej niż „30 s bez porcji"
  od swojego `track.opened`. W testach z `ManualHostClock` niewidoczne (zegar stoi).
- **Propozycja:** przy `trackOpened` (`:62`) ustawiać `lastChunkByTrack[trackID] = clock.now()`
  (baza = czas otwarcia toru); `startedAt` zostaje dla warunków końca sesji.

### P8 — wyścig `stop()` z `reopen()`/`rebuild()`: uruchomiony capture po zakończeniu sesji

- **Plik:** `Sources/MeetNotesRecording/MicrophoneSources.swift`, `Sources/MeetNotesRecording/SystemTapSource.swift`
- **Miejsce:** `MicrophoneSources.swift:56–60` (`reopen`), `SystemTapSource.swift:107–118` (`rebuild`),
  `SessionRecorder.swift:181` (`s.stop()` bez blokady)
- **Problem:** `reopen`/`rebuild` startują z kolejki `DeviceWatcher` i wykonują `open()`/`build()`
  poza blokadą. Jeśli `stop()` (z `finish`) przebiegnie między `c?.stop()` a przypisaniem
  `capture = c`, nowy `HALCapture` zostaje uruchomiony i podpięty już po `stop()` — nikt go później
  nie zatrzyma (IOProc żyje do końca procesu, callbacki trafiają w `finishing` i są ignorowane).
  Wyścig istniał przed diffem; diff dotykał obu ścieżek (dokładanie `onFailure` w `open`/
  `startCapture`), więc odnotowany przy zmienionym kodzie.
- **Propozycja:** flaga `stopped` ustawiana w `stop()` i sprawdzana po zdobyciu blokady w
  `open()`/`startCapture()` (nie przypisywać `capture` po `stop()`); docelowo cała rekonfiguracja
  na jednej serialnej kolejce razem ze `stop()`.

### P9 — `finish()` połyka błąd zamknięcia toru i zostawia uchwyt CAF otwarty

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`, `Sources/MeetNotesRecording/TrackWriter.swift`
- **Miejsce:** `SessionRecorder.swift:185` (`try? w.close(...)`), `TrackWriter.swift:60–63`
- **Problem:** `TrackWriter.close` robi `journal.append(.trackClosed)` **przed** `caf.close()`.
  Gdy append rzuci, `caf.close()` (`synchronize` + `close`) nie następuje, a `try?` w `finish`
  połyka wyjątek — niesynchronizowany plik i wyciek deskryptora do końca procesu. Poza diffem
  (`TrackWriter` nietknięty), ale w pliku zmienianym; w zakresie punktu „wycieki / połknięte błędy".
- **Propozycja:** `defer { try? caf.close() }` w `TrackWriter.close`, albo w `finish` zamykać pliki
  CAF niezależnie od błędów dziennika (najpierw pliki, potem `track.closed`).

### P10 — raport S4 podaje hash sprzed `--amend`

- **Plik:** `docs/superpowers/reports/S4.md`
- **Miejsce:** tabela „Commity" (linia z `006e69b`) i zdanie „Raport dodany do tego samego commita
  (`--amend`)"
- **Problem:** po dodaniu raportu przez `--amend` hash zmienił się na `236d42b` — to on jest na
  gałęzi `faza1`. `006e69b` istnieje jeszcze jako obiekt, ale to wersja **bez** `S4.md`
  (9 plików zamiast 10). Czytelnik robiący `git show 006e69b` nie zobaczy raportu, którego dotyczy.
  Dodatkowo „9 plików" opisuje zakres sprzed amendu.
- **Propozycja:** podmienić hash na `236d42b` (albo dopisać „hash po amende") i policzyć 10 plików
  (6 źródeł, 2 testy, plan, raport).

### P11 — zapis do dziennika (fsync) pod blokadą rejestratora na ścieżce audio

- **Plik:** `Sources/MeetNotesRecording/SessionRecorder.swift`
- **Miejsce:** `:110` (`journal.append` w `tick()` przy trzymanym `lock`)
- **Problem:** `append` robi `write` + `synchronize` na dysku pod `lock`. `handle` na wątku IOProc /
  tapu czeka wtedy na tę samą blokadę — komentarz klasy (`:7–9`) wprost zakłada nieblokowanie
  ścieżki źródeł. Do 3 torów × fsync na `tick`. Wzorzec istnieje wcześniej (`handle` też appenduje
  pod blokadą), nowy kod go pogłębia; do `AudioDeviceStop` nie dochodzi martwy zamek (blokada jest
  zwalniana), tylko opóźnienie callbacka.
- **Propozycja:** wykonać appendy po `lock.unlock()` (albo na kolejce roboczej), z ochroną przed
  `finish` (dopisywać tylko gdy `!finishing`); doczielnie — cały zapis dziennika poza blokadą.

### P12 — `trackID` nie jest sanityzowany przy budowie ścieżki pliku

- **Plik:** `Sources/MeetNotesSessionFormat/SessionDirectory.swift`
- **Miejsce:** `:11` (`trackURL` — `url.appendingPathComponent("\(trackID).caf")`)
- **Problem:** `trackID` zawierający `/` albo `..` wyprowadza plik poza katalog sesji. Dziś
  identyfikatory są zaszyte w źródłach (`system`, `mic_raw`, `mic_aec`), więc to hipoteza, ale
  `AudioSource.trackID` jest polem publicznym implementacji — przy „zapis poza katalogiem sesji"
  warto zamknąć furtkę zanim dojdzie tor z zewnątrz.
- **Propozycja:** walidacja w `SessionRecorder.start()` (np. `[A-Za-z0-9_-]+`) albo mapowanie
  `trackID` na bezpieczną nazwę pliku; odrzucić tor zamiast pisać obok katalogu sesji.

---

## Sprawdzone i bez zastrzeżeń

- `SessionJournal.read` (`:51–63`) — logika „tylko ostatni fragment bez LF może być urwany" jest
  poprawna: `Data().split` daje `[""]` i `data.last == nil`, `"a\nb\n".split` daje `["a","b",""]`,
  więc `unterminatedLast` wskazuje właściwy fragment; zakończona niepoprawna linia → `corruptLine`.
- `tick()` przed `start()` (`:104`) — brak `journal` blokuje ocenę warunków i nadzór torów; test to
  pokrywa.
- `HALCapture.start()` — zniszczenie IOProc i `procID = nil` przy nieudanym `AudioDeviceStart`;
  `stop()` bezpieczne po błędzie (patrz `guard let proc = procID`).
- `SystemTapSource.build()` — sprzątanie `aggID`/`tapID` przy błędzie `tapFormat(of:)` zamyka
  wyciek z recenzji Hermes 2.3; ścieżka sukcesu przypisuje `tap`/`aggregate` raz, pod blokadą.
- `FormatConverter.failures` — inkrementy w trzech miejscach z planu; brak wyścigu na poziomie
  egzemplarza (każdy strumień ma własny konwerter, odczyt i zapis na tej samej kolejce/wątku).
- Warunki końca i `stalledTracks` są rozłączne: tor zerowy (`allZeros60s`) dostaje porcje, więc nie
  wpada w stall; tor martwy nie wywołuje `allZeros` (brak porcji). Zgodne z intencją planu.
