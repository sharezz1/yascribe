# Faza 1.6 „Kalendarz i wykrywanie spotkań" — design

> Status: **do przeglądu użytkownika**, 2026-10-16. Powstał w wątku brainstormingu (decyzje
> użytkownika w §3, dosłownie tak, jak zapadły). Następny krok po akceptacji: plan w
> `docs/superpowers/plans/` (skill writing-plans). **Kodu aplikacji nie piszemy do akceptacji
> speca i planu.**
>
> Wejścia: zrzut Granoli `SCR-20261016-qiay` (wybór wydarzenia kalendarza przy dacie notatki),
> `docs/wymagania.md` §1 i §5, `docs/design/inspiracje/` (Granola, Wispr Flow),
> `Sources/MeetNotesRecording/EndCondition.swift`, `Sources/MeetNotesNotes/NoteTitle.swift`.
> Interfejs aplikacji po angielsku; opisy w repo po polsku.
>
> **Ten spec zastępuje W§1 i W§5 w jednym punkcie** (koniec sesji z kalendarza) — patrz §4.6.

## 1. Cel i dlaczego

Dziś użytkownik sam pamięta, żeby wcisnąć Record, sam wpisuje tytuł i sam wie, do którego
spotkania należy nagranie. Granola i Wispr Flow robią to za niego: wiedzą, że spotkanie się
zaczyna, podpowiadają nagrywanie, nazywają notatkę nazwą spotkania i pozwalają przypiąć
nagranie do wydarzenia.

Faza 1.6 daje MeetNotes to samo, w trzech krokach: **(1)** aplikacja wykrywa początek spotkania
(z kalendarza albo z rozmowy ad hoc, np. w Teams) i pokazuje pigułkę nagrywania; **(2)** notatka
dostaje tytuł z nazwy spotkania; **(3)** przy dacie notatki można wybrać wydarzenie i powiązać je
z transkrypcją. Aplikacja wykrywa też **koniec** rozmowy i pyta (albo kończy sama).

Kryterium sukcesu (od użytkownika, sprowadzone do testu): rozpoczynam spotkanie z Teams →
pojawia się pigułka z nazwą spotkania → Start → po rozłączeniu pigułka pyta, czy kończyć →
notatka ma tytuł spotkania i widać powiązane wydarzenie.

> **Wzorzec: Fireflies** (`SCR-20261016-qoja`) wybiera spotkania z kalendarza po **linku do
> wideokonferencji**. Bierzemy kryterium, nie bota: nasze nagrywanie jest lokalne, bez
> uczestnika-bota i bez chmury.

## 2. Cele, nie-cele, anty-cele

**Cele**
- Wykrycie startu spotkania z Kalendarza Apple (opcjonalnie) i z rozmowy ad hoc (Teams jako
  przypadek główny).
- Pigułka z ofertą nagrywania; przełącznik auto-startu w Settings.
- Wykrycie końca spotkania **niezależne od godziny końca w kalendarzu**; tryb „pytaj" albo
  „kończ sam".
- Tytuł notatki z nazwy wydarzenia; ręczne podpięcie/odpięcie wydarzenia do istniejącej
  notatki (także starej, także dla spotkania ad hoc).
