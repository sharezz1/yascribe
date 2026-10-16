# Faza 1.6 „Kalendarz i wykrywanie spotkań" — plan implementacji

> **Dla wykonawców (Claude Code):** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (rekomendowane) albo `superpowers:executing-plans`. Jedno zadanie = jedna sesja/podagent. Kroki używają pól `- [ ]`. **Start od T0 (spike); po T0 jest punkt STOP.**

**Cel:** MeetNotes wykrywa początek spotkania (wydarzenie z linkiem w Kalendarzu Apple albo rozmowa ad hoc w Teams), pokazuje pigułkę z ofertą nagrywania, wykrywa koniec rozmowy i **tylko pyta** (nigdy nie kończy sam), nazywa notatkę nazwą wydarzenia i pozwala powiązać wydarzenie z notatką.

## Poza zakresem (czego ten plan NIE dostarcza)

Przeczytaj przed startem — to nie błędy, tylko jawne granice (decyzje użytkownika i spec §2):

- **Ad hoc poza Teams.** Meet, Zoom, Slack huddle i inne aplikacje nie wywołują pigułki ani auto-startu; dopisanie aplikacji to wpis na liście po pomiarze, nie ta faza. Teams w przeglądarce — tylko jeśli spike (T0) pokaże odróżnialny sygnał; inaczej nie.
- **Pigułka dla spotkań stacjonarnych.** Wydarzenia bez linku do spotkania online (wizyta u lekarza, spotkanie w biurze) nie wywołują pigułki z kalendarza; zaczynasz je ręcznie i możesz przypiąć wydarzenie z listy.
- **Oferta z kalendarza po `start + 10 min`** (okno nastawne); spóźniony start ręczny.
- **Samoczynny koniec.** Aplikacja tylko pyta. Jedyne samoczynne zatrzymanie to istniejący bezpiecznik ciszy 600 s — i **„Continue" go nie przedłuża** (po 10 min ciszy nagranie i tak się kończy).
- **Działanie bez uruchomionej aplikacji.** „Quit" wyłącza wykrywanie; „Launch at login" jest opcjonalne i domyślnie wyłączone.
- **Integracje Google Calendar, Outlook, Slack** — wyłącznie wyszarzone wiersze „Coming soon", zero kodu.
- **„Coming up" / oś nadchodzących spotkań** (W§5 oznacza ✅, ale spec 1.6 go nie obejmuje — zostaje w ROADMAP).
- **Powiadomienia systemowe, nazwiska mówców, automatyczne zgadywanie wydarzenia dla rozmowy ad hoc, uczestnicy w promptach, zapis do kalendarza.**
- **Powiązanie z wydarzeniem przy bardzo wczesnym dołączeniu.** Gdy dołączasz do rozmowy wcześniej niż `offerLead` (60 s) przed startem wydarzenia, pigułka/auto-start zadziała jako „Call in Teams" bez wydarzenia (tytuł z kalendarza nie wejdzie sam); wydarzenie można przypiąć ręcznie (T12).
- **Gwarancje dla poczekalni Teams.** Jeśli T0 pokaże, że poczekalnia trzyma mikrofon dłużej niż `startSeconds`, nie obiecujemy braku pigułki w poczekalni — decyzja po raporcie (STOP po T0).

**Architektura:** nowa biblioteka `MeetNotesMeetings` (tylko Foundation) z czystą logiką — typy, filtr wydarzeń, `OfferDetector`, `EndDetector`, ranking listy wyboru — i własnym testTargetem w `scripts/test.sh`. EventKit i lista procesów Core Audio wchodzą przez cienkie adaptery w `MeetNotesApp`; koordynator `MeetingMonitor` łączy je z detektorami i pigułką. Pola w zapisywanych typach (`NoteMeta`, `GlobalSettings`) wyłącznie opcjonalne.

**Stos:** Swift 6.4 (tryb 6), tylko Command Line Tools, `swift-testing`, SwiftUI + AppKit, EventKit (`requestFullAccessToEvents`), Core Audio (lista obiektów procesów), `SMAppService`. Zero nowych zależności zewnętrznych.

**Spec:** `docs/superpowers/specs/2026-10-16-faza16-kalendarz-design.md` (commit `510750f`). Plan argumentuje ze speca; wykonawca czyta oba.

**Gałąź:** przed T0 `git switch -c faza16` (od `faza15`). ⚠️ Zadania T8–T10 dotykają pigułki (`RecordingController`) i plików, które równolegle zmienia sesja 1.5b (wyciszanie torów, macos.md §11.5): `RecordingController.swift`, `AppModel.swift`, `Snapshots.swift`, `SettingsView.swift` (T7 też). T8 ma bramkę: zaczyna się dopiero po potwierdzeniu przez użytkownika, że 1.5b jest zamknięta albo po rebase; T0–T6 tych plików nie dotykają (poza `Snapshots`/`SettingsView` w T7).

## Wspólne ograniczenia

Obowiązują w każdym zadaniu (wartości dosłownie ze speca i z CLAUDE.md):

