# Strona główna z „Coming up” (macos.md §11.5, wariant B)

Gałąź `claude/infallible-wu-2aef0e` (od `faza15` @ 5f3f696). Zadanie: decyzja użytkownika 2026-10-19, makiety
`b-cuB2.png`, `b-cuB2none.png`. Scalenie do `faza15` należy do użytkownika.

## Commity

- 0fa71d5 — `ComingUp` (MeetNotesMeetings): wybór karty i „Later today”, nazwa aplikacji z linku, etykieta czasu; 8 testów.
- 60b0c4f — widok: nagłówek (tytuł, wyszukiwarka 170 pt, popup presetu 96 pt, „● Record” ad hoc), karta najbliższego
  spotkania, linia pod kartą albo linia bez karty; karta „Record a meeting” usunięta; `startRecording(event:background:)`;
  `todaysEvents(now:)`; migawki.
- HEAD — ten raport.

`scripts/test.sh`: `test.sh: 342/342 testów uruchomionych i zaliczonych.` (było 334 + 8 nowych).

## Co działa jak w specu

- Nagłówek zawsze: „Meetings”, wyszukiwarka, jeden popup presetu (`activePresetID`, ten sam co w ofercie pigułki),
  „● Record”. Jest primary, gdy nie ma karty. Przy karcie jest drugorzędny i wtedy primary jest Record na karcie.
- Karta: zaczyna się w ciągu 60 min (włącznie) albo trwa. Linia „Next · in 8 min · 🎥 Teams” (Google Meet, Zoom z linku;
  bez linku „In person”), tytuł New York 20, „10:00 – 10:30 · 6 attendees · notes titled and linked to this event”.
- Record na karcie = `startRecording(event:)`: `calendarEvent` w `NoteMeta` zapisuje ta sama ścieżka co oferta pigułki.
  Tytuł notatki bierze się z `calendarEvent` przez `NoteTitle` (nic nowego). Błąd presetu przełącza na Presets jak
  start ręczny (oferta w tle nadal tylko `lastError`).
- Filtr: `isPickable` z 1.6 (całodniowe i OOO ≥ 24 h ukryte), wydarzenia bez linku widoczne. Oferta pigułki bez zmian:
  `isOfferable` nadal wymaga linku.
- Bez karty: „No more meetings today.” + „Open Calendar” (otwiera Kalendarz). Bez kalendarza: „See your meetings here
  and start recording from them.” (tekst z makiety `b-cuEmpty`) + „Connect Apple Calendar…” → Settings.
- Odświeżanie: `TimelineView(.everyMinute)`. EventKit (jeden dzień) jest pytany tylko w `ComingUpHeader`: co minutę,
  przy zmianie Settings albo stanu nagrania oraz przy każdym znaku w wyszukiwarce (nagłówek obserwuje `MeetingsViewState`).
  Nie co sekundę, bo licznik nagrania tego widoku nie odświeża. Lista dni i tak przeszukuje transkrypty przy każdym
  znaku, więc dodatkowe zapytanie o jeden dzień nie robi różnicy.

## Mutacje (każda: wprowadź → `scripts/test.sh --filter ComingUpTests` → `git checkout`)

| # | Mutacja w `ComingUp.swift` | Padł test |
|---|---|---|
| M1 | próg `start <= now + window` → `<` | `cardShowsAMeetingStartingWithinSixtyMinutesInclusive` |
| M2 | trwające: `end > now` → `start > now` | `cardShowsAnOngoingMeetingAndDropsEndedOnes`, `nearestStartWinsBetweenOngoingAndUpcoming` |
| M3 | bez `isPickable` (całodniowe, OOO) | `allDayAndOutOfOfficeAreHidden` |
| M4 | bez `start < dayEnd` (koniec dnia) | `laterTodayStopsAtMidnight` |
| M5 | bez `myStatus != .declined` | `declinedAndCanceledAreHiddenButMeetingsWithoutALinkAreShown` |
| M6 | najbliższy start → najwcześniejszy start | `nearestStartWinsBetweenOngoingAndUpcoming` |

Uwaga do śladowości: pierwsza seria M2–M5 była nieważna (plik nie był jeszcze w gicie, `git checkout` go nie
przywrócił i mutacje się nałożyły). Przywróciłem plik ręcznie, zrobiłem commit 0fa71d5 i powtórzyłem M2–M6 pojedynczo.
Tabela pokazuje tę drugą serię. M1 był pierwszą zmianą, więc jest ważny.

## Migawki (`scripts/snapshot.sh`, `.design/review/`, oba motywy)

- `meetings-next-*`: 9:52, standup za 8 min, Later today 11:30 / 14:00 Dentist (in person) / 16:00. Urodziny
  (całodniowe) i OOO (72 h) odfiltrowane. Zgodne z `b-cuB2.png`.