- Sekcja Integrations w Settings: Apple Calendar (działa), Google Calendar / Outlook / Slack
  (wyszarzone, „Coming soon").

**Nie-cele (jawnie)**
- Integracje Google Calendar, Outlook, Slack — **tylko wiersze UI, zero kodu integracji**.
- Strona główna „Coming up" / oś nadchodzących spotkań (W§5) — zostaje w „Nieprzypisanych"
  w ROADMAP.
- Zapis do kalendarza. Dostęp wyłącznie do odczytu (nie tworzymy ani nie zmieniamy wydarzeń).
- Automatyczne zgadywanie wydarzenia dla spotkania ad hoc. Powiązanie ad hoc jest ręczne.
- Wysyłanie danych kalendarza do dostawców API (prompty notatki, autotytułu). Tytuł i uczestnicy
  zostają lokalnie; w 1.6 uczestnicy są tylko **pokazywani**, nie trafiają do promptów
  (tożsamość mówcy to osobny temat, W§4).
- Powiadomienia systemowe macOS. Sygnałem jest wyłącznie pigułka.
- Diaryzacja, nazwiska mówców, EventKit-owy „mechaniczny koniec sesji" z W§5.

**Anty-cele (porażka, nawet jeśli technicznie działa)**
- 🔴 **Pigułka (a tym bardziej nagrywanie) uruchomiona, gdy nie ma spotkania.** To jest to, co
  użytkownik określił jako najbardziej irytujące. Przy każdej decyzji projektowej: precyzja
  przed czułością — wolimy przegapić rozmowę niż pokazać pigułkę bez spotkania.
- Nagranie spotkania, w którym użytkownik nie uczestniczy lub które odrzucił.
- Ucięcie trwającego spotkania w środku (przy końcu: wolimy pytanie niż samowolny stop).

## 3. Decyzje użytkownika (2026-10-16)

1. Aplikacja wie o spotkaniach z kalendarza, wykrywa ich początek i **uruchamia pigułkę**.
2. Tytuł notatki pochodzi z nazwy spotkania.
3. Przy dacie notatki klik → lista wydarzeń → wybór spotkania; powiązanie z transkrypcją
   (jak w Granoli, zrzut `SCR-20261016-qiay`: „Select calendar event", uczestnicy).
4. Uczestnicy z wydarzenia przychodzą razem z powiązaniem — jako dodatek, nie rdzeń.
5. **Nagrywanie nie rusza automatycznie z domu**; w Settings jest opcja „nagrywaj
   automatycznie / nie".
6. Wykrywanie **nie opiera się tylko na kalendarzu**: rozmowa ad hoc (Teams) też ją wywołuje.
7. Połączenie z Kalendarzem Apple jest **opcją w Settings** — kto chce, ten łączy. Google
   Calendar, Outlook i Slack dojdą później; teraz wyszarzone z napisem „Coming soon".
8. **Koniec spotkania wykrywa aplikacja, nie kalendarz** (godzinne spotkanie kończące się po
   15 min = stop po 15 min). Albo aplikacja kończy sama, albo pyta „Spotkanie się skończyło?
   Zakończyć czy kontynuować".
9. Najgorszy możliwy błąd: **start, gdy nie ma spotkania**.
10. Filtr wydarzeń: bez całodniowych (urodziny, OOO), bez odrzuconych. **Out of office dodaje
    wydarzenie całodniowe — trzeba uważać** (§4.3).
11. **Pigułka z kalendarza tylko dla wydarzeń z linkiem do spotkania online** (Teams, Meet, Zoom…),
    jak w Fireflies („meetings with web-conf link"). Wizyta u lekarza, urodziny i inne wydarzenia
    bez linku **nie startują pigułki**. Spotkanie stacjonarne zaczynasz ręcznie (§4.3).
12. **Auto-start tylko przy Teams, nigdy na samym kalendarzu** (§4.5).
13. **Ikona na pasku menu** (aplikacja żyje po zamknięciu okna) i **opcjonalne uruchamianie przy
    logowaniu** (§4.8).

## 4. Projekt

### 4.1 Settings → Integrations

Nowa sekcja w Settings (obok Providers / Recordings / Archive search), cztery wiersze:

| Wiersz | Stan | Zachowanie |
|---|---|---|
| Apple Calendar | działa | przełącznik Connect; przy pierwszym włączeniu systemowy monit o dostęp (klika użytkownik); po włączeniu: lista kalendarzy z polami wyboru (domyślnie wszystkie) |
| Google Calendar | wyszarzony | „Coming soon" |
| Outlook | wyszarzony | „Coming soon" |
| Slack | wyszarzony | „Coming soon" |

Osobna sekcja (nazwa robocza **Meeting detection**) z ustawieniami, które działają **także bez
połączonego kalendarza**:
- *Detect calls* (rozmowy ad hoc) — włącznik, domyślnie włączony. **(Moja decyzja:** domyślnie
  włączony, bo użytkownik chce tego jak w Granoli; pigułka niczego nie nagrywa sama.)
- *Start recording automatically* — domyślnie **wyłączony**.
- *Launch at login* — domyślnie **wyłączone** (§4.8).
- *When the meeting ends* — „Ask me" (domyślnie) / „Stop automatically".
- Zaawansowane (zwijane): lista ignorowanych aplikacji, progi czasowe z §4.2 i §4.6.

Wszystkie nowe pola `GlobalSettings` są **opcjonalne** (zasada CLAUDE.md, lekcja E6).

### 4.2 Sygnały startu

Dwa niezależne źródła; oba dają ten sam wynik — **jedną** pigułkę w stanie „oferta".

**A. Kalendarz (gdy Apple Calendar połączony).** Wydarzenie przechodzące filtr §4.3 (w tym: ma
link do spotkania online) zaczyna się → oferta z nazwą wydarzenia. Oferta pojawia się w oknie od `start − 1 min` do `start + 10 min`
(wartości nastawne; **moja decyzja**) i znika, jeśli użytkownik jej nie ruszył (nie jest to
porażka — wydarzenie mogło być spotkaniem stacjonarnym lub opuszczonym).

**B. Rozmowa ad hoc.** Aplikacja rozpoznaje, że **inny proces** używa mikrofonu jako aplikacja
rozmów.
- 🔴 **Sygnał per proces, nie per urządzenie.** Gdy MeetNotes nagrywa, sam trzyma mikrofon;
  sygnał „mikrofon w użyciu gdziekolwiek" pozostałby prawdziwy po rozłączeniu Teams i
  uniemożliwiłby wykrycie końca. Sygnał wyprowadzamy z listy obiektów procesów Core Audio
  (ta sama rodzina API co nasz process tap: lista procesów z flagą „wejście aktywne" i bundle ID).
  **Do zweryfikowania na sprzęcie w spike (§5), nie zakładamy z pamięci.** Proces MeetNotes
  jest wykluczony z sygnału.
- Do oferty kwalifikuje się tylko aplikacja ze **znanej listy rozmów** (na start: Teams —
  nowy `com.microsoft.teams2` i jego procesy pomocnicze oraz Teams w przeglądarce; lista nastawna),
  używająca mikrofonu **nieprzerwanie przez ≥ T_start** (wartość z pomiaru, szkic: 10–15 s).
  Ignorowane z założenia: dyktowanie, Wispr Flow, Voice Memos itp. (lista nastawna).
- Brak dopasowania do znanej aplikacji → **brak oferty** (precyzja przed czułością). Rozszerzanie
  listy (Meet, Zoom, huddle) to dopisanie bundle ID po pomiarze, nie zmiana projektu.

**Zbieg A + B** (wydarzenie z kalendarza i Teams używa mikrofonu): jedna pigułka, z tytułem
wydarzenia i z przypiętym wydarzeniem. Wydarzenie z kalendarza, którego okno oferty trwa,
jest dobierane do sygnału B automatycznie **tylko** w tym zbiegu (okno oferty A aktywne);
w pozostałych przypadkach ad hoc zostaje bez wydarzenia (nie zgadujemy — patrz nie-cele).

**„To nie spotkanie".** Pigułka-oferta ma przycisk odrzucenia. Odrzucenie wycisza ofertę dla
tej samej sesji mikrofonu (ten sam proces, ciągłe użycie) albo tego samego wydarzenia.
**(Moja decyzja.)**

### 4.3 Filtr wydarzeń

Wydarzenie kwalifikuje się do **oferty pigułki** wyłącznie, gdy spełnia **wszystkie** warunki
(na polach, które EventKit faktycznie zwraca; dokładne mapowanie potwierdza spike §5):

1. **ma link do spotkania online** — warunek rozstrzygający (decyzja 11). Szukany w polu URL,
   lokalizacji i treści wydarzenia (Exchange potrafi trzymać link w każdym z nich; **które —
   rozstrzyga spike**). Rozpoznawane wzorce: Teams (`teams.microsoft.com/l/meetup-join`,
   `teams.live.com`), Google Meet, Zoom, Webex; lista nastawna. Wizyta u lekarza, wydarzenie
   „dojazd", urodziny, przypomnienia, bloki „focus time" nie mają linku → **brak oferty**;
2. nie jest całodniowe (`isAllDay == false`) — urodziny, święta, OOO całodniowe;
3. nie jest wielodniowe ani dłuższe niż próg (domyślnie 8 h; nastawny) — OOO bywa blokiem
   czasowym lub kilkudniowym, nie tylko całodniowym;
4. dostępność nie jest „nieobecny" / „poza biurem" (`availability` ≠ `.unavailable` w
   przypadkach, które spike wskaże jako OOO; **reguła zależna od tego, co Exchange faktycznie
   emituje**);
5. status użytkownika nie jest „odrzucone" ani „anulowane" (`participantStatus == .declined`,
   `status == .canceled`).

Warunek „ma innych uczestników" (poprzednia wersja) **odpada**: link jest od niego mocniejszy
(wizyta u lekarza nie ma uczestników, ale spotkanie z linkiem bez uczestników też jest rozmową
online). Out of office jest odcięty podwójnie: brakiem linku **i** warunkami 2–4.

**Skutek, który przyjmujemy świadomie:** spotkanie stacjonarne z uczestnikami, ale bez linku,
**nie dostaje pigułki z kalendarza** — zaczynasz je ręcznie (Record), a potem możesz przypiąć
wydarzenie (§4.7). Precyzja przed czułością (anty-cel #1).

Wydarzenia z **ręcznego wyboru** (§4.7) nie podlegają warunkom 1 i 5 — użytkownik świadomie
wskazuje spotkanie (także stacjonarne bez linku); lista **ukrywa całodniowe i OOO** (zawsze).

> **Kryterium akceptacji (nazwane):** *„Out of office w prawdziwym kalendarzu Exchange
> użytkownika nie wywołuje pigułki."* Sprawdzane w spike na jego kalendarzu **przed**
> zamrożeniem reguły w planie.

### 4.4 Pigułka — stany

Pigułka (istniejąca, `RecordingController.showPanel`, zwijana, z poziomami torów) dostaje
dwa nowe stany obok „nagrywa":

| Stan | Treść | Przyciski |
|---|---|---|
| **Offer** | nazwa wydarzenia (lub „Call in Teams" przy ad hoc) | Start · „Not a meeting" |
| **Recording** | jak dziś; tytuł wydarzenia obok presetu | Stop |
| **End prompt** | „Meeting ended?" | Stop · Continue |

Pigułka-oferta **nie przejmuje fokusu** i nie wymaga okna głównego (decyzja (c) z odbioru 1.5a:
stanie się oknem klucza nie fokusuje Stop). Start z oferty używa presetu wybranego na stronie
głównej (jak dziś przycisk Record).

### 4.5 Auto-start

Przełącznik w Settings, domyślnie wyłączony. **Decyzja użytkownika 2026-10-16 (§3 pkt 12):**
gdy włączony, nagrywanie startuje samo **tylko** gdy trwa rozmowa w znanej aplikacji (Teams):

- zbieg A + B (wydarzenie z kalendarza **i** znana aplikacja rozmów trzyma mikrofon), albo
- B samo (znana aplikacja rozmów, ciągle ≥ T_start).

**Nigdy na samym kalendarzu (A), nawet z linkiem.** Link dowodzi, że spotkanie jest online, a nie
że użytkownik w nim uczestniczy (słucha z innego urządzenia, siedzi w sali, opuścił je); samoczynne nagrywanie takiego
wydarzenia to najgorszy możliwy błąd. Przy samym A pigułka zawsze czeka na Start.

### 4.6 Wykrywanie końca (zastępuje W§1/W§5 w punkcie „koniec z kalendarza")

> **Zmiana względem dokumentów źródłowych.** `wymagania.md` §1 wymienia „koniec wydarzenia w
> kalendarzu" jako warunek mechaniczny, a §5 mówi „jedna integracja załatwia dwie rzeczy".
> Użytkownik 2026-10-16 odrzucił to: **godzina końca z kalendarza nie wpływa na zatrzymanie**.
> Ten spec zastępuje te zdania; W§1 i W§5 są poprawione tym samym commitem. Pozostałe warunki
> W§1 (zamknięcie okna rozmowy, cisza) zostają i są tu doprecyzowane.

Sygnały końca:

1. **Aplikacja rozmów zwolniła mikrofon** (per proces, §4.2) na ≥ T_release (szkic: 20 s;
   pomiar). Dotyczy aplikacji uznanej za „śledzoną": tej, która trzymała mikrofon w trakcie
   nagrania (**moja decyzja**; start ręczny też ją uzyska, jeśli znana aplikacja zacznie
   rozmowę w trakcie). Spike sprawdza, czy Teams zwalnia wejście przy wyciszeniu — jeśli tak,
   wyciszenie jest fałszywym końcem i T_release/okna muszą to uwzględnić.
2. **Cisza na obu torach** ≥ T_silence (szkic: 3 min). Samo w sobie zawodne (prezentacja bez
   mówienia, wszyscy wyciszeni) — dlatego **zawsze pyta**, nigdy nie zatrzymuje samo w tym trybie.

Zachowanie wg Settings *When the meeting ends*:

- **Ask me (domyślnie):** sygnał 1 lub 2 → stan *End prompt*. „Continue" wycisza pytanie na
  T_snooze (szkic: 10 min; **moja decyzja**), „Stop" kończy.
- **Stop automatically:** sygnał 1 → stop z powodem `meetingEnded` (nowy przypadek `EndReason`).
  Sygnał 2 (cisza) nadal tylko pyta.

**Co z istniejącym `SilenceCondition` (600 s)?** Zostaje bez zmian jako **twardy bezpiecznik**
w obu trybach: dziś kończy sesję po 10 min ciszy bez pytania i **nie usuwamy go**, bo to
zabezpieczenie przed „70 min przypadkowego dźwięku" z W§1 (pytanie, na które nikt nie
odpowiada, nie może wisieć w nieskończoność). W trybie *Ask me* pytanie pojawia się po
T_silence (3 min) i, jeśli nikt nie odpowie, sesję kończy bezpiecznik po 10 min ciszy.
`HardLimitCondition` (4 h) i `StallCondition` (30 s) bez zmian. **(Moja decyzja.)**

`EndCondition` jest protokołem „żeby kalendarz dało się dołożyć bez dotykania rdzenia" — kalendarz
**nie jest** dokładany; sygnały końca z 1–2 działają w warstwie aplikacji (stan pigułki) i, dla
`meetingEnded`, przez wywołanie `stop(reason:)`. Rdzeń nagrywania dostaje tylko nowy `EndReason`.

### 4.7 Powiązanie wydarzenia z notatką

**UI.** W nagłówku notatki (jak na zrzucie: chip z datą/dniem i „Me") klik otwiera okno
„Select calendar event": lista wydarzeń z dnia nagrania, posortowana wg bliskości początku
nagrania, wydarzenia nakładające się na czas nagrania wyróżnione; pole „Add attendees…" ze
zrzutu **nie** wchodzi (nie-cel). Wiersz „Unlink" odpina. Klik w wydarzenie powiązuje.
Dostępne także dla notatek bez kalendarza w momencie nagrania i dla starych notatek (z sesją i
czasem startu). Gdy Apple Calendar niepodłączony: lista pokazuje wiersz „Connect Apple Calendar
in Settings".

**Dane.** `NoteMeta` (`notes/meta.json`) dostaje opcjonalne `calendarEvent: CalendarLink?`:

```
CalendarLink {
  title, start, end, calendarName?
  attendees: [{ name?, email? }]      // migawka; tylko do pokazania
  eventIdentifier                     // lokalny, niestabilny dla Exchange
  externalIdentifier?                 // calendarItemExternalIdentifier
  occurrenceStart                     // dla wydarzeń cyklicznych: data wystąpienia
}
```

- **Migawka + identyfikatory.** `eventIdentifier` nie jest stabilny dla Exchange; wydarzenia
  cykliczne mają wspólny identyfikator serii — dlatego `externalIdentifier` + `occurrenceStart`.
- **Notatka musi przeżyć** usunięcie wydarzenia, wyłączenie Apple Calendar i cofnięcie dostępu:
  pokazujemy migawkę; odświeżenie z kalendarza jest best-effort i nigdy nie kasuje migawki.
- Pola opcjonalne (E6): stary `meta.json` bez `calendarEvent` czyta się bez zmian.

**Tytuł.** Kolejność: **ręczny > kalendarz > auto > tytuł z notatki > „Untitled meeting"**
(dziś `NoteTitle.display`: ręczny > auto > notatka). `AutoTitle` (dziś zapisuje, gdy
`manualTitle == nil && autoTitle == nil`) dostaje **strażnika**: z powiązanym wydarzeniem nie
generuje tytułu. Powiązanie z wydarzeniem po fakcie **przykrywa** istniejący autotytuł
(kalendarz ma wyższy priorytet) bez kasowania go — „Unlink" przywraca autotytuł; ręczny tytuł
zawsze wygrywa. **(Moja decyzja.)**

### 4.8 Obecność aplikacji w tle

Wykrywanie działa tylko, gdy aplikacja **żyje**. Dziś jest to zwykła aplikacja okienkowa,
bez ikony na pasku menu i bez uruchamiania przy logowaniu (w kodzie brak
`MenuBarExtra`/`SMAppService`/`LSUIElement`). **Decyzja użytkownika 2026-10-16 (§3 pkt 13):**

- **Ikona na pasku menu** (`MenuBarExtra`); zamknięcie okna głównego **nie kończy aplikacji**,
  wykrywanie działa dalej. Menu ikony: stan wykrywania (włączone / wyłączone), „Open MeetNotes",
  „Quit" (Quit wyłącza wykrywanie — menu mówi to wprost). **(Moja decyzja:)** ikona w Docku
  zostaje jak dziś (bez `LSUIElement`); pigułka działa niezależnie od okna.
- **„Launch at login"** w Settings, **domyślnie wyłączone**, przez `SMAppService.mainApp`.
  Spike (§5) sprawdza, czy rejestracja działa z podpisem „MeetNotes Dev" i jak zachowuje się
  po przebudowie paczki (stały podpis = stała tożsamość, jak przy TCC).
- Bez „Launch at login" wykrywanie działa tylko od ręcznego uruchomienia aplikacji; ustawienie
  ma przy sobie jedną linijkę o tym.

### 4.9 Uprawnienia i `Info.plist`

- Do `Resources/Info.plist` dochodzi klucz opisu dostępu do kalendarza. **Weryfikujemy nazwę
  klucza dla pełnego dostępu (macOS 14+, szkic: `NSCalendarsFullAccessUsageDescription`)** i
  prosimy o pełny dostęp EventKit (odczyt wydarzeń z uczestnikami wymaga go).
- `scripts/check-bundle.sh` (dziś sprawdza `NSMicrophoneUsageDescription`,
  `NSAudioCaptureUsageDescription`) dostaje nowy klucz.
- Zgodę w systemie klika użytkownik; nie zmieniamy TCC ani Ustawień systemowych (CLAUDE.md).
- Wykrywanie procesów audio nie wymaga nowego uprawnienia TCC — **to założenie weryfikuje spike**.

### 4.10 Struktura kodu (wskazówki dla wykonawcy)

`MeetNotesApp` nie ma targetu testowego (BACKLOG), a logika tej fazy ma sporo decyzji do
przetestowania. **Moja decyzja:** logikę czystą (filtr wydarzeń, maszyna stanów sygnałów start/koniec
z debouncingiem, kolejność tytułów, kodowanie `CalendarLink`) umieścić w **nowej bibliotece**
(robocza nazwa `MeetNotesMeetings`) z targetem testowym uruchamianym przez `scripts/test.sh`;
EventKit i lista procesów Core Audio za cienkimi protokołami, żeby testy działały na danych
syntetycznych. UI i pigułka w `MeetNotesApp`.

## 5. Spike na sprzęcie (przed zamrożeniem planu)

Plik `docs/superpowers/spikes/2026-10-xx-faza16-wykrywanie.md`. Pomiary, bez których żadnej
wartości z §4 nie wpisujemy do planu jako stałej:

1. **Lista procesów audio Core Audio:** czy da się czytać per-procesowo „wejście aktywne" i
   bundle ID; czy wymaga to jakiegokolwiek uprawnienia.
2. **Teams (nowy, `com.microsoft.teams2`, procesy pomocnicze; Teams w przeglądarce):** które
   bundle ID faktycznie trzymają mikrofon podczas rozmowy.
3. **Wyciszenie w Teams:** czy zwalnia wejście (fałszywy koniec).
4. **Poczekalnia / lobby przed dołączeniem:** czy otwiera mikrofon (fałszywy start — anty-cel #1).
5. **Wispr Flow i dyktowanie systemowe:** zachowanie sygnału (lista ignorowanych).
6. **Kalendarz użytkownika (Exchange):** wypisać pola `EKEvent` dla (a) zwykłego spotkania Teams,
   (b) OOO całodniowego, (c) OOO czasowego/wielodniowego, (d) bloku focus time, (e) wydarzenia
   cyklicznego, (f) spotkania odrzuconego, (g) wizyty u lekarza bez linku, (h) urodzin —
   i zweryfikować na nich regułę §4.3. **Osobno: w którym polu (URL / lokalizacja / treść)
   leży link do Teams** i czy dla spotkań Teams jest zawsze w tym samym.
7. Czasy: `T_start`, `T_release`, `T_silence` na prawdziwych rozmowach (kilka sztuk, nie jedna).
8. **`SMAppService.mainApp`** z podpisem „MeetNotes Dev": czy rejestracja uruchamiania przy
   logowaniu działa i przeżywa przebudowę paczki; czy aplikacja bez okna (tylko ikona menu +
   pigułka) dalej widzi listę procesów audio.

Wyniki zamykają §4.3 i wartości progów. Progi i listy w aplikacji są **nastawne** w ustawieniach
zaawansowanych, nie zaszyte.

## 6. Kryteria akceptacji

1. Teams: start rozmowy → pigułka z nazwą (ad hoc: „Call in Teams") w ≤ T_start + 5 s; nic nie
   nagrywa, dopóki użytkownik nie kliknie Start (auto-start wyłączony).
2. Poczekalnia/lobby Teams **nie** wywołuje pigułki (lub: jest dokumentowane odstępstwo z decyzją
   użytkownika).
3. **OOO w prawdziwym kalendarzu Exchange nie wywołuje pigułki** (zwykłe, czasowe i
   wielodniowe).
4. **Wizyta u lekarza (wydarzenie bez linku)**, urodziny (całodniowe), blok „focus time",
   wydarzenie odrzucone i wydarzenie całodniowe nie wywołują pigułki z kalendarza. Spotkanie
   z linkiem Teams — wywołuje.
5. Wydarzenie z kalendarza + Teams razem → jedna pigułka z tytułem wydarzenia.
6. „Not a meeting" ukrywa ofertę i nie wraca w tej samej sesji mikrofonu.
7. Auto-start włączony: rusza tylko dla zbiegu A+B lub B; **nigdy** dla samego A.
8. Rozłączenie z Teams → pytanie „Meeting ended?" w ≤ T_release + 5 s (Ask me) albo stop z
   powodem `meetingEnded` (Stop automatically). Godzina końca z kalendarza nie ma wpływu.
9. Wyciszenie w Teams **nie** kończy spotkania (lub: odstępstwo opisane po spike).
10. Cisza ≥ T_silence → pytanie, nie stop; brak odpowiedzi → stop przez `SilenceCondition` (600 s).
11. Notatka z wydarzeniem: tytuł = nazwa wydarzenia; ręczny tytuł wygrywa; autotytuł nie
    nadpisuje; po „Unlink" wraca autotytuł.
12. Wybór wydarzenia w starej notatce działa; po usunięciu wydarzenia z kalendarza i po wyłączeniu
    Apple Calendar notatka dalej pokazuje migawkę.
13. Stary `meta.json` i stare `GlobalSettings` bez nowych pól wczytują się bez błędu.
14. Apple Calendar niepodłączony: wykrywanie ad hoc działa, lista wyboru pokazuje prośbę o
    połączenie, brak monitu TCC do czasu włączenia.
14a. Zamknięcie okna głównego nie kończy aplikacji; ikona na pasku menu pokazuje stan wykrywania;
    pigułka pojawia się przy zamkniętym oknie; „Quit" wyłącza wykrywanie.
14b. „Launch at login" domyślnie wyłączone; włączone → po ponownym zalogowaniu aplikacja
    startuje i wykrywa bez ręcznego uruchamiania.
15. Wiersze Google Calendar / Outlook / Slack są wyszarzone, nic nie robią i nie ładują kodu
    integracji.
16. `scripts/test.sh` zielony (testy nowej biblioteki wliczone); mutacja każdej bramki
    (filtr OOO, debouncing, kolejność tytułów) → test pada → `git checkout`.

## 7. Moje decyzje (do sprawdzenia przy czytaniu)

Wszystko, czego użytkownik nie rozstrzygał, a co przyjęliśmy:

- *Detect calls* domyślnie włączony; *Start recording automatically* domyślnie wyłączony.
- Link rozpoznajemy po wzorcach (Teams, Meet, Zoom, Webex) w URL/lokalizacji/treści; nie
  wymagamy, żeby aplikacja z linku zgadzała się z aplikacją na mikrofonie.
- Okno oferty z kalendarza: `start − 1 min` … `start + 10 min`, nastawne.
- „Not a meeting" wycisza ofertę na sesję mikrofonu / to samo wydarzenie.
- Zbieg A+B dobiera wydarzenie automatycznie; ad hoc poza tym zbiegiem nie zgaduje wydarzenia.
- „Śledzona" aplikacja końca = ta, która trzymała mikrofon w trakcie nagrania.
- Tryb końca domyślnie „Ask me"; „Continue" wycisza na ~10 min.
- `SilenceCondition` 600 s zostaje jako twardy bezpiecznik; pytanie po ~3 min ciszy.
- Kolejność tytułów: ręczny > kalendarz > auto > notatka; powiązanie po fakcie przykrywa
  autotytuł bez kasowania go.
- Uczestnicy: migawka i pokazanie; nie trafiają do promptów w 1.6.
- Wyłącznie pigułka, bez powiadomień systemowych.
- Nowa biblioteka `MeetNotesMeetings` z własnymi testami.
- Zbiór pól i progów (`T_start`, `T_release`, `T_silence`, 8 h dla bloku wielogodzinnego) to
  szkice do rozstrzygnięcia przez spike.

## 8. Do rozstrzygnięcia przez użytkownika

1. ~~Auto-start~~ — **rozstrzygnięte 2026-10-16:** tylko przy Teams, nigdy na samym kalendarzu.
2. ~~Aplikacja w tle~~ — **rozstrzygnięte 2026-10-16:** ikona na pasku menu, uruchamianie przy
   logowaniu opcjonalne (§4.8).

Brak otwartych pytań do użytkownika; zostają wyłącznie pomiary ze spike'a (§5).

## 9. Ryzyka

- Lista procesów audio może okazać się niewystarczająca (np. Teams przez przeglądarkę, procesy
  pomocnicze); wtedy zakres ad hoc się zawęża do tego, co da się wykryć precyzyjnie — nie
  rozszerzamy przez heurystyki, które zwiększają liczbę fałszywych startów.
- Exchange OOO bywa reprezentowany niespójnie; reguła §4.3 wymaga potwierdzenia na prawdziwych
  danych, nie na podręczniku.
- Zależność od `LSMinimumSystemVersion 27.0` vs `.macOS(15.0)` (BACKLOG, faza 2) — nie
  poszerzamy rozjazdu: używamy tylko API dostępnych dla 15.0, a gdzie nowszych — z dopiskiem.

## 10. Co po 1.6

Google Calendar / Outlook / Slack (wiersze już są w UI), rozszerzanie listy aplikacji rozmów,
„Coming up" i oś spotkań (nieprzypisane w ROADMAP), uczestnicy jako wejście dla tożsamości
mówcy (po diaryzacji).
