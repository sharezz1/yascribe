# Poprawki S3-S4, runda 2 — przegląd (niezależny)

**Zakres:** `git diff 13612d9..HEAD` (commity: `bde2bd0` CLI — positional+walidacja, `96fcff4` rdzeń —
U1, U2, U4, U7 + test, `972ea0d` raporty, `1040312` Plany +6). Raport wykonawcy:
`docs/superpowers/reports/S3-S4-poprawki.md` („Runda CLI", „Runda 2"), uwagi źródłowe:
`S3-S4-poprawki-przeglad.md` (U1–U7), plan `2026-09-24-faza1-00-przeglad.md` §4.
**Gałąź:** `faza1`, bez przełączania. **Tryb:** przegląd — niczego nie naprawiono; kontrole
mutacyjne robione na chwilę i przywrócone (`git status --porcelain` po nich i na końcu czysty).
**Nie uruchamiano świadomie:** `check-system-audio`, przepięć urządzeń (U7/P5/P8 — sprzęt, A10).
Wyjątek formalny: jeden dym CLI (`record --seconds 5`) nieopatrznie wykonał realne 5 s nagrania —
patrz „Formalne".

## scripts/test.sh (wymagany)

Ostatnia linia:

```
test.sh: 53/53 testów uruchomionych i zaliczonych.
```

