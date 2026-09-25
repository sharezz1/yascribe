# Raport — poprawki po przeglądach S3 i S4

**Sesja:** poprawki S3+S4. **Wykonawca:** Claude (K), Opus 5.5. **Gałąź:** `faza1`.
**Wejście:** `docs/superpowers/reports/S3-przeglad.md` (pkt 1–9), `docs/superpowers/reports/S4-przeglad.md` (P1–P12).

## Commity

| Hash | Tytuł | Zakres |
|---|---|---|
| `6241e9c` | Raporty: przeglady S3 i S4 | oba przeglądy, bez zmian |
| `7885c8a` | CLI: walidacja opcji, fit bez cichego obcinania, test fit na plikach | S3-1…S3-9 |
| `823dc51` → po amendzie: `git log -1` | Rdzen: pierwsza przyczyna awarii toru zostaje, tor moze ozyc, sprzatanie po stop | P1–P9, P12 + spec rdzenia; w amendzie P10 (`S4.md`) i ten raport |

`823dc51` to hash **przed** `--amend`, którym dodano ten raport i poprawkę `S4.md` — obiekt bez raportu. Aktualny hash: `git log -1` na `faza1`.

## Wynik testów

`scripts/test.sh` → kod 0, ostatnia linia:

```
test.sh: 52/52 testów uruchomionych i zaliczonych.
```

47 → 52 (+5 nowych `@Test`; jeden istniejący rozszerzony).

## S3 — CLI

| Punkt | Stan | Co zrobione |
|---|---|---|
| S3-1 RAM bez limitu | ✅ | `readAnyAudio` odrzuca plik dłuższy niż `maxSeconds` (domyślnie 3600 s) przed czytaniem; `reserveCapacity`. Komentarz `ponytail:` opisuje limit. |
| S3-2 ciche `break` | ✅ | Pusty odczyt / brak `int16ChannelData` przed końcem pliku = `throw` z numerem ramki. |
| S3-3 liczby w opcjach | ✅ | Nowe `CLI.number(_:_:)`: podana opcja bez wartości, z wartością nieliczbową, nieskończoną albo ≤ 0 → komunikat, `usage`, `exit(64)`. Dla `--seconds`, `--silence`, `--max-lag-ms`. |
| S3-4 walidacja po efekcie ubocznym | ✅ | `fit` pobiera oba argumenty pozycyjne (i `--max-lag-ms`) przed otwarciem plików. `fit /nie/ma/ref.aiff` → 64. |
| S3-5 `--seconds` > 4 h | ✅ | Podane `--seconds` usuwa standardowy `HardLimitCondition` i dokłada własny. |
| S3-6 SIGINT | ✅ | `sigint.cancel()` i `signal(SIGINT, SIG_DFL)` po zakończeniu. |
| S3-7 ticker | ✅ | Pętla `while (try? await Task.sleep(...)) != nil` — po anulowaniu nie ma już `tick()`; do tego `await ticker.value`. |
| S3-8 podwójne „koniec:" | ✅ | Usunięty wydruk w pętli; zostaje ten z `summarize` (obejmuje „BRAK (awaria)", na nim opiera się A10 krok 8). |
| S3-9 brak testu `fit` | ✅ | Test `fitFilesFindsDelayedCopyInRealFiles`: wzorzec zapisany przez `AVAudioFile` (wav), nagranie przez `CAFWriter` z opóźnieniem 240 ramek i wzmocnieniem 0,06 → `lagFrames == 240`, `gain ≈ 0,06`; do tego odczyt bajt w bajt i odrzucenie pliku ponad limit (S3-1). |

Dymny test CLI bez sprzętu (binarka debug): brak argumentów → 64; `fit /nie/ma/ref.aiff` → 64;
`fit a b --max-lag-ms -3` → 64; `record /tmp/mn-x --seconds abc --no-system --no-aec` → 64 (katalog
nie powstaje); `record /tmp/mn-x --seconds` → 64; `summarize /nie/ma` → 1. Samego nagrywania nie
uruchamiałem (sprzęt/uprawnienia).

## S4 — rdzeń

