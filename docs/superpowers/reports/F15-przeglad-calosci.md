# Faza 1.5 (+1.5b, 1.6, Coming up) — przegląd całości przed scaleniem do `master`

2026-10-19, Opus. Zakres: `master..faza15` (`762c18d..02ca8ae`), 179 commitów, 203 pliki, w tym `Sources/`
80 plików (+7847/−386) i `Tests/` 46 plików (+3341/−3). Pkt 13 speca 1.5 (§9) i pozycja 1.5b w `ROADMAP.md`. Przegląd tylko do odczytu;
poprawek w kodzie nie ma (mutacje cofnięte `git checkout`).

`scripts/test.sh` na `02ca8ae` (ostatnia linia): `test.sh: 353/353 testów uruchomionych i zaliczonych.` (`check-bundle: OK`)

**Wynik: 0 blokujących, 4 do poprawy, 8 do BACKLOG.** P1, P2 i P4 są zrobione w `reports/F15-poprawki-P1-P2-P4.md`
(355/355), a P3 w dokumentach przy scaleniu. W `BACKLOG.md` otwartych pozycji jest dziś 34 (`- [ ]`); 8 nowych
z tego raportu jeszcze tam nie trafiło (P3).

## Co sprawdziłem

- **Retencja audio** (`Sources/MeetNotesNotes/Recordings.swift`, `AudioRetention`): kasuje tylko `*.caf` z najwyższego
  poziomu katalogu sesji. Warunki: wiek liczony od `sessionStarted.wallClock`, ukończony najnowszy przebieg (transkrypt bez
  luk), sesja spoza `busySessions` (nagrywana, transkrybowana, korekta, tytuł, notatka). Znacznik `audio-deleted.json`
  powstaje przed kasowaniem. Nieczytelny dziennik daje `isExpired == false`, więc audio zostaje. Przebieg przerwany, w toku
  albo z lukami też zostawia audio. `AppModel.run` nie uruchomi transkrypcji bez audio, więc pusty `runs/<id>/` nie przesłoni
  gotowego transkryptu.
- **Przenoszenie folderu** (`RecordingsMove.run` i `AppModel.changeRecordingsLocation`): kopia, weryfikacja (lista
  i rozmiary), `commit` (zapis ustawień), dopiero potem usunięcie. Od ustawienia `recordingsMove` do końca przebiegu blokują
  się: nagrywanie (też auto-start z oferty), transkrypcja, wznowienie, usuwanie, retencja, My notes, tytuł, powiązanie
  z kalendarzem, generowanie i korekta (`NotesModel.isMoving`). Autozapis My notes jest opróżniany przed kopią.
  Sprawdzenie i ustawienie `recordingsMove` dzieje się synchronicznie na MainActor, więc nic nie wejdzie między nie.
- **Wyścigi na MainActor:** między `transcribing.remove` a `correcting.insert` i `titling.insert` (`AppModel.run` →
  `NotesModel.afterTranscription`) nie ma punktu zawieszenia, więc retencja ani przenoszenie nie trafią w tę przerwę.
- **Dziennik i nowe zdarzenia:** `track.muted`, `track.unmuted` i `track.audible` są tylko dodane. `SessionSummary.Mute`
  i `audibleFrame` są opcjonalne. Stare dzienniki i `summary.json` czytają się bez zmian:
  `journalAndSummaryFromBeforeMutingLoadUnchanged` i `SessionSummaryTests` (`rebuilt.tracks.allSatisfy { $0.mutes == nil
  && $0.audibleFrame == nil }`). Wyciszenie trwające przy Stop zamyka się na ostatniej ramce, a po awarii zostaje otwarte
  („to the end”). Starszy build nowego dziennika nie przeczyta. To jest udokumentowane i po scaleniu przestaje mieć
  znaczenie, bo `master` = nowy build.
- **Zapisywane typy (lekcja E6):** nowe pola są wyłącznie opcjonalne (`Preset.languageAuto`, `RunSnapshot.language`,
  `Provider.kind`, `GlobalSettings.recordingsPath/keepAudio*/meetings`, `MeetingSettings.*`, `Utterance.echoOfThem`,
  `CalendarLink`). Fikstury fazy 1: `phase1-presets.json`, `phase1-providers.json`, `phase1-input.json` oraz
  `settingsWithoutRecordingFieldsStillLoad`.
