# Faza 1.6 — odbiór na żywo (1ddd08e)

Odbiór robi użytkownik na sprzęcie: ✅/❌ + uwaga. Rozbieżności ze specem: STOP, bez ślepych napraw.

## T11 — pasek menu i okno (2026-10-19)

| # | Punkt | Wynik | Uwaga |
|---|---|---|---|
| 1–3 | Ikona w pasku, menu (stan, Open, Quit + podpis); zamknięcie okna nie kończy aplikacji; Open wraca z oknem; brak dwóch okien przy starcie; „Open note" nie łapie okna paska | ✅ | „działa" |

## T10 — wykrywanie (do sprawdzenia na spotkaniu)

| # | Punkt | Wynik | Uwaga |
|---|---|---|---|
| 3a | Oferta z kalendarza minutę przed spotkaniem („The real InPost daily”, źródło Calendar, Start / Not a meeting) | ✅ | pojawiła się ≈60 s przed startem (offerLead), zrzut od użytkownika 2026-10-19 |
| 4 | Teams + mikrofon ≈12 s → pigułka „Call in Teams" (Start / Not a meeting) | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 5 | Start, rozłączenie ≈20 s → „Meeting ended?" (Stop / Continue) | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 6 | Auto-start, Stop przy trwającej rozmowie, zmiana „Start after" → nagranie nie rusza od nowa | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 7 | Oferta przy zamkniętym oknie (App Nap, tryb `.common`) | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 8 | Zmiana wyboru kalendarzy działa od razu | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 9 | Tekst stanu w menu przy wyłączonym Detect calls / kalendarzu | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 10 | Quit w trakcie nagrywania: pytanie, Stop and Quit, brak „Recovered" | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |
| 11 | Preset bez języka + auto-start → oferta zostaje jako ręczna | ✅ | użytkownik: „wszystko działa", bez szczegółów per punkt (2026-10-19) |

## Menu Preset w ofercie (5e07211, 99df124)

| Punkt | Wynik | Uwaga |
|---|---|---|
| Menu Preset w pigułce-ofercie otwiera się i zmienia preset | ✅ | 2026-10-19 |
| Przeciąganie pigułki po użyciu menu | ❌ → ✅ | Po użyciu menu pigułka nie dawała się przesunąć (okno kluczowe, pozycja bez zmian). Poprawka 99df124: po `NSMenu.didEndTrackingNotification` w trybie oferty zmiana `.id` treści. Użytkownik: „działa". Przyczyna to hipoteza z objawów. |