| Punkt | Stan | Co zrobione |
|---|---|---|
| P1 wybuchy awarii konwersji | ✅ | `FormatConverter.shouldReport(before:after:)` — pierwsza awaria i każde przekroczenie tysiąca na sumie; używane w `HALCapture` i `VoiceProcessedMicrophoneSource`. Test `conversionFailuresAreReportedEvenWhenTheyComeInBursts`. |
| P2 stall nadpisuje przyczynę | ✅ | Zbiór `failedTracks` (błąd `source.start()`, `.failed` ze źródła, `allZeros`) — nadzór go pomija. Test `stallDoesNotOverwriteEarlierFailure`; mutacja (usunięcie warunku) → czerwień. |
| P3 `try?` + bezwarunkowy insert | ✅ | `do { append; insert } catch {}` — niezapisane zdarzenie ponawia się przy kolejnym `tick()`. Bez testu (wymagałby wstrzyknięcia błędu zapisu dziennika). |
| P4 test nie przypina 30 s | ✅ | `deadTrackIsFlaggedWhileOtherContinues`: po k=29 `failure == nil`, po k=30 `stalled30s`, na końcu `mic_raw` bez `failure`. Mutacje `* 100`, `* 10`, `/ 10` → kod 1 (sprawdzone przebiegiem, przywrócone). |
| P5 „mic_aec stopped" bez stopu | ✅ | Callback obserwatora robi `removeTap` + `engine.stop()` przed zgłoszeniem. Treść zdarzenia bez zmian (E3 opiera się na `failure != nil` dla `mic_aec`). |
| P6 tor nie wraca do życia | ✅ | Nowe zdarzenie `track.recovered` przy pierwszej porcji toru ze `stalledTracks`; `SessionSummary` zdejmuje `failure`. Test `stalledTrackThatResumesIsNotLeftFailed`. Spec rdzenia (l. 152) uzupełniony. |
| P7 30 s od startu sesji | ✅ | `lastChunkByTrack[trackID]` = czas `track.opened`. |
| P8 wyścig `stop()`/przebudowa | ✅ | Flaga `stopped` w `RawMicrophoneSource` i `SystemTapSource`; `open()`/`startCapture()` po `stop()` nie podpinają capture (zatrzymują go), `rebuild()` po `stop()` sprząta tap i urządzenie zbiorcze. Bez testu — wymaga Core Audio. |
| P9 CAF otwarty po błędzie dziennika | ✅ | `TrackWriter.close`: przy błędzie `append` zamyka CAF i rzuca dalej. |
| P10 hash w S4.md | ✅ | `006e69b` → `4b8025a`, „9 plików" → 10 (z opisem amendu). |
| P11 fsync pod blokadą w `tick()` | ⏭ świadomie nie | Patrz „Decyzje". Komentarz `ponytail:` w `tick()`. |
| P12 niesanityzowany `trackID` | ✅ | `SessionRecorder.isSafeTrackID` (`[A-Za-z0-9_-]+`); zły tor → `track.failed("invalidTrackID")`, bez pliku. Test `unsafeTrackIDNeverLeavesSessionDirectory`. |

Poza punktami, uwaga formalna z S4 o śmieceniu `$TMPDIR` przez testy — nie ruszana (poza zakresem propozycji). Nowy test `fit` po sobie sprząta.

## Odchylenia od planu (z powodem)

