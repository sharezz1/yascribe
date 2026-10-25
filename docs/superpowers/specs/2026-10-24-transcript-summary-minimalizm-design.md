# Transcript i Summary: minimalizm (projekt)

Status: do zatwierdzenia. Makieta: https://claude.ai/artifact/AqP5EUBqoT6do7V8QChVnf (plansze „Dziś" i „A" dla obu zakładek; prywatna).
Zakres: zakładki **Transcript** i **Summary** w widoku spotkania. Presets i Templates (lista + okno jak w Dictionary) to osobny projekt, po tym.

## Po co

Po fazie 2.1 pasek nad transkryptem ma siedem elementów w jednej linii (wersja, „N parts kept as heard", „Corrected with …",
chip modelu, „Improve transcript", „Transcribe again…", „Copy"), a nad nim stos banerów. Chip modelu i „Improve transcript"
zajmują to samo miejsce, teksty się ucinają. Summary ma ten sam problem: wnęka z szablonem, kontekstem, chipem modelu,
„Regenerate" i Copy, a pod nią dwie linie informacyjne. Użytkownik chce mniej nakładających się opcji i informacji.

## Cele

- Jedna linia narzędzi na zakładkę. Stałe elementy: wybór wersji (Transcript) albo szablon i „Add context" (Summary), „Copy", menu `⋯`.
- Rzadkie akcje w `⋯`: Transcript — „Improve transcript again", „Correction model: <nazwa>…", „Transcribe again…"; Summary — „Summary model: <nazwa>…".
  Pozycje z wielokropkiem otwierają dotychczasowe popovery (dostawca, model, „Thinking"; język), a nie pod-menu: wybór modelu to kilka pól, nie lista.
  (Korekta po sprawdzeniu kodu: makieta pokazywała „›" jak pod-menu.)
- Wyjątki na wierzchu, bo to wtedy akcja główna: „Improve transcript" (wyróżniony) przed pierwszą korektą; „Regenerate" w Summary.
- Informacje o stanie (kto poprawił, ile części zostało „as heard", „Made with …", „Long meeting: condensed …") jako drobna notka w `⋯`.
- Stany przejściowe i błędy (korekta trwa, korekta padła, nowa transkrypcja nieukończona) jako **jedna linia** z jednym przyciskiem (Retry, Resume), bez osobnych bloków.
- Czytelne nazwy modeli w Transcript i Summary zamiast `id` dostawcy.

## Poza zakresem

- Presets, Templates, Settings, chipy poza tymi dwiema zakładkami. Tam nazwy modeli zostają jak dziś, do osobnej decyzji.
- Zmiana zachowania: bramki, ponawianie, wznawianie, wybór modelu w spotkaniu (`modelOverrides`), `RunSnapshot`.
- Ciemny motyw i wąskie okno nie były na makiecie; implementacja trzyma tokeny z `DesignSystem.swift`, ale wygląd wymaga odbioru.

## Antycele

- Funkcja schowana tak, że użytkownik jej nie znajdzie (np. zmiana modelu). Po zmianie: każda akcja z dzisiejszego paska jest osiągalna w co najwyżej dwóch kliknięciach.
- Utrata informacji: nic z dzisiejszych komunikatów nie znika, tylko zmienia miejsce.
- Nowe pola w zapisywanych typach inne niż opcjonalne (zasada z CLAUDE.md).

## Podejścia

Układ: (A) jedna linia + menu `⋯` — wybrane po obejrzeniu makiety; (B) zostawić wszystko na wierzchu, ale w dwóch rzędach —
nie rozwiązuje problemu nakładania; (C) panel boczny z akcjami — większa zmiana i odejście od Dictionary/Granoli. Wybrane A.

Nazwy modeli: (1) obcięcie przedrostka dostawcy; (2) nazwa z odpowiedzi `/models` dostawcy, z cofnięciem do (1); (3) własna tabela w aplikacji.
Wybrane **2**.

## Ustalenia

- `ModelInfo` (`MeetNotesProviders/OpenAICompatibleClient.swift`) dostaje opcjonalne pole `name`. Podręczna tabela `id → nazwa` per dostawca
  zapisuje się przy każdym pobraniu listy modeli. `RunSnapshot` zostaje bez zmian (trzyma sam `id`), więc stare nagrania też dostają ładną nazwę, jeśli tabela ją zna.
- Nazwa do wyświetlenia: `name` bez przedrostka „Dostawca: " (OpenRouter zwraca np. „DeepSeek: V4.1 Flash"); gdy tabela nie zna `id` (offline, model lokalny, stary wpis) — `id` bez części przed `/`.
  Pełne `id` zostaje w podpowiedzi (`.help`) i w pickerze modeli, gdzie wybór musi być jednoznaczny.
- Kod do zmiany: `TranscriptTab` i `SummaryTab` w `Sources/MeetNotesApp/MeetingTabs.swift`, `MeetingModelChip.swift` (model przeniesiony do `⋯`, w Transcript i w Summary), `TranscribeAgainButton.swift` (pozycja menu zamiast przycisku).

## Zostawione wykonawcy (jego decyzja)

- Dokładny kształt menu `⋯` w SwiftUI (`Menu` z pod-menu dla modelu) i skróty.
- Gdzie dokładnie leży tabela nazw na dysku (obok `providers.json` albo w katalogu cache).
- Zachowanie `⋯` przy wyłączonych akcjach (np. w trakcie przenoszenia nagrań, `moving`) — dziś te same warunki `.disabled`.
- Testy: migawki (`Snapshots.swift`) dla stanów z makiety; test czystej funkcji „id + tabela → nazwa".

## Do potwierdzenia przy odbiorze

- Czy dwa kliknięcia do zmiany modelu nie przeszkadzają.
- Czy „Transcribe again…" nie powinno wrócić na wierzch (jeśli używane często).
- Ciemny motyw i wąskie okno.