Kod 0. Suma z przebiegów per cel: 0 + 12 + 41 + 0 = 53 = liczba deklaracji `@Test` (52 + 1 nowy).
Zgodne z raportem („52 → 53"). Baseline **53 = 47 + 6** potwierdzony.

## 1. U1, U2, U4, U7 — czy naprawione zgodnie z propozycjami

### U1 — OK

- **Plik/miejsce:** `Sources/MeetNotesRecording/SessionRecorder.swift:152–157` (blok `.chunk`)
- **Stan:** OK — dokładnie propozycja: `do { try journal.append(.trackRecovered); stalledTracks.remove }
  catch {}` (wzorzec P3 1:1). Przy błędzie zapisu tor zostaje w `stalledTracks`, zdarzenie ponowi
  się przy następnej porcji. Brak testu zadeklarowany w raporze (wymaga wstrzyknięcia błędu zapisu)
  — uczciwie; mutacja samego `stalledTracks.remove` — patrz uwaga 3.
- **Propozycja:** brak (poza uwagą 3).

### U2 — OK; nie blokuje legalnego recovery

- **Plik/miejsce:** `SessionRecorder.swift:152` (warunek `&& !failedTracks.contains(trackID)`)
- **Stan:** OK — wariant (a) z propozycji. **Legalne recovery działa:** tor po stallu bez realnej
  awarii trafia wyłącznie do `stalledTracks` (nadzór, `:122–130`), nigdy do `failedTracks`
  (to tylko `catch` przy `source.start()`, `.failed` z `handle`, `allZeros`) → warunek go nie
  blokuje, `track.recovered` powstaje. Potwierdza to zielony `stalledTrackThatResumesIsNotLeftFailed`
  w przebiegu 53/53 (tor `system`: stalled30s przy k=30, `track.recovered` przy k=41, `failure == nil`).
  Scenariusz U2 (stall → prawdziwa awaria → porcje) nie dostaje `track.recovered` — przypięte
  nowym testem (mutacja M1 poniżej). `SessionSummary.rebuild` bez zmian (`failure = nil`
  bezwarunkowo) — poprawne, bo to rejestrator warunkuje zdarzenie; dziennik pozostaje źródłem
  prawdy. Krawędź świadoma: jeśli zapis `.failed` padnie (`catch {}`), tor nie jest w `failedTracks`
  i po porcji dostanie `track.recovered` — ale tamtej awarii nigdy nie było w dzienniku, więc
  podsumowanie jest zgodna ze źródłem prawdy. Nie jest to błąd.
- **Propozycja:** brak.

### U4 — OK w mechanizmie; luka pokrycia w `watchZerosLocked` — patrz uwaga 2

- **Plik/miejsce:** `SessionRecorder.swift:165–171` (`handle`, `.failed`), `:193–199` (`watchZerosLocked`)
- **Stan:** OK — oba inserty warunkowane udanym `journal.append` (wzorzec P3), `zeroResolved`
  celowo bezwarunkowo (kompromis z raportu opisany). Twierdzenie raportu „mutacja usunięcia insertu
  w `.failed` → czerwień (4 asercje)" potwierdzone przebiegiem (M2: dokładnie 4 asercje).
  Insert w `watchZerosLocked` (`:197`) — nadal zielony pod mutacją (uwaga 2).
- **Propozycja:** patrz uwaga 2.

### U7 — OK

- **Plik/miejsce:** `Sources/MeetNotesRecording/MicrophoneSources.swift:59–66` (`RawMicrophoneSource.reopen`)
- **Stan:** OK — dokładnie propozycja: gdy `open()` zwróci `""` (spóźniony `stop()`), bez zdarzenia.
  Kompletność sprawdzona grepem: jedyne miejsce emitujące `.deviceChanged` z pustym UID to
  `open()` → `reopen()` w `RawMicrophoneSource`; `SystemTapSource.rebuild` (`:110–123`) bierze UID
  z `CoreAudioDevices.uid(of:)` (niepusty, `throws` przy błędzie) — tam ścieżki `""` nie ma.
  Spóźniony `.deviceChanged(uid)` z `SystemTapSource.rebuild` po `stop()` istnieje, ale z realnym
  UID i jest odrzucany przez `finishing` — jak opisano przy P5/P8. Bez testu (Core Audio) — zgodnie
  z raportem.
- **Propozycja:** brak.

## 2. Test `failedTrackKeepsItsReasonThroughStallAndResume` — kontrole mutacyjne

**Plik/miejsce:** `Tests/MeetNotesRecordingTests/SessionRecorderTests.swift:250–273`.

Scenariusz jest niebezwzględny (4 asercje, wszystkie mogą paść): `system` — `.failed("reopen: A")`
w k=1, brak porcji; `mic_aec` — stalled30s (k=30), `.failed("reopen: B")` (k=35), porcje od k=41;
`mic_raw` podaje przez całą sesję. Wyniki mutacji (każda przywrócona, drzewo czyste):

| Mutacja | Wynik | Zgodność z raportem |
|---|---|---|
| M1 usunięcie `!failedTracks.contains` | **czerwień**, 2 asercje (269, 272) | ✅ raport: „2 asercje" |
| M2 usunięcie `failedTracks.insert` w `.failed` | **czerwień**, 4 asercje (268–272) | ✅ raport: „4 asercje" |
| M3 zdjęcie warunku `stalledTracks.contains` | **zieleń** (53/53) | ❌ nieprzypięte, raport milczy — **uwaga 1** |
| M4 usunięcie `failedTracks.insert` w `watchZerosLocked` | **zieleń** (53/53) | ❌ nieprzypięte — **uwaga 2** |
| M5 usunięcie `stalledTracks.remove` | **zieleń** (53/53) | ❌ nieprzypięte — **uwaga 3** |

Oba zachowania wskazane w zakresie (warunek U2 + insert `.failed`) są więc przypięte; test nie jest
bezwzględny dla pozostałych trzech mutacji bloku recovery.

### UWAGA 1 — warunek `stalledTracks.contains` nieprzypięty (M3 zielony)

- **Plik/miejsce:** `SessionRecorderTests.swift:250–273` vs `SessionRecorder.swift:152`
- **Problem:** po zdjęciu `stalledTracks.contains(trackID)` z warunku recovery cały zestaw jest
  zielony (53/53). Mutant emituje `track.recovered` przy **każdej** porcji każdego toru bez
  realnej awarii (w tym `mic_raw` co sekundę) — żadna asercja tego nie łapie: `mic_aec` jest
  wykluczony przez `failedTracks`, `system` nie daje porcji, a `mic_raw` nie jest sprawdzany.
  Ten sam test mógłby to przypiąć jedną linią.
- **Propozycja:** w nowym teście dodać
  `#expect(!events.contains { $0.type == .trackRecovered && $0.trackID == "mic_raw" })`
  (`mic_raw` nigdy nie stawał — nie ma prawa dostać recovery).

### UWAGA 2 — insert `failedTracks` w `watchZerosLocked` nadal zielony pod mutacją (M4)

- **Plik/miejsce:** `SessionRecorder.swift:197`; test `systemTrackOfPureZerosIsFlagged`
  (`SessionRecorderTests.swift:135–143`)
- **Problem:** runda 2 warunkowała oba inserty (U4), ale testem przypięła tylko ścieżkę `.failed`.
  Usunięcie `failedTracks.insert` w `watchZerosLocked` zostaje zielone — `systemTrackOfPureZerosIsFlagged`
  kończy się w chwili ostatniej porcji zer, więc nadzór nie ma okazji dopisać `stalled30s`.
  To dokładnie ta luka pokrycia, którą zgłaszała U4 dla `:187`, i raport jej nie odnotowuje
  (opisuje sam kompromis zapisu, nie zieloność mutacji). Skutek mutanta: tor z `allZeros60s`,
  któremu źródło potem umrze, dostaje `stalled30s` nadpisujące przyczynę — regresja P2.
- **Propozycja:** rozszerzyć test o dalsze ~40 s ticków **bez** porcji po oknie zer i asercję
  `failure == "allZeros60s"` (brak `stalled30s`); albo zapisać w raporcie wprost, że insert
  w `:197` jest nieprzypięty.

### UWAGA 3 — `stalledTracks.remove` nieprzypięte (M5 zielony)

- **Plik/miejsce:** `SessionRecorder.swift:155`; test `stalledTrackThatResumesIsNotLeftFailed`
  (`SessionRecorderTests.swift:211–229`)
- **Problem:** usunięcie `stalledTracks.remove(trackID)` zostaje zielone — tor zostaje w
  `stalledTracks`, więc każda kolejna porcja ponawia `track.recovered` (duplikaty w dzienniku
  co porcję), a test sprawdza tylko `contains`, nie liczbę zdarzeń. Raport deklaruje „bez testu"
  tylko dla U1 (błąd zapisu); to jest inna mutacja i da się ją przypiąć bez wstrzykiwania błędów.
- **Propozycja:** w `stalledTrackThatResumesIsNotLeftFailed` zmienić asercję na liczbę:
  `events.filter { $0.type == .trackRecovered && $0.trackID == "system" }.count == 1`.

### UWAGA 4 — `try?` + bezwarunkowy insert w `catch` przy `source.start()` (reszta klasy U4)

- **Plik/miejsce:** `SessionRecorder.swift:103–104`
- **Problem:** ostatnie miejsce starego wzorca: `try? journal.append(.trackFailed)` +
  bezwarunkowy `failedTracks.insert`. Przy błędzie zapisu dziennika tor nie ma w dzienniku
  **żadnego** `track.failed`, a insert blokuje nadzór (brak też `stalled30s`) — dokładnie skutek,
  który U4 likwiduje w `.failed`/`allZeros` („niech wtedy zapisze go nadzór"). Poza literą U1–U7
  (U4 wskazywała `:162`/`:187`), ale przeczy teraz udokumentowanej w raporcie zasadzie
  „insert tylko po udanym zapisie". Mutacja tego insertu jest czerwona (test
  `stallDoesNotOverwriteEarlierFailure`, jak w rundzie 1) — chodzi wyłącznie o wzorzec `try?`.
- **Propozycja:** dopasować do wzorca P3 (`do { append; insert } catch {}` — tu bez ponowienia,
  zdarzenie jednorazowe) albo zapisać kompromis jednym zdaniem w raporcie obok U4.

## 3. Zachowanie poza zakresem; CLI vs plany B/C

- **Kod (poza CLI):** zmiany w `SessionRecorder`/`MicrophoneSources` to dokładnie U1/U2/U4/U7 —
  każda zmiana zachowania jest treścią poprawki. Przełożenie `zeroResolved.insert` przed `do`
  w `watchZerosLocked` (`:194`) nie zmienia zachowania przy udanym zapisie i jest częścią
  opisanego kompromisu U4. Poza zakresem nie znaleziono nic.
- **CLI — grep wywołań w planach 02/03:** OK. Wszystkie opcje przekazywane `meetnotes-cli`
  w planach B/C (i A10 w planie 01) to `--seconds`, `--silence`, `--max-lag-ms`, `--language`,
  `--shape`, `--run`, `--no-aec`, `--no-system` — wszystkie w `valued ∪ known`
  (`Sources/meetnotes-cli/CLI.swift:20–21`), więc walidacja nieznanych opcji ich nie odrzuci.
  `positional` (`CLI.swift:61–67`) poprawnie pomija wartości opcji z `valued` — dla wywołań
  z planów (`probe <baseURL> <model> <rola> [--language pl]`, `transcribe <katalog> <baseURL>
  <model> --language pl [--shape X] [--run ID]`, `session-from-file <plik> <katalog>`,
  `models <baseURL>`, `record <katalog> …`, `fit <wzorzec> <nagranie> [--max-lag-ms N]`) liczba
  argumentów pozycyjnych się zgadza także przy opcjach przed ścieżkami. Sygnatury `option`/
  `positional`/`readAnyAudio` bez zmian (kod literalny B4/C4 się skompiluje). Składnia
  `--opt=wartość` nie jest używana w planach (teraz daje 64 — bez wpływu).
- **Dymy CLI (bez sprzętu):** `fit --max-lag-ms 100 /nie/ma/a` → `usage`, 64 (przed poprawką
  „100" był pozycyjnym — rozróżniające, zgodne z raportem); `record /tmp/x --second 5` →
  `nieznana opcja: --second`, 64, katalog nie powstaje; `fit a b --max-lag-ms 100` → błąd
  otwarcia pliku, 1 (wartość pominięta przy pozycyjnych). Odrzucanie nieznanych opcji i pomijanie
  wartości to decyzje poz. 3+4 z `S3-S4-poprawki-decyzje.md` — w zakresie.
- **U6 (walidacja ≤ 0)** — bez zmian względem rundy 1: udokumentowane w „Odchyleniach" (pkt 7),
  zachowanie świadome. OK.

## 4. Liczby: plany i runbook

- **Baseline:** 53 = 47 + 6 potwierdzony (`scripts/test.sh` = 53/53; 47 po E1, +5 runda 1,
  +1 nowy test w rundzie 2). Runbook §2 nota „+6 od S6" ✓.
- **Wartości żywe w planach — wszystkie na stanie +6, spójne z runbookiem:** B: `57/57` (B1),
  `64/64` (B2), `71/71` (B3), `76/76` (B4, po E2); C: `86/86` (C1), `90/90` (C2), `98/98` (C3),
  `105/105` (C4, po E3); E2 `76/76`, E3 `105/105`, plan 04 `105/105`. Runbook: S6 = 71,
  S7 = 76, S8 = 76, S10 = 98, S11–S18 = 105 — zgadza się co do sztuki. Notka C3
  „90 z poprzednich zadań" też przesunięta (84 → 90) ✓. Commit `1040312` zmienia wyłącznie liczby
  (i notę) — nic poza nimi ✓.
- **Wartości historyczne nietknięte zgodnie z wytyczną:** `[x]` w planie 01/05 (`47/47`, `44/44`
  itd.), statusy „przebieg kontrolny … 99/99" (plan 05 l. 15/39/258/423/716, plan 00, runbook §6),
  kody HTTP `400/422`. Żywych oczekiwań na starych wartościach (51/58/65/70/80/84/92/99) nie ma.
- **Problem:** brak.

## Formalne

- Kontrole mutacyjne wykonane tymczasowo na kopii roboczej i przywrócone przez
  `git checkout -- Sources/MeetNotesRecording/SessionRecorder.swift`; `git status --porcelain`
  czysty przed i po (także na końcu przeglądu).
- Odchylenie procedury przeglądu: dym `record /tmp/mn-r2-smoke --seconds 5` uruchomił realne
  5 s nagrania ze sprzętu (TCC odziedziczone po terminalu; `koniec: hardLimit`). Nie było to
  zamierzone (miało sprawdzać `positional`); wynik nie jest użyty w ocenie, katalog usunięty.
  Nagrywania jako przedmiotu przeglądu to nie zmienia — P5/P8/U7 i tak czekają na A10.
- Raport poprawek („Runda CLI", „Runda 2") nie zawiera odwołań do nieistniejących kroków;
  cytowane liczbę testów i mutacje sprawdzone przebiegiem. Hash `1040312` = „Plany +6" zgodny
  z opisem w zadaniu.