1. **`CLI.swift` nie jest już bajt w bajt z A9.** Wszystkie S3-1…S3-8 wymagały zmian w kodzie z planu. Sygnatury, na które liczą plany B i C (`CLI.option`, `CLI.positional`, `CLI.readAnyAudio` zwracające `(samples, rate, channels)`), zostały bez zmian; `CLI.readAnyAudio` przekazuje do `AudioFit.readAnyAudio`.
2. **Rdzeń `fit` przeniesiony do biblioteki** (`AudioFit.fitFiles`, `AudioFit.readAnyAudio`, `AudioFit.analysisRate` w `MeetNotesRecording`, które importuje teraz AVFoundation i `MeetNotesSessionFormat` — zależność już była w grafie). Powód: cel wykonywalny nie ma sensownego testu z `scripts/test.sh`; test `fit` na plikach (S3-9) potrzebuje kodu w bibliotece.
3. **Limit 1 h w `readAnyAudio`** dotyczy też `session-from-file` z planu C (używa `CLI.readAnyAudio`). Plan C używa tam krótkiego pliku z `say`, więc nie koliduje.
4. **E1 krok 4/5/7 (literalny kod):** zmieniony warunek raportowania błędów konwersji (P1), `try?` przy stall (P3), callback watchera `mic_aec` (P5), zbiór `failedTracks` (P2). Zgodnie z poleceniem — propozycja przeglądu ma pierwszeństwo.
5. **Nowy typ zdarzenia `track.recovered`** w `JournalEvent.Kind` (P6). Jedyny `switch` po `e.type` w kodzie i planach to `SessionSummary.rebuild` — obsłużony.
6. **Spec rdzenia** (`2026-09-24-rdzen-nagrywania-design.md`, l. 152) — dopisane: liczenie od `track.opened`, brak nadpisywania innej awarii, `track.recovered`. Tylko to jedno zdanie.
7. **Liczba testów 47 → 52.** Dalsze plany mają zaszyte oczekiwane liczby (`51/51`, `58/58`, `65/65` w B; `70/70`, `99/99` w E2/E3; `80/80`, `84/84`, `92/92` w C). Każda będzie teraz o **+5** wyższa. Planów nie zmieniałem — patrz pytania.

## Decyzje przy wariantach

