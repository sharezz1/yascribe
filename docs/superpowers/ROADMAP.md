# ROADMAP — co dalej po fazie 1.5a

> Zebrane 2026-10-16 z dokumentów źródłowych; **przydział do fazy jest tylko tam, gdzie zapadła
> decyzja** (źródło w nawiasie). Pozycje bez decyzji są w sekcji „Nieprzypisane” — fazę wybiera
> użytkownik przy planowaniu. Przy sprzeczności wygrywa dokument źródłowy, nie ten plik.

## Gdzie jesteśmy

- **Faza 1** — zamknięta 2026-10-13 (`master`).
- **Faza 1.5a** — zamknięta 2026-10-16, tag `faza-1.5a` → `b4f5804`, gałąź `faza15` na GitHubie:
  język wizualny B ([macos.md §11](../design/macos.md)), trzy odbiory na żywo, ElevenLabs
  bezpośrednio, szablony z sekcjami, Recordings z retencją audio
  ([raport F15-T13 część B](reports/F15-T13-czesc-B.md)).

## Faza 1.5b (w toku)

| Pozycja | Źródło |
|---|---|
| **Wyciszanie torów w pigułce** (cisza zamiast przerwy, „Muted”, okresy w dzienniku, zakaz wyciszenia obu) — sesja w toku | [macos.md §11.5](../design/macos.md) |
| Zdarzenie w dzienniku przy pierwszym dźwięku po `allZeros60s` (trwałe odróżnienie ciszy na początku od braku uprawnień) — razem z wyciszaniem | decyzja (b), [F15-T13 część B](reports/F15-T13-czesc-B.md) |
| **Pomiar języka Auto i pary PL+EN (T11)** — czeka na nagranie mieszane i klucz w terminalu użytkownika; wynik decyduje o fazie 2 | [spec 1.5 §9 pkt 11, decyzja 8](specs/2026-10-14-faza15-design.md), [F15-T13 uwagi, C](reports/F15-T13-uwagi-uzytkownika.md) |
| Przegląd całości przez Opusa, potem scalenie `faza15` → `master` | [spec 1.5 §9 pkt 13](specs/2026-10-14-faza15-design.md) |
| Drobne z przeglądów T5/T6/T10 (tytuły z `\r`, `MarkdownBlocks` dla tabel, `latestRunID`, wyścig `updateMeta`, `AutoTitle.clean`, `ContextError`, wygaszanie poziomów…) — bez rundy poprawek, do sesji porządkowej | [BACKLOG](BACKLOG.md) |

**Równolegle, poza fazami:** nazwa (**Yascribe**), logo i ikona aplikacji — sesja designu w toku;
podpięcie ikony do paczki (`scripts/bundle.sh`, `Info.plist`) i ewentualna zmiana nazwy to
osobny krok po decyzji.

## Faza 1.6 „Kalendarz i wykrywanie spotkań" (decyzja użytkownika 2026-10-16, przed fazą 2)

Spec do przeglądu: [faza16-kalendarz](specs/2026-10-16-faza16-kalendarz-design.md) — Apple Calendar
jako opcja w Settings, pigułka przy starcie spotkania (kalendarz i rozmowa ad hoc w Teams), auto-start
jako przełącznik, wykrywanie końca przez aplikację (nie kalendarz), tytuł z wydarzenia, ręczne
powiązanie wydarzenia z notatką. Google Calendar / Outlook / Slack: tylko wyszarzone wiersze „Coming soon".
Wymaga spike'a na sprzęcie (lista procesów audio, Teams, OOO w Exchange) przed planem.

## Faza 2 (decyzje już zapadły)