- **Swift 6.4, tryb 6, tylko Command Line Tools, `swift-testing`.** SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`; stan lokalny przez `ObservableObject` + `@StateObject`; `@Observable` działa.
- **Testy wyłącznie `scripts/test.sh`**, nigdy goły `swift test`. Kody: 3 = usterka pluginu makr (`rm -rf .build`), 4 = rozjazd liczby testów (wynik NIEWAŻNY — STOP). Każdy `@Test` zaczyna linię. Katalogi tymczasowe: `mn-<UUID>` w `temporaryDirectory`.
- **Nowe pola w zapisywanych typach (`NoteMeta`, `GlobalSettings`, nowe struktury na dysku) tylko opcjonalne** (lekcja E6). Stare `meta.json` / `settings.json` wczytują się bez zmian.
- **Nigdy `git add -A` ani `git add .`** — jawne ścieżki. **Mutacja każdej bramki:** najpierw `git add` jawnych ścieżek zadania (żeby implementacja była w indeksie), potem wprowadź mutację → test ma paść → `git checkout -- <plik>` (przywraca zastage'owaną implementację; bez wcześniejszego `add` `checkout` skasowałby niezacommitowaną pracę albo zawiódł na pliku nowym) → dopiero commit.
- **Klucze API i zgody TCC robi użytkownik.** Nie zmieniamy Ustawień systemowych, TCC ani pęku kluczy. Nie logujemy ani nie zapisujemy w repo tytułów, uczestników i adresów e-mail z kalendarza użytkownika (raporty spike'a: tylko flagi, długości, nazwy pól, bundle ID).
- **Kalendarz tylko do odczytu** — nie tworzymy ani nie zmieniamy wydarzeń. Dane kalendarza nie trafiają do promptów ani do dostawców API.
- **Interfejs po angielsku**, dokumenty w repo po polsku.
- **Wartości (progi, listy) pochodzą z raportu T0**; w nawiasach niżej są szkice ze speca, używane do czasu raportu: `offerLead` 60 s, `offerGrace` 600 s, `maxEventHours` 8, `startSeconds` 12, `releaseSeconds` 20, `silenceSeconds` 180, `snoozeSeconds` 600. Bez zmian: `SilenceCondition` 600 s, `HardLimitCondition` 4 h, `StallCondition` 30 s.
- **Domyślne ustawienia:** *Detect calls* włączone; *Start recording automatically* wyłączone; *Launch at login* wyłączone. **Koniec spotkania zawsze pyta; nie ma trybu samoczynnego zatrzymania** (decyzja 2026-10-16) — jedyne samoczynne zatrzymanie to istniejący bezpiecznik `SilenceCondition` 600 s.
- **Kolejność tytułu:** ręczny > kalendarz > auto > tytuł z notatki > „Untitled meeting".
- **Auto-start tylko** przy rozmowie w znanej aplikacji (Teams) — z wydarzeniem albo bez; **nigdy** na samym kalendarzu.

## Review Focus (czego spec nie mówi, a co użytkownik napotka)

Najpierw najbardziej prawdopodobne; każda linia ma test w zadaniu, które posiada kod:

1. **Teams zwalnia mikrofon na chwilę w trakcie spotkania** (ponowne łączenie, przełączenie urządzenia). Oczekiwane: żadnego pytania o koniec, dopóki zwolnienie nie trwa ≥ `releaseSeconds`. `shortMicReleaseDoesNotEndTheMeeting` (T4).
2. **Aplikacja startuje w trakcie trwającej rozmowy** (uruchomiona ręcznie albo przy logowaniu), **rozmowa trwa godzinami po „Not a meeting"** i **Teams dalej trzyma mikrofon po Twoim Stop**. Oczekiwane: oferta po ≥ `startSeconds` ciągłego użycia; po odrzuceniu **albo po zatrzymaniu nagrania** cisza do końca tej sesji mikrofonu aplikacji (rodziny procesów, nie pojedynczego `pid`) — ani oferta, ani auto-start nie wracają. `callAlreadyInProgressAtLaunchOffersAfterStartSeconds`, `dismissedOfferStaysQuietForTheWholeMicSession`, `dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp`, `manualStopSilencesAutoStartForTheSameCall`, `afterManualStopANewCallOffersAgain` (T3).
3. **Dwa nakładające się spotkania z linkiem** (podwójna rezerwacja). Oczekiwane: jedna pigułka, z wydarzeniem, którego początek jest najbliższy „teraz"; bez migotania między dwoma. `overlappingEventsOfferTheOneStartingClosestToNow` (T3).
4. **Dostęp do kalendarza cofnięty, wydarzenie usunięte lub przesunięte, gdy oferta jest na ekranie.** Oczekiwane: oferta znika (albo zostaje jako ad hoc, gdy Teams trzyma mikrofon), notatka z powiązaniem dalej pokazuje migawkę, nic nie rzuca. `offerDisappearsWhenItsEventIsRemoved` (T3), `linkSnapshotSurvivesWithoutCalendarAccess` (T1).
5. **Ręczny start podczas trwającej rozmowy Teams i ręczny start bez żadnej rozmowy.** Oczekiwane: w pierwszym przypadku śledzimy Teams i pytamy o koniec po jego rozłączeniu; w drugim zwolnienie mikrofonu nie znaczy nic (nie było aplikacji rozmów) i pytanie pojawia się tylko po ciszy. `manualStartAdoptsACallThatStartsLater`, `manualStartWithoutACallNeverPromptsOnMicRelease` (T4).

---

## Przydział modeli i effort

Opus tylko tam, gdzie błąd jest drogi albo decyzja trudna; resztę robi Sonnet, mechanikę Haiku. Effort = poziom rozumowania ustawiany w prompcie zadania i w sesji (narzędzie Agent nie ma parametru effort).

| Zadanie | Model | Effort | Dlaczego |
|---|---|---|---|
| T0 kod sond | Sonnet | **xhigh** | nieznane nazwy API Core Audio/EventKit w SDK 27, nic nie wolno zgadywać |
| T0 interpretacja raportu (STOP) | **Opus** | **xhigh** | decyduje o regule OOO, progach, listach aplikacji |
| T1 typy, `NoteMeta`, tytuły | Sonnet | medium | Codable i kolejność, pełne sygnatury w planie |
| T2 filtr wydarzeń | Sonnet | high | reguły OOO/link, bramka fałszywego startu |
| T3 `OfferDetector` | Sonnet | **xhigh** | maszyna stanów, najgorszy błąd użytkownika |
| T4 `EndDetector` | Sonnet | high | czas, śledzona aplikacja; przegląd Opusa po zadaniu |
| T5 `MeetingSettings` | Haiku | medium | opcjonalne pola, domyślne, mechaniczne |
| T6 adaptery EventKit/Core Audio | Sonnet | high | API systemowe; przegląd Opusa po zadaniu |
| T7 Settings UI | Sonnet | medium | wzór: `RecordingsSection` |
| T8 prefactoring pigułki | Sonnet | high | AppKit, zachowanie bez zmian, porównanie migawek |
| T9 stany Offer / End prompt | Sonnet | medium | UI wg wzoru pigułki |
| T10 `MeetingMonitor` | Sonnet | **xhigh** | integracja czasu, detektorów i pigułki; przegląd Opusa po zadaniu |
| T11 pasek menu, żywotność | Sonnet | medium | przegląd Opusa i STOP po zadaniu |
| T12 lista wyboru wydarzenia | Sonnet | medium | ranking czysty + widok |
| T13 odbiór, dokumenty | Haiku (dokumenty, `test.sh`) / **Opus xhigh** (przegląd całości) | medium / xhigh | przegląd całości przed scaleniem |
| Po każdym zadaniu: `scripts/test.sh`, porównanie liczby testów, mutacje wg przepisu, odhaczanie `- [ ]` | Haiku | low | mechanika |

Kolejność: **T0 → STOP → T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 (bramka 1.5b) → T9 → T10 → T11 → STOP → T12 → T13.**

---

### Task 0: Spike na sprzęcie (sondy, raport) — **STOP po zadaniu**

Spec §5. Bez tego żadna wartość z planu nie jest stała, a reguła OOO i miejsce linku są zgadywane.

**Files:**
- Modify: `Resources/Info.plist` (klucz dostępu do kalendarza), `scripts/check-bundle.sh` (ten klucz w pętli)
- Create: `Sources/MeetNotesApp/Probes.swift` (sondy sterowane zmienną `MEETNOTES_PROBE`, jak `Snapshots` — narzędzie deweloperskie, zostaje w repo)
- Modify: `Sources/MeetNotesApp/MeetNotesApp.swift` (wywołanie `Probes.runIfRequested()` w `init`)
- Create: `docs/superpowers/spikes/2026-10-16-faza16-wykrywanie.md`

**Interfaces:**
- Produces: raport z sekcją **„Wartości dla planu"** (`startSeconds`, `releaseSeconds`, `silenceSeconds`, lista `callApps`, lista `ignoredApps`, pole z linkiem, reguła OOO) — czytają go T1–T3.

- [ ] **Step 1: Klucz Info.plist.** Dodaj `NSCalendarsFullAccessUsageDescription` („MeetNotes reads your calendar to recognise meetings and name your notes. It never changes your events.") i dopisz go do pętli kluczy w `scripts/check-bundle.sh`. Zweryfikuj nazwę klucza w SDK (`grep -r NSCalendarsFullAccess` w nagłówkach / dokumentacji Apple); jeśli inna — użyj właściwej i zapisz w raporcie.
- [ ] **Step 2: Sonda `MEETNOTES_PROBE=calendar`.** `Probes.calendar()`: `requestFullAccessToEvents`, potem dla zdarzeń od −14 do +7 dni wypisuje **bez tytułów i adresów**: `isAllDay`, czas trwania w godzinach, `availability`, `status`, status uczestnictwa użytkownika, liczbę uczestników, `hasURL`, oraz **w których polach (url / location / notes) występuje wzorzec Teams/Meet/Zoom/Webex**, plus `calendarItemExternalIdentifier` obecny (tak/nie) i czy wydarzenie cykliczne.
- [ ] **Step 3: Sonda `MEETNOTES_PROBE=audio`.** `Probes.audio()`: co 1 s czyta listę obiektów procesów Core Audio (`kAudioHardwarePropertyProcessObjectList`; per proces `kAudioProcessPropertyPID`, `…BundleID`, `…IsRunningInput`), wypisuje **zmiany** z czasem (bundle ID, wejście włączone/wyłączone). Pomija własny proces. Jeśli nazwy API w SDK macOS 27 się różnią — ustal właściwe i zapisz.
- [ ] **Step 4: Sonda `MEETNOTES_PROBE=login`.** Rejestruje `SMAppService.mainApp`, wypisuje `status`, wyrejestrowuje; powtórz po przebudowie paczki (podpis „MeetNotes Dev"). Zmienia to pozycje logowania w systemie, więc **uruchamia ją wyłącznie użytkownik, w swoim terminalu** (CLAUDE.md: nie zmieniamy ustawień systemowych); wykonawca tylko pisze sondę.
- [ ] **Step 5: Scenariusze (robi użytkownik, w swoim terminalu; zgodę kalendarza klika użytkownik).** Uruchom paczkę (`scripts/bundle.sh`, potem `MEETNOTES_PROBE=… .build/MeetNotes.app/Contents/MacOS/MeetNotesApp`) i zmierz: rozmowa w nowym Teams (które bundle ID trzymają wejście), wyciszenie i wyłączenie wyciszenia, poczekalnia przed dołączeniem, rozłączenie, Teams w przeglądarce, dyktowanie Wispr Flow i systemowe — **kilka rozmów, nie jedna**. Kalendarz: wydarzenia (a) Teams, (b) OOO całodniowe, (c) OOO czasowe/wielodniowe, (d) focus time, (e) cykliczne, (f) odrzucone, (g) wizyta bez linku, (h) urodziny.
- [ ] **Step 6: Raport.** Wypełnij `docs/superpowers/spikes/2026-10-16-faza16-wykrywanie.md`: surowe pomiary i sekcja „Wartości dla planu" (reguła OOO na polach `EKEvent`; pole linku; progi; listy aplikacji; `SMAppService` działa z podpisem tak/nie). **Bez tytułów i adresów w pliku.**
- [ ] **Step 7: `scripts/test.sh` zielony** (check-bundle widzi nowy klucz). Commit:

```bash
git add Resources/Info.plist scripts/check-bundle.sh Sources/MeetNotesApp/Probes.swift Sources/MeetNotesApp/MeetNotesApp.swift docs/superpowers/spikes/2026-10-16-faza16-wykrywanie.md
git commit -m "Spike fazy 1.6: sondy kalendarza, procesów audio i uruchamiania przy logowaniu"
```

**🛑 STOP (Opus + użytkownik):** użytkownik przegląda raport. Potwierdza regułę OOO na swoim kalendarzu (kryterium akceptacji 3 ze speca) i wartości progów. Jeśli lista procesów audio nie daje per-procesowego sygnału wejścia — **nie improwizuj**: zgłoś, bo cały ad hoc (spec §4.2 B) opiera się na tym. Dopiero potem T1.

---

### Task 1: Biblioteka `MeetNotesMeetings`, typy, powiązanie w `NoteMeta`, kolejność tytułów

**Files:**
- Modify: `Package.swift` (target `MeetNotesMeetings` bez zależności; `MeetNotesNotes` i `MeetNotesApp` zależą od niego; testTarget `MeetNotesMeetingsTests`)
- Create: `Sources/MeetNotesMeetings/CalendarLink.swift`, `CalendarEventInfo.swift`, `MeetingTuning.swift`
- Modify: `Sources/MeetNotesNotes/NoteTitle.swift` (`NoteMeta.calendarEvent`, `NoteTitle.display`), `Sources/MeetNotesNotes/AutoTitle.swift` (strażnik)
- Test: `Tests/MeetNotesMeetingsTests/CalendarLinkTests.swift`, `Tests/MeetNotesNotesTests/CalendarTitleTests.swift`

**Interfaces:**
- Produces (`MeetNotesMeetings`, wszystko `Codable, Equatable, Sendable` poza zaznaczonym):
  - `struct CalendarLink { title: String; start: Date; end: Date; calendarName: String?; attendees: [Attendee]?; eventIdentifier: String?; externalIdentifier: String?; occurrenceStart: Date?; struct Attendee { name: String?; email: String? } }`
  - `struct CalendarEventInfo: Identifiable { id: String; title: String; start, end: Date; isAllDay: Bool; availability: Availability; myStatus: ParticipantStatus; isCanceled: Bool; url: URL?; location: String?; notes: String?; attendees: [CalendarLink.Attendee]; calendarName: String?; eventIdentifier: String?; externalIdentifier: String?; occurrenceStart: Date?; func link() -> CalendarLink }` (bez `Codable`); `enum Availability { busy, free, tentative, unavailable, notSupported }`; `enum ParticipantStatus { accepted, declined, tentative, pending, none }`. `id` = `(externalIdentifier ?? eventIdentifier ?? title) + "|" + (occurrenceStart ?? start) ISO-8601`.
  - `struct MeetingTuning: Equatable, Sendable` z polami i domyślnymi wartościami ze „Wspólnych ograniczeń"/raportu T0: `offerLead`, `offerGrace`, `maxEventHours`, `startSeconds`, `releaseSeconds`, `silenceSeconds`, `snoozeSeconds` (`Double`), `callApps`, `ignoredApps`, `linkPatterns` (`[String]`).
- Produces (`MeetNotesNotes`): `NoteMeta.calendarEvent: CalendarLink?` (opcjonalne, E6); `NoteTitle.display(meta:noteTitle:)` z nową kolejnością.

- [ ] **Step 1: Testy (padają).**

```swift
@Test func linkRoundTripsAndOldMetaWithoutItDecodes() throws {
    let old = #"{"manualTitle":"A"}"#.data(using: .utf8)!
    let m = try JSONDecoder().decode(NoteMeta.self, from: old)
    #expect(m.calendarEvent == nil && m.manualTitle == "A")
    var n = NoteMeta(); n.calendarEvent = CalendarLink.fixture()
    let again = try JSONDecoder().decode(NoteMeta.self, from: JSONEncoder().encode(n))
    #expect(again == n)
}
@Test func titleOrderIsManualThenCalendarThenAutoThenNote() {
    var m = NoteMeta(manualTitle: nil, autoTitle: "Auto"); m.calendarEvent = .fixture(title: "Weekly")
    #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Weekly")
    m.manualTitle = "Mine"; #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Mine")
    m.manualTitle = nil; m.calendarEvent = nil; #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Auto")
}
@Test func autoTitleDoesNothingWhenAnEventIsLinked()      // z `CalendarLink` w meta: klient nie jest wołany, `autoTitle` zostaje nil
@Test func unlinkingRestoresTheAutoTitle()               // `calendarEvent = nil` → display = autoTitle
@Test func linkSnapshotSurvivesWithoutCalendarAccess()   // CalendarLink czyta się i wyświetla z samego meta.json, bez żadnego dostępu do EventKit
@Test func eventIDDiffersPerOccurrenceOfARecurringEvent() // ten sam externalIdentifier, inne occurrenceStart → inne `id`
```

- [ ] **Step 2: Uruchom** `scripts/test.sh --filter MeetingsTests` i `--filter CalendarTitleTests` — oczekiwane: FAIL (brak typów).
- [ ] **Step 3: Zaimplementuj** typy wg bloku Interfaces; `NoteTitle.display` bierze kolejność `[manualTitle, calendarEvent?.title, autoTitle, noteTitle]`; `AutoTitle` przy `m.calendarEvent != nil` nie zapisuje (zmiana w istniejącym warunku `manualTitle == nil && autoTitle == nil`).
- [ ] **Step 4: `scripts/test.sh`** (pełny) — zielony, liczba się zgadza.
- [ ] **Step 5: Zastage'uj** (jawne ścieżki): `git add Package.swift Sources/MeetNotesMeetings Sources/MeetNotesNotes/NoteTitle.swift Sources/MeetNotesNotes/AutoTitle.swift Tests/MeetNotesMeetingsTests Tests/MeetNotesNotesTests/CalendarTitleTests.swift`.
- [ ] **Step 6: Mutacja:** w `display` zamień kalendarz i auto miejscami → `titleOrderIsManualThenCalendarThenAutoThenNote` pada → `git checkout -- Sources/MeetNotesNotes/NoteTitle.swift` (wraca zastage'owana implementacja).
- [ ] **Step 7: Commit** (`git commit` z zastage'owanych plików; w razie potrzeby dołóż `git add` tych samych ścieżek).

---

### Task 2: Filtr wydarzeń i wykrywanie linku

Spec §4.3.

**Files:**
- Create: `Sources/MeetNotesMeetings/EventFilter.swift`
- Test: `Tests/MeetNotesMeetingsTests/EventFilterTests.swift`

**Interfaces:**
- Consumes: `CalendarEventInfo`, `MeetingTuning` (T1).
- Produces: `enum EventFilter { static func meetingURL(in: CalendarEventInfo, patterns: [String]) -> URL?; static func isOfferable(_: CalendarEventInfo, tuning: MeetingTuning) -> Bool; static func isPickable(_: CalendarEventInfo) -> Bool }`.

Reguły `isOfferable` (wszystkie naraz): `meetingURL != nil` (szuka w `url`, `location`, `notes` — **kolejność pól i wzorce z raportu T0**); `!isAllDay`; czas trwania ≤ `maxEventHours` i ten sam dzień kalendarzowy rozpoczęcia nie przekroczony (blok wielodniowy odpada); **`availability` nie jest sygnałem OOO** (pomiar T0: OOO z Exchange ma dostępność *busy*; spec §4.3 pkt 4) — nie wchodzi do filtra; `myStatus ∈ {accepted, tentative, none}` (*none* = wydarzenie własne, brak wpisu użytkownika w uczestnikach; **unknown/pending/declined/delegated odpadają** — spec §4.3 pkt 5); `!isCanceled`. Wzorce linków: ogólnie `teams.microsoft.com` (nie `/l/meetup-join` — pomiar T0), `teams.live.com`, `meet.google.com`, `zoom.us/j`; **bez** `webex.com`. `isPickable`: `!isAllDay`, nie OOO (ta sama detekcja), niezależnie od linku i statusu.

- [ ] **Step 1: Testy (padają)** — fixtura `CalendarEventInfo.fixture(...)` z parametrami; wartości pól dla OOO i Teams z raportu T0:

```swift
@Test func teamsMeetingWithLinkInNotesIsOfferable()
@Test func doctorsVisitWithoutALinkIsNotOfferable()          // wizyta u lekarza: brak linku → false
@Test func allDayBirthdayIsNotOfferable()
@Test func allDayOutOfOfficeIsNotOfferable()
@Test func exchangeOutOfOfficeShownAsBusyIsNotOfferable()        // fixtura z pomiaru T0: całodniowe, 72 h, availability .busy, bez linku i uczestników → false (dostępność nie pomaga, odcinają całodniowe i brak linku)
@Test func timedOutOfOfficeWithoutLinkIsNotOfferable()
@Test func multiDayBlockIsNotOfferableEvenWithALink()        // link w OOO wielodniowym nadal odpada
@Test func declinedAndCanceledAreNotOfferable()
@Test func unansweredInvitationIsNotOfferable()                  // myStatus .unknown i .pending + link Teams → false (codzienne spotkanie na ~50 osób bez odpowiedzi)
@Test func acceptedAndTentativeAndOwnEventsAreOfferable()        // .accepted, .tentative, .none (+ link) → true
@Test func teamsMeetLinkInNotesIsRecognised()                    // `https://teams.microsoft.com/meet/…` w `notes` → rozpoznany
@Test func webexAloneIsNotAMeetingLink()                         // `webex.com` bez Teams/Zoom/Meet → false
@Test func meetingWithLinkButNoOtherAttendeesIsOfferable()   // warunek „ma uczestników" odpadł
@Test func linkPatternsMatchTeamsMeetZoomWebex()
@Test func pickableHidesAllDayAndOOOButKeepsInPersonEvents() // wizyta stacjonarna bez linku jest na liście wyboru
```

- [ ] **Step 2–3:** uruchom (FAIL) → zaimplementuj → uruchom (PASS). Wzorce linków jako `NSRegularExpression`-free: `String.contains` po wzorcach z `MeetingTuning.linkPatterns`.
- [ ] **Step 4: Mutacje** (najpierw `git add Sources/MeetNotesMeetings/EventFilter.swift Tests/MeetNotesMeetingsTests/EventFilterTests.swift`): (a) usuń warunek `!isAllDay` → `allDayBirthday…` pada; (b) usuń warunek linku → `doctorsVisit…` pada; (c) usuń warunek odpowiedzi użytkownika → `unansweredInvitation…` pada; (d) usuń warunek `!isAllDay` **i** warunek linku → `exchangeOutOfOfficeShownAsBusy…` pada (OOO odcinają te dwa warunki, nie dostępność). Każdą cofnij `git checkout -- <plik>`.
- [ ] **Step 5: `scripts/test.sh`**, commit (`EventFilter.swift`, `EventFilterTests.swift`).

---

### Task 3: `OfferDetector` — oferta startu

Spec §4.2, §4.5.

**Files:**
- Create: `Sources/MeetNotesMeetings/OfferDetector.swift`, `AudioProcessSample.swift`
- Test: `Tests/MeetNotesMeetingsTests/OfferDetectorTests.swift`

**Interfaces:**
- Consumes: `CalendarEventInfo`, `EventFilter`, `MeetingTuning`.
- Produces:
  - `struct AudioProcessSample: Equatable, Sendable { var pid: Int32; var bundleID: String; var isRunningInput: Bool }` (adapter w T6 pomija proces MeetNotes).
  - `struct Offer: Equatable, Sendable, Identifiable { var id: String; var title: String; var source: Source; var event: CalendarEventInfo?; var app: String?; enum Source { calendar, call, calendarAndCall } }`. `title` = tytuł wydarzenia albo `"Call in Teams"` (nazwa aplikacji z mapy `bundleID → nazwa`).
  - `enum OfferAction: Equatable { case show(Offer), hide, startRecording(Offer) }`
  - `struct OfferDetector { init(tuning: MeetingTuning); mutating func step(now: Date, events: [CalendarEventInfo], processes: [AudioProcessSample], recording: Bool, callsEnabled: Bool, autoStart: Bool) -> OfferAction?; mutating func dismiss() }` — zwraca akcję tylko przy **zmianie** stanu (brak powtarzania `.show` co tik).

Reguły: oferta A tylko dla `isOfferable` w oknie `[start − offerLead, start + offerGrace]`; oferta B tylko gdy bundle ID ∈ `callApps`, ∉ `ignoredApps`, wejście włączone **nieprzerwanie** ≥ `startSeconds`; A+B razem → jedna oferta `.calendarAndCall` z wydarzeniem; przy kilku wydarzeniach wygrywa to o początku najbliższym `now`; `recording == true` → brak ofert i `.hide`; `callsEnabled == false` wyłącza B (A zostaje); `autoStart == true` → `.startRecording` **tylko** dla `.call` i `.calendarAndCall`, nigdy dla `.calendar`; `dismiss()` wycisza ofertę dla bieżącej sesji mikrofonu **rodziny aplikacji** i dla tego `id` wydarzenia. „Rodzina" = wpis z `callApps` dopasowany **po prefiksie** bundle ID (`com.microsoft.teams2` obejmuje jej procesy pomocnicze); `pid` nie jest kluczem. Sesja rodziny kończy się (i wyciszenie z nią), gdy żaden jej proces nie trzyma wejścia przez ≥ `releaseSeconds`. **Zatrzymanie nagrania** (przejście `recording: true → false`, ręczne albo przez bezpiecznik) wycisza tak samo wszystkie trwające rodziny i bieżące wydarzenie — ani oferta, ani `.startRecording` nie wracają do końca tej sesji.

- [ ] **Step 1: Testy (padają):**

```swift
@Test func calendarEventWithLinkOffersInsideTheWindowOnly()      // −61 s: nil; −59 s: show; +601 s po starcie: hide
@Test func teamsHoldingTheMicForStartSecondsOffersACall() {
    var d = OfferDetector(tuning: .test)             // startSeconds = 12
    #expect(d.step(now: t0, events: [], processes: [.teams], recording: false, callsEnabled: true, autoStart: false) == nil)
    #expect(d.step(now: t0 + 11, events: [], processes: [.teams], ...) == nil)
    guard case .show(let o)? = d.step(now: t0 + 12, events: [], processes: [.teams], ...) else { Issue.record("no offer"); return }
    #expect(o.source == .call && o.title == "Call in Teams")
}
@Test func lobbyBlipShorterThanStartSecondsNeverOffers()         // wejście 5 s, wyłączone, znów 5 s → nil (przerwa zeruje licznik)
@Test func ignoredAppsNeverOffer()                               // Wispr Flow / dyktowanie
@Test func unknownAppsNeverOffer()
@Test func calendarPlusTeamsMakesOneOfferWithTheEvent()          // source == .calendarAndCall, event != nil
@Test func overlappingEventsOfferTheOneStartingClosestToNow()
@Test func autoStartNeverFiresOnCalendarAlone()                  // autoStart: true + samo wydarzenie → tylko .show
@Test func autoStartFiresForACall()                              // autoStart: true + Teams ≥ startSeconds → .startRecording(.call)
@Test func autoStartFiresForCalendarPlusCall()
@Test func dismissedOfferStaysQuietForTheWholeMicSession()       // po dismiss(): 2 h ciągłego użycia → nigdy .show
@Test func dismissedOfferReturnsForANewMicSession()              // Teams zwalnia na ≥ releaseSeconds, potem znów ≥ startSeconds → .show
@Test func dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp() // po dismiss() wejście przechodzi z `com.microsoft.teams2` na `com.microsoft.teams2.helper` (inny pid) → nigdy .show
@Test func dismissedEventStaysQuietForTheSameEvent()             // po dismiss() oferty z wydarzenia: to samo `id` w oknie → nigdy .show; inne wydarzenie → .show
@Test func manualStopSilencesAutoStartForTheSameCall()           // autoStart: true; nagranie trwało (recording: true), potem recording: false, Teams nadal trzyma wejście → żadnego .startRecording ani .show przez 2 h
@Test func afterManualStopANewCallOffersAgain()                  // po Stop Teams zwalnia ≥ releaseSeconds, znów ≥ startSeconds → .startRecording (autoStart) / .show
@Test func callAlreadyInProgressAtLaunchOffersAfterStartSeconds()
@Test func offerDisappearsWhenItsEventIsRemoved()                // ofertę z wydarzenia A + zdarzenie znika z `events` → .hide
@Test func recordingSuppressesOffers()
@Test func callsDisabledKeepsCalendarOffers()
```

- [ ] **Step 2–3:** FAIL → implementacja (stan: `micSince: [String: Date]` kluczowany rodziną aplikacji, `dismissedFamilies: Set<String>`, `dismissedEventIDs`, `wasRecording`, `currentOffer`) → PASS.
- [ ] **Step 4: Mutacje** (najpierw `git add` plików zadania): (a) `autoStart` także dla `.calendar` → `autoStartNeverFiresOnCalendarAlone` pada; (b) `startSeconds` ignorowane → `lobbyBlip…` pada; (c) `dismiss()` czyści tylko do następnego tiku → `dismissedOffer…WholeMicSession` pada; (d) klucz rodziny zastąpiony `pid` → `…AcrossHelperProcesses…` pada; (e) pomiń wyciszenie przy przejściu `recording true → false` → `manualStopSilencesAutoStart…` pada. Cofnij każdą `git checkout -- <plik>`.
- [ ] **Step 5: `scripts/test.sh`**, commit.

---

### Task 4: `EndDetector` — koniec spotkania (tylko pytanie)

Spec §4.6. Po zadaniu **przegląd Opusa**. Detektor **nigdy nie zatrzymuje nagrania** — wynikiem jest wyłącznie pytanie.

**Files:**
- Create: `Sources/MeetNotesMeetings/EndDetector.swift`
- Test: `Tests/MeetNotesMeetingsTests/EndDetectorTests.swift`

**Interfaces:**
- Consumes: `AudioProcessSample`, `MeetingTuning`.
- Produces:
  - `enum EndSignal: Equatable, Sendable { case callReleased, silence }`
  - `enum EndAction: Equatable, Sendable { case prompt(EndSignal), dismissPrompt }` (**brak** przypadku zatrzymania)
  - `struct EndDetector { init(tuning: MeetingTuning); mutating func step(now: Date, recording: Bool, processes: [AudioProcessSample], silentSeconds: Double) -> EndAction?; mutating func continueMeeting(now: Date); mutating func reset() }`

Reguły: „śledzona" aplikacja = `callApps`, która trzymała wejście w trakcie nagrania (także jeśli zaczęła po starcie); `callReleased` po ≥ `releaseSeconds` bez wejścia **wszystkich** śledzonych procesów; bez śledzonej aplikacji sygnału `callReleased` nie ma; `silence` po `silentSeconds ≥ silenceSeconds`; oba sygnały dają `.prompt(sygnał)`; `continueMeeting` wycisza na `snoozeSeconds`; powrót wejścia lub dźwięku po `.prompt` → `.dismissPrompt`.

- [ ] **Step 1: Testy (padają):**

```swift
@Test func releaseLongerThanReleaseSecondsPrompts() {
    var d = EndDetector(tuning: .test)               // releaseSeconds = 20
    _ = d.step(now: t0, recording: true, processes: [.teams], silentSeconds: 0)
    #expect(d.step(now: t0 + 19, recording: true, processes: [], silentSeconds: 0) == nil)
    #expect(d.step(now: t0 + 41, recording: true, processes: [], silentSeconds: 0) == .prompt(.callReleased))
}
@Test func shortMicReleaseDoesNotEndTheMeeting()                  // 10 s bez wejścia, potem znów → nil, nigdy .prompt
// wyciszenie w Teams: jeśli raport T0 pokaże, że zwalnia wejście na dłużej niż `releaseSeconds`, skutkiem jest jedno zbędne pytanie, które znika samo po powrocie wejścia (`promptIsDismissedWhenTheCallComesBack`) — nagranie nigdy nie jest zatrzymywane; opisz to w raporcie T11, osobnego testu nie ma
@Test func silenceAloneOnlyPrompts()                              // silentSeconds = 181 → .prompt(.silence)
@Test func noInputNeverYieldsAnythingButAPrompt()                 // po 4 h bez wejścia i z ciszą: akcje ∈ {.prompt, .dismissPrompt, nil} (typ nie ma przypadku stop — test pilnuje, że nie zostanie dodany)
@Test func continueSnoozesThePromptForSnoozeSeconds()             // po continueMeeting: 599 s → nil, 601 s → znów .prompt
@Test func manualStartAdoptsACallThatStartsLater()                // recording od t0 bez rozmowy, Teams w t0+60, zwalnia → .prompt(.callReleased)
@Test func manualStartWithoutACallNeverPromptsOnMicRelease()      // brak aplikacji rozmów → release nic nie znaczy; tylko cisza
@Test func promptIsDismissedWhenTheCallComesBack()
@Test func notRecordingProducesNoActions()
```

- [ ] **Step 2–3:** FAIL → implementacja → PASS.
- [ ] **Step 4: Mutacje** (najpierw `git add` plików zadania): (a) pomiń `releaseSeconds` (prompt przy pierwszym tiku bez wejścia) → `shortMicRelease…` pada; (b) śledź też aplikacje spoza `callApps` → `manualStartWithoutACall…` pada; (c) pomiń `snoozeSeconds` → `continueSnoozes…` pada. Cofnij każdą.
- [ ] **Step 5: `scripts/test.sh`**, commit (`EndDetector.swift`, `EndDetectorTests.swift`). `EndReason` i rdzeń nagrywania **bez zmian**.

---

### Task 5: `MeetingSettings` w `GlobalSettings`

Spec §4.1.

**Files:**
- Modify: `Sources/MeetNotesProviders/Preset.swift` (struktura `MeetingSettings` i pole `GlobalSettings.meetings: MeetingSettings?`)
- Create: `Sources/MeetNotesApp/MeetingTuning+Settings.swift` (`MeetingTuning.init(settings:)` — w app, bo `Providers` nie zna `Meetings`)
- Test: `Tests/MeetNotesProvidersTests/MeetingSettingsTests.swift`

**Interfaces:**
- Produces: `struct MeetingSettings: Codable, Equatable, Sendable` — wszystkie pola `Bool?`/`String?`/`Double?`: `appleCalendarEnabled`, `calendarIDs: [String]?` (`nil` = wszystkie), `detectCalls`, `autoStart`, `launchAtLogin`, nadpisania progów (`startSeconds`, `releaseSeconds`, `silenceSeconds`), `ignoredApps: [String]?`; akcesory z domyślnymi: `var detectCallsOrDefault: Bool` (true), `autoStartOrDefault` (false), `launchAtLoginOrDefault` (false), `appleCalendarOrDefault` (false). `GlobalSettings.meetings` opcjonalne.

- [ ] **Step 1: Testy (padają):** `oldSettingsJSONWithoutMeetingsDecodes`; `defaultsMatchTheSpec` (calls true, autoStart false, login false, calendar false); `overridesFlowIntoTuning` (w `MeetNotesApp` nie ma testTargetu — test `MeetingTuning`-mapowania wykonaj na czystej funkcji w `MeetNotesProviders`: `MeetingSettings.tuningValues` zwraca krotkę liczb, a `init(settings:)` tylko ją przepisuje).
- [ ] **Step 2–4:** FAIL → implementacja → `scripts/test.sh` zielony. Mutacja: po `git add` plików zadania: `autoStartOrDefault` zwraca `true` → `defaultsMatchTheSpec` pada → `git checkout -- <plik>`.
- [ ] **Step 5: Commit.**

---

### Task 6: Adaptery systemowe — EventKit i procesy audio

**Files:**
- Create: `Sources/MeetNotesApp/EventKitCalendar.swift`, `Sources/MeetNotesApp/AudioProcessMonitor.swift`
- Create: `Sources/MeetNotesMeetings/Sources.swift` (protokoły `CalendarSource`, `AudioProcessSource`; nazwa pliku bez kolizji z modułem `MeetNotesProviders`)
- Create: `Sources/MeetNotesMeetings/EventMapping.swift` (czysta funkcja mapowania z `EventFields`)
- Test: `Tests/MeetNotesMeetingsTests/EventMappingTests.swift` (istniejący testTarget z T1; tylko czysta część mapowania)

**Interfaces:**
- Consumes: `CalendarEventInfo`, `CalendarLink.Attendee` (T1), `AudioProcessSample` (T3).
- Produces:
  - `protocol CalendarSource: Sendable { func authorization() -> CalendarAuthorization; func requestAccess() async -> Bool; func calendars() -> [CalendarInfo]; func events(from: Date, to: Date, calendarIDs: [String]?) -> [CalendarEventInfo]; var changes: AsyncStream<Void> { get } }`; `enum CalendarAuthorization { notDetermined, granted, denied }`; `struct CalendarInfo: Identifiable, Equatable, Sendable { id: String; title: String }`.
  - `protocol AudioProcessSource: Sendable { func snapshot() -> [AudioProcessSample] }`.
  - `EventKitCalendar: CalendarSource` (`EKEventStore`, `requestFullAccessToEvents`, `.EKEventStoreChanged`); `AudioProcessMonitor: AudioProcessSource` (Core Audio, nazwy API ustalone w T0, **wyklucza własny PID**).
  - `struct EventFields: Sendable` (surowe pola wydarzenia, w tym `isOrganizer` = organizator to bieżący użytkownik, jako proste wartości: czas, flagi, liczby i teksty zamiast typów EventKit) i `enum EventMapping { static func map(_ f: EventFields) -> CalendarEventInfo }` w `MeetNotesMeetings` — dzięki temu mapowanie testuje się bez EventKit; pola `availability`/`status`/uczestnik mapowane wg raportu T0. Adapter w `MeetNotesApp` tylko wypełnia `EventFields` z `EKEvent`.

- [ ] **Step 1: Testy mapowania (padają):** `unavailableAvailabilityMapsToUnavailable`, `declinedParticipantMapsToDeclined`, `unknownParticipantStatusMapsToPendingNotNone` (EventKit *unknown*/*delegated* → `.pending`; `.none` oznacza wyłącznie wydarzenie własne bez wpisu użytkownika wśród uczestników — pomyłka tu wpuściłaby niezaakceptowane spotkania do `isOfferable`), `recurringEventKeepsExternalIDAndOccurrenceStart`, `missingFieldsDoNotCrash` (wszystkie pola `nil`).
- [ ] **Step 2–4:** FAIL → implementacja → PASS. Adaptery EventKit/Core Audio nie mają testu jednostkowego (system); weryfikuje je sonda z T0 i odbiór w T13. **Brak dostępu do kalendarza → `events` zwraca `[]`, nic nie rzuca** (Review Focus 4).
- [ ] **Step 5: Mutacja** (najpierw `git add` plików zadania): w `EventMapping` odwróć mapowanie `declined` → `accepted` (albo `unavailable` → `busy`) → `declinedParticipantMapsToDeclined` (`unavailableAvailabilityMapsToUnavailable`) pada → `git checkout -- <plik>`. Mapowanie jest bramką filtra OOO/odrzuconych (CLAUDE.md: mutacja każdej bramki).
- [ ] **Step 6: Przegląd Opusa** (po T6): czy adapter nie loguje tytułów, czy własny proces jest wykluczony, czy `changes` nie przecieka.
- [ ] **Step 7: Commit.**

---

### Task 7: Settings — Integrations i Meeting detection

Spec §4.1. Interfejs po angielsku; wzór wyglądu: istniejące sekcje (`SectionHeader`, `RecordingsSection`).

**Files:**
- Create: `Sources/MeetNotesApp/MeetingSettingsView.swift`
- Modify: `Sources/MeetNotesApp/SettingsView.swift` (sekcje po Recordings), `Sources/MeetNotesApp/AppModel.swift` (`settings.meetings`, zapis, akcja `connectAppleCalendar()`)
- Modify: `Sources/MeetNotesApp/Snapshots.swift` (migawka sekcji)

**Interfaces:**
- Consumes: `MeetingSettings` (T5), `CalendarSource` (T6).
- Produces: `AppModel.connectAppleCalendar() async` (prosi o dostęp dopiero po włączeniu przełącznika; odmowa → komunikat z instrukcją „System Settings → Privacy & Security → Calendars", **bez zmieniania TCC**), `AppModel.setLaunchAtLogin(_:)` (`SMAppService.mainApp.register()/unregister()`, błąd → `lastError`).

- [ ] **Step 1: Sekcja Integrations:** Apple Calendar (przełącznik Connect + lista kalendarzy z polami wyboru, domyślnie wszystkie) oraz wyszarzone wiersze Google Calendar, Outlook, Slack z „Coming soon" (`.disabled(true)`, bez żadnego kodu integracji).
- [ ] **Step 2: Sekcja Meeting detection:** *Detect calls*, *Start recording automatically* (pod nim jedna linijka: „Starts only for calls in Teams, never for a calendar event alone."), *Launch at login* (z linijką „Without it, detection starts when you open MeetNotes."), zwijane *Advanced* (progi i lista ignorowanych aplikacji z wartościami domyślnymi widocznymi jako placeholdery).
- [ ] **Step 3: Zapis** jak w `RecordingsSection` (nie `SettingsDraft` — ten obsługuje tylko „Archive search"): przełączniki zmieniają `model.settings.meetings` i zapisują od razu istniejącym mechanizmem zapisu ustawień; Connect zapisuje stan po odpowiedzi systemu. Bez Save/Cancel dla tych sekcji.
- [ ] **Step 4: Weryfikacja ręczna:** `scripts/run.sh`, otwórz Settings, sprawdź sekcje w jasnym i ciemnym trybie, wiersze „Coming soon" nie reagują; zrób migawki narzędziem `Snapshots`.
- [ ] **Step 5: `scripts/test.sh`**, commit.

---

### Task 8: Prefactoring pigułki — okno niezależne od nagrywania

Spec §4.4. Czysty refaktor: zachowanie podczas nagrywania **bez zmian**. Dziś pigułka istnieje tylko podczas nagrania: `showPanel` ma guard `isRecording`, `PillHostingView` jest typowany na jeden widok, a `finish()` chowa okno — stany Offer i End prompt (T9) wymagają okna, które żyje bez nagrywania.

**🛑 Bramka 1.5b:** zadanie zaczyna się dopiero, gdy użytkownik potwierdzi, że 1.5b (wyciszanie torów) jest zamknięta, a `faza16` jest od niej (albo po rebase). Pliki narażone na konflikt: `RecordingController.swift`, `AppModel.swift`, `Snapshots.swift`, `SettingsView.swift`. Bez potwierdzenia — STOP.

**Files:**
- Modify: `Sources/MeetNotesApp/RecordingController.swift`, `Sources/MeetNotesApp/Snapshots.swift`

**Interfaces:**
- Consumes: `Offer` (T3), `EndSignal` (T4).
- Produces: `enum PillMode: Equatable { case recording; case offer(Offer); case endPrompt(EndSignal) }`; `PillState.mode: PillMode` (domyślnie `.recording`); `RecordingController.showPanel(model:)` bez guardu `isRecording` (guard przeniesiony do wywołań z menu, które już mają `.disabled(!isRecording)`); `hidePanel()` wołane, gdy nagranie się kończy **albo** oferta/pytanie zostaje zdjęte; treść okna wybierana przez `mode` (gałąź `.recording` = dotychczasowy `RecordingPanelView`, bez zmian).

- [ ] **Step 1: Potwierdzenie bramki 1.5b** (użytkownik) i `git status` czysty.
- [ ] **Step 2: Zrzuty referencyjne.** Zrób migawki pigułki narzędziem `Snapshots` (zwinięta i rozwinięta) **przed** refaktorem i zachowaj je w scratchpadzie.
- [ ] **Step 3: Refaktor** wg bloku Interfaces; gałęzie `.offer` i `.endPrompt` na razie renderują pusty widok zastępczy (treść w T9).
- [ ] **Step 4: Weryfikacja zachowania.** `scripts/test.sh` zielony, liczba testów bez zmian; migawki pigułki po refaktorze identyczne z referencyjnymi; `scripts/run.sh`: Start nagrania → pigułka wygląda i działa jak dotąd, Stop → okno znika.
- [ ] **Step 5: Commit** (`RecordingController.swift`, `Snapshots.swift` — jawne ścieżki).

---

### Task 9: Pigułka — stany Offer i End prompt, start z oferty, zapis powiązania

Spec §4.4.

**Files:**
- Modify: `Sources/MeetNotesApp/RecordingController.swift` (treść gałęzi `.offer` i `.endPrompt`, metody poniżej), `Sources/MeetNotesApp/AppModel.swift` (`startRecording(offer:)`)
- Modify: `Sources/MeetNotesApp/Snapshots.swift` (migawki Offer i End prompt)

**Interfaces:**
- Consumes: `PillMode` (T8), `Offer` (T3), `EndSignal` (T4), `CalendarLink` (T1), `NotesStore.updateMeta`.
- Produces: `RecordingController.showOffer(_ offer: Offer, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void)`, `hideOffer()`, `showEndPrompt(_ signal: EndSignal, onStop: @escaping () -> Void, onContinue: @escaping () -> Void)`, `hideEndPrompt()`; `AppModel.startRecording(offer: Offer? = nil)`.

- [ ] **Step 1: Offer:** nazwa wydarzenia (lub „Call in Teams"), przyciski **Start** i **Not a meeting**. Okno **nie przejmuje fokusu** (decyzja (c) z odbioru 1.5a: stanie się oknem klucza nie fokusuje Stop). Tekst i ikona niosą stan, nie sam kolor; Reduce Motion bez pulsowania.
- [ ] **Step 2: End prompt:** „Meeting ended?" z **Stop** i **Continue**.
- [ ] **Step 3: `startRecording(offer:)`:** jak dziś + gdy `offer.event != nil`, po starcie `NotesStore(session:).updateMeta { $0.calendarEvent = event.link() }`; błąd zapisu → `lastError` (nagranie trwa). Tytuł wydarzenia wyświetlany w pigułce obok presetu.
- [ ] **Step 4: Weryfikacja ręczna** na migawkach (`Snapshots`) i `scripts/run.sh` z wymuszoną ofertą (sztuczne wywołanie z `Probes`, nie z detektora — ten przychodzi w T10).
- [ ] **Step 5: `scripts/test.sh`**, commit.

---

### Task 10: `MeetingMonitor` — łączy detektory, adaptery i pigułkę

Spec §4.2, §4.5, §4.6. Pierwsze realne zachowanie od końca do końca. Po zadaniu **przegląd Opusa**.

**Files:**
- Create: `Sources/MeetNotesApp/MeetingMonitor.swift`
- Modify: `Sources/MeetNotesApp/AppModel.swift` (`let monitor`, spięcie z `recording`)

**Interfaces:**
- Consumes: `OfferDetector`, `EndDetector`, `CalendarSource`, `AudioProcessSource`, `MeetingSettings`, `RecordingController`, `AppModel.startRecording(offer:)`.
- Produces: `@MainActor final class MeetingMonitor` — `start()`, `stop()`, `state: MonitorState` (`.off / .watching / .calendarDenied`); tik co 1 s dla procesów audio, odświeżenie wydarzeń co 30 s i na `EKEventStoreChanged`; `silentSeconds` = czas od `lastLoudAt` rekordera (**ten sam próg −50 dBFS co `SilenceCondition`**, `SessionRecorder.swift`; wystaw wartość z rekordera przez `RecordingController`, nie licz drugiej definicji ciszy z `levels` — przy szumie −60…−50 dBFS bezpiecznik 600 s ucinałby nagranie bez pytania); `.startRecording` → `AppModel.startRecording(offer:)`; `EndAction.prompt` → `recording.showEndPrompt(...)` (Stop = istniejące `recording.stop()`, Continue = `endDetector.continueMeeting`). **Monitor nigdy sam nie zatrzymuje nagrania.**

- [x] **Step 1: Koordynator.** Wyłączone *Detect calls* i brak Apple Calendar → monitor `.off`, zero odpytywania. Bez dostępu do kalendarza ad hoc działa dalej (`.calendarDenied` tylko w menu i w Settings).
- [x] **Step 2: Przejście `recording` do detektora.** `OfferDetector.step` dostaje `recording` z `recording.isRecording` w każdym tiku (przejście `true → false` wycisza trwającą rozmowę — T3).
- [x] **Step 3b: Kontrakty z adapterami (przegląd Opusa po T6).** `AudioProcessSource.snapshot()` zwraca `nil` przy błędzie odczytu — monitor pomija wtedy tik (nie woła `step` z pustą listą). EventKit wołaj z jednego aktora. Wygasłe `calendarIDs` (identyfikator kalendarza ginie po pełnej synchronizacji) dają `events == []` bez sygnału: monitor/Settings mają pokazać „Selected calendars not found — re-select" zamiast cichego braku ofert (stan `.calendarSelectionStale` obok `.calendarDenied`).
- [x] **Step 3a: Kontrakty z `OfferDetector` (przegląd Opusa).** `.hide` przychodzi także w pierwszym tiku z `recording == true` — monitor zdejmuje wtedy wyłącznie stan Offer, nie panel Recording. `.startRecording` zastępuje `.show` w tym samym tiku i nie powtarza się; gdy start się nie powiedzie (np. brak uprawnień), monitor woła `dismiss()`, żeby nie wisiał stan „startuje". Tiki monitora co 1 s; przy przerwie między tikami > 3 s (uśpienie, App Nap) detektor zeruje ciągłość mikrofonu (T3b).
- [x] **Step 3: Kontrakt zakończenia.** Sygnał końca daje wyłącznie pytanie w pigułce; istniejące `SilenceCondition` (600 s), `HardLimitCondition`, `StallCondition` **bez zmian** (jedyne samoczynne zatrzymanie).
- [ ] **Step 4: Weryfikacja ręczna** (pełny odbiór w T13): ad hoc Teams → oferta → Start → rozłączenie → pytanie; `scripts/test.sh` zielony; commit.

---

### Task 11: Pasek menu i aplikacja żyje po zamknięciu okna — **STOP po zadaniu**

Spec §4.8. Po zadaniu **przegląd Opusa**.

**Files:**
- Modify: `Sources/MeetNotesApp/MeetNotesApp.swift` (`MenuBarExtra`, zachowanie po zamknięciu okna)

**Interfaces:**
- Consumes: `MeetingMonitor.state` (T10), `AppModel.setLaunchAtLogin` (T7).

- [ ] **Step 1: `MenuBarExtra`** z menu: stan wykrywania (Detecting meetings / Detection off), „Open MeetNotes", „Quit MeetNotes" (tekst pod spodem: „Quitting turns off detection"). Ikona w Docku zostaje (bez `LSUIElement`).
- [ ] **Step 2: Zamknięcie okna nie kończy aplikacji** (`applicationShouldTerminateAfterLastWindowClosed` → `false`, jeśli domyślne zachowanie `WindowGroup` na to nie pozwala); pigułka działa przy zamkniętym oknie.
- [ ] **Step 3: Weryfikacja ręczna:** zamknij okno, wymuś ofertę, sprawdź pigułkę; „Quit" wyłącza wykrywanie; `scripts/test.sh` zielony; commit.

**🛑 STOP (Opus + użytkownik):** przed odbiorem na żywo — krótki przegląd, czy nic nie startuje nagrywania bez Teams, czy po Stop rozmowa nie wywołuje auto-startu od nowa i czy „Quit" faktycznie wyłącza wykrywanie.

---

### Task 12: Lista wyboru wydarzenia w nagłówku notatki

Spec §4.7, zrzut `SCR-20261016-qiay`.

**Files:**
- Create: `Sources/MeetNotesMeetings/EventRanking.swift`, `Sources/MeetNotesApp/EventPickerView.swift`
- Modify: `Sources/MeetNotesApp/MeetingDetailView.swift` (chip daty w nagłówku → okno wyboru), `Sources/MeetNotesApp/AppModel.swift` (`link(event:to:)`, `unlink(_:)`)
- Test: `Tests/MeetNotesMeetingsTests/EventRankingTests.swift`

**Interfaces:**
- Consumes: `EventFilter.isPickable`, `CalendarSource.events`, `NotesStore.updateMeta`.
- Produces: `enum EventRanking { static func order(_ events: [CalendarEventInfo], recordingStart: Date, recordingEnd: Date?, now: Date) -> [Ranked] }`, `struct Ranked: Equatable { var event: CalendarEventInfo; var overlapsRecording: Bool }`; `AppModel.link(_ event: CalendarEventInfo, to item: SessionItem)` i `unlink(_ item: SessionItem)` (przez `updateMeta`; `notes.onChange` odświeża).

- [ ] **Step 1: Testy (padają):** `eventsAreOrderedByDistanceFromRecordingStart`, `overlappingEventsAreFlagged`, `allDayAndOutOfOfficeAreNeverListed`, `inPersonEventsWithoutALinkAreListed`, `nilRecordingEndUsesNowAsTheEnd` (nagranie w toku: bez `recordingEnd` nakładanie liczone względem `now`).
- [ ] **Step 2–3:** FAIL → implementacja → PASS.
- [ ] **Step 4: UI:** klik chipu daty otwiera „Select calendar event" — lista z dnia nagrania (wg rankingu, nakładające się wyróżnione), wiersz „Unlink" gdy jest powiązanie, wiersz „Connect Apple Calendar in Settings" gdy kalendarz niepodłączony; **bez** pola „Add attendees…" (nie-cel). Powiązanie działa dla starych notatek i dla ad hoc. Uczestnicy z migawki pokazani w nagłówku (tylko wyświetlanie).
- [ ] **Step 5: Weryfikacja ręczna** na starej notatce z `.devdata`; `scripts/test.sh`; commit.

---

### Task 13: Odbiór na żywo, dokumentacja, przegląd całości

**Files:**
- Create: `docs/superpowers/reports/F16-odbior.md`
- Modify: `CLAUDE.md` (sekcja „Stan"), `docs/superpowers/ROADMAP.md`, `docs/superpowers/BACKLOG.md` (jeśli pojawią się odłożone drobiazgi)

- [ ] **Step 1: Odbiór — robi użytkownik, na sprzęcie** (każdy punkt: ✅/❌ + uwaga w raporcie), kryteria 1–16 ze speca §6 (w tym 6a), w tym nazwane: **wizyta u lekarza i urodziny nie wywołują pigułki; OOO w prawdziwym Exchange nie wywołuje pigułki; poczekalnia Teams nie wywołuje pigułki (albo odstępstwo opisane po T0); auto-start nigdy na samym kalendarzu; po ręcznym Stop trwająca rozmowa nie startuje nagrania od nowa; zamknięcie okna nie wyłącza wykrywania.**
- [ ] **Step 2:** poprawki z odbioru (bez ślepych napraw — STOP przy rozbieżnościach ze specem).
- [ ] **Step 3:** `scripts/test.sh` zielony (liczba testów w raporcie), `check-bundle` widzi klucz kalendarza.
- [ ] **Step 4: Przegląd całości przez Opusa** przed scaleniem `faza16`.
- [ ] **Step 5: Dokumenty:** `CLAUDE.md` → stan fazy 1.6; ROADMAP: 1.6 zamknięta, „Coming up" i integracje Google/Outlook/Slack zostają.
- [ ] **Step 6: Commit** (jawne ścieżki). **Scalenie i tag — decyzja użytkownika.**

---

## Self-review (pokrycie speca)

| Wymóg speca | Zadanie |
|---|---|
| §4.1 Integrations, Meeting detection, „Coming soon" | T5, T7 |
| §4.2 A (kalendarz) i B (ad hoc per proces, bez własnego procesu), zbieg, „Not a meeting", cisza po Stop | T3, T6, T10 |
| §4.3 filtr (link, całodniowe, OOO, odrzucone), lista ręczna | T2, T12 |
| §4.4 stany pigułki | T8 (prefactoring), T9 |
| §4.5 auto-start tylko przy Teams | T3 (reguła i testy), T10 |
| §4.6 koniec: zwolnienie mikrofonu, cisza, zawsze tylko pytanie, bezpiecznik 600 s bez zmian („Continue" go nie przedłuża) | T4, T10 |
| §4.7 powiązanie, migawka, tytuł, `AutoTitle` | T1, T9, T12 |
| §4.8 pasek menu, uruchamianie przy logowaniu | T7, T11 |
| §4.9 `Info.plist`, `check-bundle` | T0 |
| §4.10 nowa biblioteka z testami | T1 |
| §5 spike | T0 |
| §6 kryteria akceptacji | T13 (na żywo), T1–T4, T12 (testy) |

Nie-cele (patrz „Poza zakresem" na górze) nie mają zadań z założenia.