- `meetings-none-*`: 17:00, „No more meetings today.” · Open Calendar, Record w nagłówku primary. Zgodne z `b-cuB2none.png`.
- `meetings-later-*`: 12:40, nic w 60 min, ale 14:00 i 16:00 później (patrz D1).
- `meetings-*` / `meetings-full-*`: kalendarz niepodłączony → „Connect Apple Calendar…”.

## Decyzje do potwierdzenia przez użytkownika (przyjąłem domyślne, łatwe do zmiany)

- **D1. Nic w 60 min, ale coś później dziś.** Spec mówi wtedy „No more meetings today”, co byłoby nieprawdą. Zamiast tego
  ta sama linia ma tekst „Later today: 14:00 Dentist (in person) · 16:00 1:1 Adrian” + „Open Calendar”, a Record
  w nagłówku jest primary (migawka `meetings-later`).
- **D2. Trwające i nadchodzące naraz.** Karta bierze wydarzenie z najbliższym startem (w przód albo w tył), remis po id,
  jak `OfferDetector`. Dzięki temu karta i pigułka wskazują to samo. Przykład: trwa od 50 min, a następne jest za 5 min,
  więc karta pokazuje następne.
- **D3. Etykieta trwającego:** „Now · started 5 min ago · Teams”, w pierwszej minucie „Now · starting”. Spec opisuje tylko „Next · in N min”.
- **D4. Odrzucone i anulowane ukryte** (spec 1.6 decyzja 10 „bez odrzuconych”). `isPickable` z ręcznego wyboru ich nie
  odcina. Bez odpowiedzi (*pending*) są widoczne, bo są w kalendarzu.
- **D5. OOO czasowe krótsze niż 24 h** (np. blok 9–17 bez flagi całodniowego) przechodzi przez `isPickable` i pokaże się
  jako „Now · In person” przez cały blok. Ostrzejszy próg (8 h jak w `isOfferable`) to zmiana jednej linii.
- **D6. Północ:** karta i „Later today” tylko do końca dnia `now`. O 23:50 spotkanie o 00:15 nie daje karty.
- **D7. W trakcie nagrania** nagłówek pokazuje „■ Stop” jako primary (jak dawna karta), a Record na karcie jest wyłączony
  (secondary, podpowiedź „A recording is already in progress”).
- **D8. Co zniknęło z kartą „Record a meeting”:**
  - „PL · model” jest teraz w podpowiedzi popupu presetu;
  - ostrzeżenie Auto (W§2) to linia `WarnLabel` „Auto language: the preset has no fixed language” pod nagłówkiem, tylko
    przy presecie Auto (bez migawki tego stanu);
  - „Create a preset to start” jest w podpowiedzi. Record bez presetu przełącza na Presets z komunikatem, jak dotąd.
- **D9. Kolumna 600 pt** (makieta `width:600px`, było 580). Placeholder wyszukiwarki zostaje „Search meetings” (makieta: „Search”).

## Odbiór na żywo — DO ZROBIENIA u użytkownika

Uruchomienie: `scripts/run.sh` (paczka podpisana „MeetNotes Dev”, więc zgoda na kalendarz zostaje z 1.6). Dane są w
`.devdata/` katalogu, z którego się uruchamia. Z własnymi danymi: po scaleniu do `faza15` z
`/Users/michalprzytulski/meetnotes`. Z worktree `.claude/worktrees/infallible-wu-2aef0e` dane są puste, więc najpierw
trzeba zrobić preset i włączyć Apple Calendar w Settings → Integrations. Do tego czasu strona pokazuje
„Connect Apple Calendar…”.

| # | Punkt | Wynik |
|---|---|---|
| 1 | Spotkanie w kalendarzu za ≤ 60 min → karta z „Next · in N min · Teams”, liczba się zmienia co minutę | ⏳ |
| 2 | Record na karcie → nagranie, notatka ma tytuł wydarzenia, nagłówek notatki pokazuje powiązanie | ⏳ |
| 3 | Wydarzenie bez linku (np. lekarz) → karta „In person”, brak oferty pigułki | ⏳ |
| 4 | Całodniowe / OOO nie pojawiają się ani na karcie, ani w „Later today” | ⏳ |
| 5 | Po ostatnim spotkaniu: „No more meetings today.” · Open Calendar otwiera Kalendarz | ⏳ |
| 6 | „● Record” w nagłówku: ad hoc bez wydarzenia; primary tylko bez karty | ⏳ |
| 7 | Kalendarz wyłączony w Settings → „Connect Apple Calendar…” przechodzi do Settings | ⏳ |

## Odłożone (wpisane do BACKLOG, sekcja „Z wdrożenia »Coming up«”)

- Odświeżanie po `EKEventStoreChanged` jest najpóźniej po minucie, nie od razu. Gdyby przeszkadzało, wystarczy
  podpiąć `calendarSource.changes`.
- Nieaktualny wybór kalendarzy (`calendarSelectionStale` monitora) na stronie głównej wygląda jak „No more meetings today”.

Merge Danger: odwracalne — bez zmian formatu na dysku (`calendarEvent` istniał od 1.6), bez TCC i pęku kluczy.