- **Wyciszanie w rdzeniu** (`SessionRecorder.setMuted` i ścieżka porcji): cyfrowa cisza tej samej długości. Wykrywacz zer
  i poziom pracują na surowym dźwięku, a próg ciszy na zapisanym (decyzja 4). Zdarzenia zapisują się pod tą samą blokadą,
  więc `frameIndex` trafia na granicę porcji.
- **Klucze:** `ProviderError.http` powstaje tylko w `checkedBody` (`HTTPClient.swift:22`), który maskuje klucz w treści błędu; `ProviderCheck.describe` nie dołącza treści. `print` jest tylko
  w sondach i migawkach i nie wypisuje kluczy. Test połączenia przed zapisem nie dotyka pęku kluczy. Literały testowe
  nie wyglądają jak klucz.
- **Bramki i mutacje:** w raportach są zapisane mutacje dla: warunku ukończonej transkrypcji, kasowania tylko `*.caf`,
  weryfikacji kopii (F15-T13-B), sprzątania własnej kopii (R2) i wszystkich bramek wyciszania M1–M11 (F15b). Dwie bramki
  bez zapisanej mutacji sprawdziłem sam (`scripts/test.sh --filter retention`, potem `git checkout`):
  - usunięty filtr `skip` w `AudioRetention.plan` → padają `retentionKeepsAudioWithoutFinishedTranscription`
    i `retentionPlanMatchesWhatRetentionDeletes`;
  - usunięty zapis znacznika `audio-deleted.json` → pada `retentionDeletesOnlyCafAndOnlyAfterTheTerm`.
- **Hashe w raportach:** 27 plików (CLAUDE.md, BACKLOG, ROADMAP, 23 raporty, 1 spike), 85 unikalnych hashy. Wszystkie
  istnieją, są przodkami `faza15`, a opisy zgadzają się z tematami commitów. `faza-1.5a` → `b4f5804` jest poprawny
  (commit zamykający T13-B). Sprawdzał Haiku. Mimo polecenia „tylko odczyt” agent zostawił w katalogu worktree
  25 pustych plików `docs_superpowers_*.md`, nieśledzonych. Usunąłem je; główny checkout jest czysty.
- **Zgodność z §11.5 i decyzjami:** Keep audio 7/14/30/90/Forever z domyślnymi 30, R1 (potwierdzenie skrócenia z liczbą
  i rozmiarem, ta sama reguła `plan`), R2, R3, R4, decyzje wyciszania (1)–(4), `track.audible` jako decyzja (b),
  ElevenLabs bez `language_code` dla Auto, Coming up D1. Nie znalazłem rozjazdów.

## Zakres — czego NIE przejrzałem linia po linii

Widoki SwiftUI (`PresetsView`, `SettingsView`, `TemplatesView`, układ `MeetingTabs` i `MeetingDetailView`,
`DesignSystem`), `Snapshots.swift`, `Probes.swift`, `AudioProcessMonitor`, `EventKitCalendar`. Zgodność wizualna
z §11 opiera się na trzech odbiorach na żywo, przeglądzie 50 migawek (F15-T13-B), `F16-przeglad.md` i `F15b-wyciszanie.md`.
Detektory 1.6 (`OfferDetector`, `EndDetector`) przeczytałem pod kątem danych i wyścigów; ich logikę szczegółowo omawia
`F16-przeglad.md` (8 uwag w BACKLOG). Cel aplikacji nie ma testów (to znana pozycja fazy 2), więc blokady R3
i powiązanie `busySessions` z retencją sprawdził tylko odbiór na żywo.

## Uwagi

### Do poprawy

**P1. Ścieżka „`commit` rzuca → nic nie jest usuwane” w `RecordingsMove.run` nie ma testu.**
`Sources/MeetNotesNotes/Recordings.swift`, `run`, blok `do { try await commit() } catch { throw fail(...) }`. To bramka
przed utratą danych: gdy nie da się zapisać nowej lokalizacji, stare spotkania muszą zostać, a własna kopia ma zniknąć.
Kod jest poprawny. **Korekta po poprawkach:** to twierdzenie było za mocne. `moveCopiesVerifiesThenDeletes` już woła
`commit: { throw NoSave() }` i pada przy mutacji „kasuj przed `commit`” (mój grep szukał słowa `commit` w treści testu
i go nie znalazł). Brakowało tylko sprawdzenia komunikatu „Nothing was deleted” i usunięcia folderu celu utworzonego
przez przebieg.
**Propozycja (Sonnet):** test z `commit: { throw … }`. Ma sprawdzić, że stare pliki zostały, cel jest pusty albo usunięty,
a `Failure` zawiera „Nothing was deleted”. Mutacja: usuwanie przed `commit` → test pada.