| Pozycja | Źródło |
|---|---|
| Transkrypt na żywo w trakcie spotkania | [spec 1.5 decyzja 1](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md), [wymagania 🆕](../wymagania.md) |
| „Resume” — wznowienie nagrania do tej samej notatki (wiele segmentów sesji) | [spec 1.5 decyzja 1](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md) |
| Wybór mikrofonu przed startem (rdzeń: źródło + dziennik + obserwator urządzeń) | [spec 1.5 decyzja 4](specs/2026-10-14-faza15-design.md), [BACKLOG](BACKLOG.md) |
| Długie transkrypty: dzielenie na części (map-reduce) dla korekty i notatki | [spec 1.5 decyzja 20, §10](specs/2026-10-14-faza15-design.md) |
| Odzyskiwanie odmówionej zgody TCC (instrukcja + „Reset permission”) i klucze TCC w `Info.plist` | [BACKLOG](BACKLOG.md), aneks S18 |
| Target testowy aplikacji (`MeetNotesApp` jako biblioteka + testTarget) | [BACKLOG](BACKLOG.md), aneks S18 |
| `reloadSessions()` poza MainActorem, debounce zapisu ustawień | [BACKLOG](BACKLOG.md), aneks S18 |
| Minimalna wersja macOS (`.macOS(15.0)` vs `LSMinimumSystemVersion 27.0`) | [BACKLOG](BACKLOG.md), aneks S18 |
| Oś i czas trwania nagrań bez dźwięku systemowego („0 min”) | [BACKLOG](BACKLOG.md), [spec 1.5 §10](specs/2026-10-14-faza15-design.md) |
| AEC offline (echo głośników w mikrofonie; w 1.5 jest filtr tekstowy) | [F15-T13 uwagi, A #2](reports/F15-T13-uwagi-uzytkownika.md) |
| Decyzja o „Auto” / parze języków na podstawie pomiaru T11 | [spec 1.5 decyzja 8](specs/2026-10-14-faza15-design.md) |

## Faza 3 (decyzja już zapadła)

| Pozycja | Źródło |
|---|---|
| Wyszukiwanie w archiwum (embedding, indeksowanie; model wybierany już dziś w Settings) | [spec 1.5 §10](specs/2026-10-14-faza15-design.md) |

## Nieprzypisane (z wymagań — fazę wybiera użytkownik)

| Pozycja | Źródło |
|---|---|
| Lokalny ASR w procesie (FluidAudio, Parakeet v3 już na dysku; Cohere Transcribe lokalnie) | [wymagania §0, §2](../wymagania.md) |
| Diaryzacja lokalna z nastawialnym progiem, edycja rozmówców, automatyczne nazwiska; tożsamość mówcy aż do zadań | [wymagania §4, §5](../wymagania.md) |
| Słownik i word boosting (format aliasów = `replacements.tsv`), klik na słowo → poprawka → alias (zakładka Dictionary) | [wymagania §3](../wymagania.md), [macos.md §9](../design/macos.md) |
| Kalendarz Apple: „Coming up” / oś nadchodzących spotkań (sam EventKit i wykrywanie → faza 1.6; koniec sesji z kalendarza **uchylony**) | [wymagania §5](../wymagania.md), [spec 1.6](specs/2026-10-16-faza16-kalendarz-design.md) |
| Chat nad spotkaniem i nad archiwum (RAG, „Ask anything”) | [wymagania §4](../wymagania.md), [spec 1.5 §2](specs/2026-10-14-faza15-design.md) |
| Zakładka zadań (zależna od tożsamości mówcy) | [wymagania §4](../wymagania.md) |
| Dyktowanie na żywo (osobny tryb) | [wymagania §1](../wymagania.md) |
| MCP dla Claude, eksport notatek do plików markdown | [wymagania §6](../wymagania.md) |
| Kompresja audio do Opusa po sesji (wznawialny krok) | [spec rdzenia nagrywania](specs/2026-09-24-rdzen-nagrywania-design.md) |
| Punkty notatki z odnośnikami do miejsca w transkrypcie (widoczne źródło) | [macos.md §11.8](../design/macos.md) |
| Historia wersji notatek w UI, wyszukiwarka w widoku transkryptu | [spec 1.5 §2](specs/2026-10-14-faza15-design.md) |
| Odsłuch zmiksowany (po wyrównaniu, oryginały zostają); nagrywanie ekranu (rekomendacja: nie w v1) | [wymagania §7](../wymagania.md) |