- **S3-1:** wariant „jawny limit + błąd", nie „offset/długość" — mniejsza zmiana, a `fit` i `session-from-file` z planu i tak czytają krótkie pliki. Limit 3600 s jako parametr z wartością domyślną.
- **S3-5:** wariant „nadpisać standardowy limit", nie „udokumentować 4 h" — intencja `--seconds` to twardy koniec podany przez użytkownika.
- **S3-7:** zamiast `cancel()` + `await` dodatkowo pętla kończąca się na wyjątku ze `sleep`, więc po anulowaniu nie ma już ani jednego `tick()` — zachowanie wynika z kontraktu, nie z implementacji `tick()`.
- **S3-8:** zostaje wydruk z `summarize` (A10 krok 8 oczekuje `koniec: BRAK (awaria)`, który daje tylko on).
- **P2:** wariant w rejestratorze (`failedTracks`), nie „pierwsza przyczyna wygrywa" w `SessionSummary` — podsumowanie dalej pokazuje ostatnią awarię, jeśli tor naprawdę zawiódł dwa razy z różnych powodów (np. `.failed("rebuild…")` po stall), a nadzór nie dokłada fałszywego `stalled30s`.
- **P5:** wariant „faktycznie zatrzymać tor", nie zmiana treści — treść „mic_aec stopped, mic_raw continues" i intencja E1 krok 7 („tor zgłasza awarię; surowy mikrofon nagrywa dalej") zostają prawdziwe.
- **P6:** wariant z jawnym zdarzeniem `track.recovered`, nie heurystyka „po `track.failed` przyszły jeszcze dane" w podsumowaniu — dziennik ma pozostać źródłem prawdy, a heurystyka na `frames` myliłaby tor, który nagrywał przed awarią.
- **P8:** flaga `stopped` (propozycja minimalna), nie wspólna kolejka seryjna dla rekonfiguracji i `stop()`.
- **P9:** zamknięcie CAF przy błędzie dziennika (kolejność „dziennik, potem plik" zostaje — `track.closed` nie może wyprzedzić ostatnich ramek na dysku).
- **P11 — świadomie niezrobione.** `SessionJournal.append` ma własną blokadę, więc przeniesienie appendów z `tick()` za `lock.unlock()` jest technicznie możliwe, ale otwiera wyścig z `finish()`, które zamyka dziennik (zapis do zamkniętego `FileHandle`) i może dopisać `track.failed` za `session.ended`. Zysk jest pomijalny: nadzór zapisuje najwyżej jedno zdarzenie na tor na sesję, a ten sam wzorzec (append + fsync pod blokadą) występuje w `handle()` przy każdej luce i kotwicy zegara — dużo częściej. Właściwa poprawka to cały zapis dziennika poza blokadą rejestratora — osobne zadanie (pytanie 2).
- **P12:** walidacja w `SessionRecorder.start()` (propozycja), nie w `SessionDirectory.trackURL` — ta zwraca `URL` bez `throws` i jest używana w planach C/D; zmiana sygnatury rozlałaby się na plany.

## Czego nie uruchamiałem

- `record` na sprzęcie, `check-system-audio` — wymagają mikrofonu/tapu i uprawnień TCC. P5 i P8 (Core Audio, zmiana urządzenia) zweryfikowane tylko kompilacją i przeglądem kodu; sprawdzi je A10 (T6: przepięcie słuchawek).

## Pytania do orkiestratora

1. **Liczby testów w dalszych planach (+5).** Każdy krok „oczekiwane: `N/N`" w planach B, C, E2, E3 będzie rozbieżny o +5 i zgodnie z §0 pkt 3 wykonawca zrobi STOP. Proponuję: albo jednorazowo przesunąć liczby w planach (decyzja użytkownika — plan zmienia tylko on), albo dopisać w runbooku, że oczekiwana liczba = liczba z planu + 5.
2. **P11** — czy wydzielić zadanie „dziennik poza blokadą rejestratora" (np. do E2/E4), czy uznać obecny stan za wystarczający?
3. **`positional` traktuje wartości opcji jako argumenty pozycyjne**, gdy opcja stoi przed ścieżką (np. `record --seconds 5 /tmp/x` → katalog „5"). Poza zakresem przeglądów, nie poprawiałem — plany B/C wołają `positional` z opcjami na końcu. Poprawić przy okazji B4/C4?
4. **Nieznane opcje** (np. literówka `--second 5`) nadal są cicho ignorowane — S3-3 dotyczył tylko wartości. Czy walidować listę opcji per polecenie?

## Runda CLI (pozycje 3+4 z decyzje.md)

Zmiana tylko w `Sources/meetnotes-cli/CLI.swift`: `static let valued` (6 opcji z wartością, w tym `--language`/`--shape`/`--run` z B4/C4); `positional` pomija element stojący zaraz po opcji z `valued`; w `main` każde `--x` spoza `valued ∪ ["--no-aec", "--no-system"]` → `nieznana opcja: …`, `usage`, `exit(64)`. Sygnatury `positional`/`option` bez zmian. Bez nowych `@Test` (kompromis z decyzje.md).

Dymy (bez sprzętu):

| Wywołanie | Wynik | exit |
|---|---|---|
| `fit --max-lag-ms 100 /nie/ma/a /nie/ma/b` | `błąd: Error Domain=com.apple.coreaudio.avfaudio Code=2003334207 … ExtAudioFileOpenURL` | 1 |
| `record /tmp/mn-x --second 5` | `nieznana opcja: --second`, katalog nie powstał | 64 |
| `record /tmp/mn-x --seconds abc --no-system --no-aec` | `--seconds wymaga liczby dodatniej`, katalog nie powstał | 64 |
| `summarize /nie/ma` | `błąd: … journal.jsonl couldn't be opened …` | 1 |

**Odstępstwo od oczekiwania dla dymu `fit`:** oczekiwano „błąd o `/nie/ma/a`, exit 64". Nieosiągalne bez zmiany `fit`: błąd CoreAudio nie zawiera ścieżki, a brak pliku to błąd wykonania (exit 1) — przed poprawką wynik jest identyczny (tam otwierał „100"). Ten dym nie rozróżnia stanu przed/po. `fit` nie zmieniałem (poza zakresem). Dymy rozróżniające, uruchomione na HEAD przed poprawką (`git stash`) i po niej (`/tmp/mn-ref.aiff` z `say`):

| Wywołanie | przed | po |
|---|---|---|
| `fit --max-lag-ms 100 /tmp/mn-ref.aiff /tmp/mn-ref.aiff` | błąd otwarcia pliku („100"), 1 | `błąd: notOurLayout("magic")`, 1 — wzorzec otwarty, odrzucone nagranie (aiff to nie nasz CAF) |
| `fit --max-lag-ms 100 /nie/ma/a` (jedna ścieżka) | błąd CoreAudio, 1 | `usage`, 64 |
| `fit --max-lag-ms -3 …` | `--max-lag-ms wymaga liczby dodatniej`, 64 | to samo, 64 |

Do decyzji: czy `fit`/`summarize` mają w błędzie podawać ścieżkę pliku (osobna drobna zmiana).

`scripts/test.sh`: `test.sh: 52/52 testów uruchomionych i zaliczonych.`
