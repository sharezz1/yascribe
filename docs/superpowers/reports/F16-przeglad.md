# Faza 1.6 — niezależny przegląd (`faza15..faza16`, HEAD f752b79)

2026-10-19. Przegląd tylko do odczytu: bez poprawek i bez commitów. Wejścia to spec `2026-10-16-faza16-kalendarz-design.md`
(§4, §6), plan `2026-10-16-faza16-kalendarz.md`, spike `2026-10-16-faza16-wykrywanie.md` i `F16-odbior.md`.

`scripts/test.sh` (ostatnia linia): `test.sh: 334/334 testów uruchomionych i zaliczonych.` (`check-bundle: OK`)

## Uwagi

### 1. Ważna: poczekalnia Teams bez pomiaru i bez decyzji użytkownika, a auto-start może ruszyć przed dołączeniem

- **Gdzie:** spike §4 („Poczekalnia Teams… niezmierzone… Decyzja przy odbiorze T13”). `F16-odbior.md` nie ma o niej wiersza. Kod: `Sources/MeetNotesMeetings/OfferDetector.swift`, `step`, wybór `fam` (jedynym progiem jest `startSeconds` = 12 s).
- **Problem:** spec §6 pkt 2 wymaga jednego z dwóch: braku pigułki w poczekalni albo opisanego odstępstwa z decyzją użytkownika. Nie ma ani pomiaru, ani decyzji. Ekran przed dołączeniem w Teams zwykle otwiera mikrofon na podgląd poziomu. Jeśli `com.microsoft.teams2.*` trzyma wejście ≥ 12 s, detektor daje `.call` albo, w oknie wydarzenia, `.calendarAndCall`. Przy włączonym auto-starcie to jest `.startRecording`, czyli nagranie przed wejściem na spotkanie (anty-cel #1).
- **Dowód z testów:** `lobbyBlipShorterThanStartSecondsNeverOffers` sprawdza tylko syntetyczny 5-sekundowy impuls, nie poczekalnię.
- **Propozycja:** STOP dla użytkownika przed zamknięciem fazy. Do wyboru:
  - pomiar sondą `MEETNOTES_PROBE=audio` na ekranie przed dołączeniem;
  - jawny wpis odstępstwa z decyzją w `F16-odbior.md`;
  - dłuższy, osobny próg ciągłości dla `.startRecording`.

### 2. Ważna: część testów „cisza przez godzinę” po 3c1b94e nic nie sprawdza

- **Gdzie:** `Tests/MeetNotesMeetingsTests/OfferDetectorTests.swift`:
  - `manualStopSilencesAutoStartForTheSameCall` (`every: 10`);
  - `dismissedOfferStaysQuietForTheWholeMicSession`, część dwugodzinna (`every: 60`);
  - `manualStopDuringAMicBlipStaysQuiet`, część po t0+36 (`every: 5`);
  - `dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp`, część po t0+31 (`every: 5`);
  - `ignoredAppsNeverOffer` i `unknownAppsNeverOffer` (`every: 5`).
- **Problem:** commit 3c1b94e dodał `maxTickGap = 3`: przerwa między tikami większa niż 3 s zeruje `micSince`. Przy tikach co 5–60 s licznik ciągłości zeruje się w każdym kroku, więc oferta rozmowy nie może powstać w ogóle. Te asercje przechodzą nawet po usunięciu każdego wyciszenia.
- **Skutek dla mutacji z planu (T3, krok 4):**
  - Mutacja (e) nie zabija już testu, który plan dla niej wskazuje. Zabijają ją `afterManualStopANewCallOffersAgain` (60 s tików co 1 s) i `retuningKeepsTheMuteAfterManualStop` (600 s).
  - Mutację (c) zabija `dismissedOfferReturnsForANewMicSession`.
  - Mutację (d) zabija pierwszy odcinek `…AcrossHelperProcesses…`.
  - Realna luka: **Stop w chwili krótkiego zwolnienia mikrofonu**. Zamiana `mutedFamilies.formUnion(lastInput.keys)` na `formUnion(active)` w gałęzi `wasRecording` przechodzi cały zestaw testów. Jedyny test tego przypadku jest pusty.
- **Dlaczego ważne:** to ścieżka kryterium 6a. Auto-start po Stop to błąd, którego użytkownik najbardziej nie chce.
- **Propozycja:** w tych przebiegach tiki co 1 s (albo ≤ 3 s), potem ponowić mutację (e) i mutację `lastInput.keys` → `active`.

### 3. Drobna: po nieudanym starcie typu `noSources` oferta i tak znika (poprawka z 79fd410 jest niepełna)

- **Gdzie:**
  - `MeetingMonitor.accept`, czyli `if !model.startRecording(offer:) { present(offer) }`;
  - `RecordingController.start`, w którym `onEnded` puszcza `Task` na MainActorze;
  - `RecordingController.finish`, który woła `hidePanel()`.
- **Problem:** gdy `r.start()` kończy sesję od razu (`finish(.noSources)`), `startRecording` zwraca `false` i monitor znów pokazuje ofertę. Dopiero potem wykonuje się zakolejkowany `finish` → `hidePanel()`, który chowa ofertę i ustawia `mode = .recording`. Detektor dalej ma `current` (oraz `starting`, jeśli był auto-start), więc `.show` nie przyjdzie ponownie. Oferta znika bez śladu, choć poprawka miała ją zostawić.
- **Przy okazji:** powstaje pusta sesja z powiązanym wydarzeniem, która jest otwierana i transkrybowana.
- **Propozycja:** `finish` nie chowa panelu, gdy `pill.mode` to `.offer`. Inna droga: monitor ponawia `present` po `onEnded` dla nieudanego startu.

### 4. Drobna: po nieudanym auto-starcie oferta przestaje się aktualizować

- **Gdzie:** `OfferDetector.step`, warunek `if !starting { action = .show(offer) }`; `MeetingMonitor.accept`.
- **Problem:** gdy auto-start się nie uda (np. preset bez języka), `starting` zostaje `true`, a monitor pokazuje ofertę jako ręczną. Jeśli potem oferta się zmieni (rozmowa w Teams, a za chwilę otwiera się okno wydarzenia, więc `.call` → `.calendarAndCall`), `current` się zmienia, ale nie przychodzi ani `.show`, ani `.startRecording`. Pigułka pokazuje stare „Call in Teams”, a `onStart` trzyma starą ofertę. Start nagrywa więc bez powiązania z wydarzeniem i bez jego tytułu.
- **Propozycja:** metoda detektora typu `startFailed()`, która zeruje `starting` bez wyciszania. Inna droga: `.show` przy zmianie oferty także wtedy, gdy `starting` jest ustawione.

### 5. Drobna: „Unlink” wydarzenia przypiętego przy starcie daje „Untitled meeting”, nie autotytuł

- **Gdzie:** `Sources/MeetNotesNotes/AutoTitle.swift`, `shouldRun` (strażnik `calendarEvent == nil`); `AppModel.unlink` w `EventLinking.swift`.
- **Problem:** start z oferty z wydarzeniem zapisuje `calendarEvent` od razu. Autotytuł po transkrypcji się więc nie generuje, a „Unlink” niczego nie odtwarza. Spec §6 pkt 11 („po Unlink wraca autotytuł”) działa tylko dla powiązań dodanych po fakcie. Test `unlinkingRestoresTheAutoTitle` sprawdza tylko ten przypadek.
- **Kiedy boli:** głównie przy odpięciu źle dobranego wydarzenia, np. przy nakładających się spotkaniach w `.calendarAndCall`.
- **Propozycja (decyzja użytkownika):** albo uruchomić `AutoTitle` przy `unlink`, gdy `autoTitle == nil`, albo zdjąć strażnika. Kolejność w `display` i tak stawia kalendarz nad autotytułem; kosztem jest jedno wywołanie modelu na nagranie.

### 6. Drobna: przełącznik „Launch at login” pokazuje zapisane ustawienie, nie stan systemu

- **Gdzie:** `MeetingSettingsView.swift`, `setLaunchAtLogin` i binding `m.launchAtLoginOrDefault`.
- **Problem:**
  - `SMAppService.mainApp.register()` może się udać bez rzucania, a status zostaje `.requiresApproval`.
  - Użytkownik może też usunąć pozycję w Ustawieniach systemowych.
  - W obu przypadkach przełącznik dalej pokazuje „on”.
- Spike nie zmierzył `SMAppService` (§4), a kryterium 14b nie jest odebrane.
- **Propozycja:** odczyt przełącznika z `SMAppService.mainApp.status == .enabled`, a `.requiresApproval` jako podpis z instrukcją.

### 7. Drobna: tytuł okna pigułki (czyta go VoiceOver) nie wraca do „Recording”

- **Gdzie:** `RecordingController.present`, w którym `panel?.title = title`. `start`, `hideEndPrompt` i `hidePanel` tytułu nie przywracają.
- **Problem:** po Start z oferty okno nagrywania nazywa się „Meeting detected”, a po „Continue” nazywa się „Meeting ended?” aż do końca nagrania.
- **Propozycja:** ustawiać `panel?.title = "Recording"` przy przejściu w `mode = .recording`.

### 8. Drobna: potwierdzenie Quit działa tylko z paska menu

- **Gdzie:** `MenuBarMenu.quit()`. W `Sources/MeetNotesApp` nie ma `applicationShouldTerminate` ani `NSApplicationDelegateAdaptor`.
- **Problem:** poprawka z przeglądu T10/T11 obejmuje tylko „Quit MeetNotes” w pasku menu. Cmd-Q, Quit z Docka i wylogowanie w trakcie nagrania kończą proces bez Stop, więc sesja wraca jako „Recovered”. Problem jest starszy niż 1.6, ale od 1.6 nagranie może ruszyć w tle (auto-start), przy zamkniętym oknie, więc łatwiej o nie trafić.
- **Propozycja:** `applicationShouldTerminate` przez adapter delegata, z tym samym pytaniem i `recording.stop()`.

## Sprawdzone bez uwag (pkt 4 zlecenia)

- **`.id(pill.rev)` (99df124):**
  - `rev` rośnie tylko przy `mode == .offer`.
  - Wyścig, w którym asynchroniczne podbicie trafia już w tryb `.recording` (menu zamknięte, a zaraz potem Start z menu aplikacji), przebudowuje `RecordingPanelView` raz, tuż po starcie. Nic przy tym nie ginie: ten widok, `LevelRow` i `PillIconButton` nie mają stanu lokalnego (`@StateObject`/`@State`), a stan żyje w `PillState` i `RecordingController`.
  - Klucz rozmiaru (`LayoutKey`) nie zależy od `rev`.
- **Obserwator `NSMenu.didEndTrackingNotification`:**
  - Ma `[weak self]` i nie jest zdejmowany, ale panel powstaje raz (`isReleasedWhenClosed = false`), więc w praktyce nie przecieka.
  - Działa w obrębie całej aplikacji (`object: nil`): każde zamknięte menu przy widocznej ofercie przebudowuje widok oferty. To nieszkodliwe.
- **Menu Preset w ofercie (5e07211):** pisze ten sam `activePresetID`, a `startRecording(offer:)` waliduje preset przed startem.
- **Pola zapisywane:**
  - `NoteMeta.calendarEvent`, `GlobalSettings.meetings` i wszystkie pola `MeetingSettings` są opcjonalne.
  - Typy nie mają własnego `init(from:)`, a stare pliki dekodują się poprawnie (testy `linkRoundTripsAndOldMetaWithoutItDecodes` i `oldSettingsJSONWithoutMeetingsDecodes`).
  - Zapisy idą wyłącznie przez `NotesStore(session:)` w katalogu sesji.
- **Prywatność:**
  - Adaptery i monitor nic nie logują.
  - Sondy wypisują flagi, a uruchamia je tylko zmienna środowiskowa.
  - Tytuł wydarzenia nie trafia do promptów: `AutoTitle` nie dostaje tytułu, a `embed` jest używane tylko w sondzie dostawcy.
- **EventKit:** wszystkie wywołania `events`/`calendars` idą z MainActora (monitor, lista wyboru, Settings). Strumień `changes` zdejmuje obserwatora w `onTermination` (anulowanie `changesTask` w `stop()`).

## Kryteria nazwane

| Kryterium | Werdykt | Gdzie |
|---|---|---|
| Wizyta u lekarza (bez linku) nie daje pigułki | pokryte testem | `EventFilterTests.doctorsVisitWithoutALinkIsNotOfferable`, `timedOutOfOfficeWithoutLinkIsNotOfferable`; warunek `meetingURL != nil` w `EventFilter.isOfferable`. Spike nie miał prawdziwej próbki (§2 „brak próbki”). |
| Urodziny (całodniowe) nie dają pigułki | pokryte testem | `allDayBirthdayIsNotOfferable`: druga asercja izoluje sam `isAllDay` przy obecnym linku. |
| OOO w Exchange nie daje pigułki | pokryte testem (fikstura z pomiaru T0) | `exchangeOutOfOfficeShownAsBusyIsNotOfferable` (całodniowe, 72 h, busy, bez linku i uczestników), `allDayOutOfOfficeIsNotOfferable`, `timedOutOfOfficeWithoutLinkIsNotOfferable`, `multiDayBlockIsNotOfferableEvenWithALink`; mapowanie `EventMappingTests.noUserEntryMapsToNone`. Na żywo nie sprawdzano. |
| Poczekalnia Teams nie daje pigułki (albo opisane odstępstwo) | **niepokryte** | Brak pomiaru i brak decyzji (uwaga 1). `lobbyBlip…` testuje tylko 5-sekundowy impuls. |
| Auto-start nigdy na samym kalendarzu | pokryte testem | `autoStartNeverFiresOnCalendarAlone`, `callsDisabledKeepsCalendarOffers`; w kodzie `o.source != .calendar` w `OfferDetector.step`. W monitorze jedyne drogi do `startRecording(offer:)` to `.startRecording` z detektora i przycisk Start. |
| Po ręcznym Stop trwająca rozmowa nie startuje nagrania od nowa | pokryte testem, z luką | `afterManualStopANewCallOffersAgain` (z auto-startem i bez), `retuningKeepsTheMuteAfterManualStop`; monitor podaje `isRecording` w każdym tiku (tylko kod). Luka: Stop w trakcie krótkiego zwolnienia mikrofonu nie ma działającego testu (uwaga 2). |
| Zamknięcie okna nie wyłącza wykrywania | pokryte tylko kodem | `MeetNotesApp.init` → `monitor.start()`; `Timer` w `RunLoop.main` `.common`; `beginActivity`; `MenuBarExtra` trzyma aplikację; nic nie wiąże monitora z oknem. `F16-odbior` ma T11 1–3 i T10 #7 jako ✅, ale z ogólnego „wszystko działa”. |
| Monitor nigdy sam nie zatrzymuje nagrania | pokryte testem (detektor) i kodem (monitor) | `EndAction` nie ma przypadku stop (`noInputNeverYieldsAnythingButAPrompt`, `silenceAloneOnlyPrompts`). Jedyne `recording.stop()` w `MeetingMonitor` siedzi w `onStop` przycisku pigułki. Samoczynny stop to tylko istniejący `SilenceCondition` 600 s (bez zmian). |

przegląd: 8 uwag
