# Faza 1.6 — odbiór na żywo (b15e841)

Odbiór robi użytkownik na sprzęcie: ✅/❌ + uwaga. Rozbieżności ze specem: STOP, bez ślepych napraw.

## T11 — pasek menu i okno (2026-10-19)

| # | Punkt | Wynik | Uwaga |
|---|---|---|---|
| 1–3 | Ikona w pasku, menu (stan, Open, Quit + podpis); zamknięcie okna nie kończy aplikacji; Open wraca z oknem; brak dwóch okien przy starcie; „Open note" nie łapie okna paska | ✅ | „działa" |

## T10 — wykrywanie (do sprawdzenia na spotkaniu)

| # | Punkt | Wynik | Uwaga |
|---|---|---|---|
| 3a | Oferta z kalendarza minutę przed spotkaniem („The real InPost daily”, źródło Calendar, Start / Not a meeting) | ✅ | pojawiła się ≈60 s przed startem (offerLead), zrzut od użytkownika 2026-10-19 |
| 4 | Teams + mikrofon ≈12 s → pigułka „Call in Teams" (Start / Not a meeting) | | |
| 5 | Start, rozłączenie ≈20 s → „Meeting ended?" (Stop / Continue) | | |
| 6 | Auto-start, Stop przy trwającej rozmowie, zmiana „Start after" → nagranie nie rusza od nowa | | |
| 7 | Oferta przy zamkniętym oknie (App Nap, tryb `.common`) | | |
| 8 | Zmiana wyboru kalendarzy działa od razu | | |
| 9 | Tekst stanu w menu przy wyłączonym Detect calls / kalendarzu | | |
| 10 | Quit w trakcie nagrywania: pytanie, Stop and Quit, brak „Recovered" | | |
| 11 | Preset bez języka + auto-start → oferta zostaje jako ręczna | | |