**P2. `RunDirectory.latestRunID` decyduje teraz o kasowaniu audio.**
`Sources/MeetNotesTranscription/TranscriptionRunner.swift:41`. Pozycja jest w BACKLOG od T5, ale powstała przed
retencją. `isValid(runID:)` przepuszcza każdą nazwę z liter, cyfr i `-_.`, a sortowanie jest leksykalne. `--run debug`
z CLI sortuje się za każdym przebiegiem aplikacji (`2026-…`), bo litery są w ASCII po cyfrach. Scenariusz: przebieg
aplikacji kończy się z lukami (do ponowienia trzeba audio), a w `runs/` leży kompletny `debug`. Wtedy
`transcriptionFinished` widzi `debug`, retencja po N dniach kasuje audio i wznowienie przebiegu aplikacji jest
niemożliwe. Lista spotkań pokazuje też transkrypt `debug` zamiast przebiegu aplikacji. Dotyczy tylko sesji, w których
używano CLI z własną nazwą przebiegu. Odwrotny błąd (zabłąkany wpis bez transkryptu) jest bezpieczny: audio zostaje.
**Propozycja (Sonnet):** `latestRunID` bierze tylko katalogi pasujące do wzorca `AppModel.sessionName`
(`yyyy-MM-dd'T'HH-mm-ss'Z'-xxxx`). Inne nazwy pomija albo sortuje po dacie modyfikacji. Test: `debug` obok przebiegu
aplikacji nie wygrywa. Mutacja: stary filtr.

**P3. Rozjazdy dokumentów ze stanem (mechaniczne, Haiku).**
- `ROADMAP.md`, sekcja 1.6, ostatnie zdanie: „„Coming up" i integracje Google/Outlook/Slack zostają”. Coming up jest
  zrobione (`F16-coming-up.md`, `02ca8ae`).
- `ROADMAP.md`: „Faza 1.5b (w toku)” i wiersz „Przegląd całości przez Opusa, potem scalenie” wymagają aktualizacji
  po decyzji o scaleniu. Raport: ten plik.
- `CLAUDE.md`, „Kod:”: brak modułów `MeetNotesNotes` (notatki, szablony, retencja i przenoszenie) i `MeetNotesMeetings`
  (kalendarz, wykrywanie, Coming up).
- `CLAUDE.md`, „Stan”: po scaleniu `master` = faza 1.5 + 1.6. Wpisać tagi i raport.
- `BACKLOG.md`: dopisać B1–B8 z tego raportu, P2 przenieść z sekcji T5 z dopiskiem o retencji.

**P4. Testy „cisza przez godzinę” w `OfferDetectorTests` nie mogą paść (F16-przeglad #2, nadal otwarte).**
`BACKLOG.md:99`; od `49c4980` plik testów się nie zmienił. Tiki co 5–60 s przy `maxTickGap = 3` zerują `micSince`
w każdym kroku, więc oferta rozmowy nie powstaje w ogóle i asercje przechodzą nawet po usunięciu każdego wyciszenia.
Liczą się do 353/353, a nie sprawdzają bramki (wyciszenie po Stop i po „Not a meeting”). Mutację (e) z planu T3 łapią
dziś inne testy, ale luka „Stop w chwili krótkiego zwolnienia mikrofonu” zostaje bez strażnika. Tę bramkę trzeba
traktować jako „bez testu”, nie jako drobiazg.
**Propozycja (Sonnet):** tiki co 1 s w tych testach (jak `afterManualStopANewCallOffersAgain`). Mutacja: usunięcie
`mutedFamilies.formUnion(lastInput.keys)` → co najmniej jeden z nich pada.

### BACKLOG (bez rundy poprawek)

- **B1. Zakaz wyciszenia obu torów liczy martwe tory jako nagrywające.** `SessionRecorder.setMuted` patrzy na
  `started − muted − ended`. Tor `stalled30s`, `allZeros60s` albo z błędem zapisu nadal się liczy, więc da się wyciszyć
  jedyny żywy tor. Dosłownie zgodne z §11.5 („obu torów naraz”). Do rozważenia przy fazie 2.
- **B2. Wyciszenie toru, który nie wystartował** (np. mikrofon bez zgody) zwraca `false`, a pigułka pokazuje „Nothing is
  being recorded”. To mylący komunikat. Do sprawdzenia, czy pigułka w ogóle pokazuje przełącznik dla takiego toru.
- **B3. Awaria aplikacji w trakcie kopiowania** zostawia częściową kopię w celu. Ustawienia wskazują stare miejsce, więc
  danych nie brakuje, ale ponowna próba dostaje „Choose an empty folder”. Sprzątanie jest tylko w ścieżce błędu, nie po
  restarcie.
- **B4. Dwie osie czasu w widoku spotkania.** `TrackProblem` liczy „Sound started at” jako `offsetSeconds +
  frame/sampleRate`, a `MuteNote` liczy przez `SessionClock` (z dryfem zegara). Przy długim nagraniu różnica może
  wynieść sekundy.
- **B5. `NotesModel.runCorrection` zapisuje `corrected.json` przez `try?`.** Błąd zapisu ginie po cichu. Skutek jest
  łagodny: „Improve transcript” wraca, bo korekty nie ma. Lepiej zgłosić przez `report`.
- **B6. Wyścig `NotesStore.updateMeta`** (BACKLOG T5) ma od 1.6 więcej piszących: powiązanie z kalendarzem przy starcie
  nagrania oraz link i unlink obok autotytułu (poza MainActor) i ręcznego tytułu. Okno wciąż jest poniżej 1 ms
  (odczyt–zmiana–zapis małego JSON), ale przegrany zapis może teraz zgubić powiązanie wydarzenia, nie tylko tytuł.
  Poszerzyć opis pozycji.
- **B7. Pierwsze uruchomienie po aktualizacji z fazy 1 stosuje domyślne 30 dni bez pytania R1.** To zgodne z decyzją
  (domyślnie 30), ale faza 1 nie kasowała nic. W `.devdata` najstarsza sesja jest z 2026-10-13, więc pierwsze audio
  zniknie przy starcie aplikacji ok. 2026-11-12. Patrz „Dla użytkownika”.
- **B8. `EndDetector`:** gdy pytanie wisi z sygnału `silence`, a potem przychodzi `callReleased`, treść pytania się nie
  zmienia (`shown != nil` → `nil`). Kosmetyka.

## Dla użytkownika (decyzje i STOP)

1. **Scalenie `faza15` → `master`.** Testy 353/353, 0 blokujących, 4 do poprawy. Do wyboru:
   - **`--no-ff`** z opisem faz (1.5a, 1.5b, 1.6, Coming up) — zalecane, bo `master` dostaje jeden czytelny commit na całą
     fazę 1.5;
   - **fast-forward** — możliwe, bo `faza15..master` = 0.

   `faza15` jest wyciągnięta w głównym checkoucie (`/Users/michalprzytulski/meetnotes`), a ten raport leży na gałęzi
   `claude/vigilant-austin-cd58d0` (`faza15` + raport). Wariant: scalić tę gałąź do `master` tutaj (`master` nie jest
   nigdzie wyciągnięty), potem przesunąć `faza15` fast-forwardem w głównym checkoucie. P1, P2 i P4 przed scaleniem albo po:
   Twoja decyzja. Push też jest Twoją decyzją.
2. **Tagi:** propozycja `faza-1.6` → `49c4980` (koniec 1.6 na `faza15` z przeglądem F16) i `faza-1.5` na commicie
   scalenia w `master`. Istnieją już `faza-1.5a` i `faza-1.5b-wyciszanie`.
3. **Nadal otwarte i nieblokujące:** pomiar T11 (Auto, para PL+EN); poczekalnia Teams (F16-przeglad #1, spec 1.6 §6
   pkt 2) bez pomiaru i decyzji przy włączonym auto-starcie; lekarz, urodziny i OOO pokryte tylko testami.
4. **T11 a retencja:** pomiar porównuje kilka transkrypcji tego samego audio, a domyślne 30 dni skasuje je po pierwszej
   ukończonej transkrypcji. Nagranie korpusu trzymać z „Keep audio: Forever” na czas pomiaru albo skopiować `*.caf` poza
   folder nagrań.
5. **Sprzątanie po scaleniu (Haiku):** wszystkie gałęzie lokalne są przodkami `faza15`. Worktree `agent-*`,
   `adoring-pasteur`, `distracted-babbage`, `eloquent-newton` (`faza15-design-b`), `faza16` i `infallible-wu` można
   usunąć po `git status --porcelain` każdego z nich i tylko wtedy, gdy są czyste. Zdalne `faza1` i `faza16` usuwa
   tylko push, więc to Twoja decyzja.
