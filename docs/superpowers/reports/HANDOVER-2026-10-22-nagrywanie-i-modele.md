# Przekazanie sesji 2026-10-22: nagrywanie (pigułka, urządzenia) i zmiana modelu w widoku spotkania

Dla nowej sesji. Najpierw `CLAUDE.md` (twarde zasady) i pamięć projektu; ten plik mówi, co jest otwarte i gdzie to leży w kodzie.
Dokumenty po polsku, interfejs aplikacji po angielsku. Zmiany do `master` tylko przez PR (`gh pr merge --merge`, nie squash), scalenie wyłącznie na wyraźne „scal".

## Stan na koniec sesji

- `master` = `00e45b9` (po PR #1–#15), 581/581 (`scripts/test.sh`). Faza 2.0 scalona (tag `faza-2.0` → `7eebaea`).
- PR #15 scalony: wpis w `BACKLOG.md` o torze `system` na słuchawkach Bluetooth + ten plik. Brak otwartych PR.
- Artefakt „Mapa faz Yascribe": https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz (wersja 20). Każda zmiana w BACKLOG/ROADMAP/postępie ma go aktualizować: `Artifact read`, edycja, publikacja pod tym samym `url`.
- Aplikacja uruchomiona z `scripts/run.sh` (build z `master`); dane w `.devdata/`. Nie zamykaj jej (zamyka użytkownik); `run.sh` odmówi, gdy działa.
- **Nie wchodź shellem do katalogów sesji w `.devdata/sessions/…`** (hooki tworzą tam `.claude-flow/`, `.swarm/`). Czytaj je przez ścieżki bezwzględne (`Read`, `python3 -I` z pełną ścieżką).

## Zadanie 1: pigułka nagrywania pokazuje, co nagrywa

**Problem (potwierdzony przez użytkownika).** Spotkanie z 2026-10-22 na słuchawkach Bluetooth (Sound Blaster JAM V2, UID `00-02-3C-8D-E0-50`) przy Teams ustawionym na MacBooka: aplikacja nagrywa **domyślne** urządzenia macOS, nie te, których używa spotkanie. Pigułka pokazała mikrofon słuchawek, a Teams miał MacBooka. Tor `system` przez 139,5 s nie dostał klatki (`stalled30s` w 30,1 s), a pigułka **nic nie pokazała**. Wispr Flow ma kilkanaście tekstów z początku rozmowy, których Yascribe nie ma.

**Dowody (sesje w `.devdata/sessions/`):**
- `2026-10-22T06-45-33Z-ec0b` ([spotkanie dzienne], słuchawki): `system` 352 s audio na 1025 s nagrania, stosunek zegara do pliku stały 3,0, efektywnie 16,5 kHz przy deklarowanych 48 kHz; „Them" = 6 słów szumu. Hipoteza (bez odsłuchu): tryb HFP 16 kHz, a format tapa czytany raz przy starcie (`SystemTapSource.swift:77`, `:92`).
- `2026-10-22T07-31-04Z-82c4` (test poczekalni): słuchawki → w 139,5 s `device.changed` na `BuiltInMicrophoneDevice`/`BuiltInSpeakerDevice` (użytkownik wyłączył słuchawki), `track.recovered`; potem oba tory zdrowe (zegar 1,0), „Them" 3371 słów.
- `2026-10-21T21-39-48Z-49df`, `2026-10-13T10-17-30Z-e9f3`, `…10-24-20Z-b96d`: na wbudowanych urządzeniach tor `system` ma 0 klatek, gdy nic nie gra. **Cisza w poczekalni to więc zwykły stan, nie błąd**; alarm nie może straszyć.
- `2026-10-22T07-04-55Z-8307`: 4 s, pusty `system.caf` (68 B).

**Do zrobienia (decyzja użytkownika: zacząć od tego):**
1. Pigułka: wiersz „System audio" z **nazwą wyjścia** (jak dziś mikrofon: `RecordingController.swift:64`, `:71`, wiersze `:453`), a po 30 s bez klatek informacja „No system audio yet · <nazwa wyjścia>" (informacja, nie ostrzeżenie; brzmienie do uzgodnienia z użytkownikiem).
2. Stall dziś trafia tylko do dziennika: `SessionRecorder.swift:165–205` (`trackFailed`/`trackRecovered`, `stalledTracks`). Trzeba przekazać stan do `RecordingController` i pigułki; po `track.recovered` komunikat znika.
3. Test: stan „stall" i jego odwołanie; **mutacja każdej bramki** (wprowadź → test ma paść → `git checkout <plik>`). Tylko `scripts/test.sh`.
4. Wygląd: migawka (`scripts/snapshot.sh`) jak przy innych zmianach widoku.
5. Aktualizacja BACKLOG/ROADMAP/artefaktu po wdrożeniu. Gałąź np. `faza22-pill-system-audio`; commit z `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR z `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

**Poza tym zadaniem, bez decyzji (nie zaczynać bez użytkownika):**
- Pomiar na słuchawkach (słuchawki domyślne, dźwięk puszczony na głośnikach MacBooka, potem dziennik): potwierdza, że tap na nieaktywnym wyjściu nie dostaje klatek, i wyjaśnia stosunek 3,0. Ustawienia systemu zmienia użytkownik.
- Specyfikacja „wybór mikrofonu i wyjścia przed startem" (spec 1.5 decyzja 4; BACKLOG „PRIORYTET WYSOKI … Bluetooth"). Faza nieustalona (moja propozycja 2.3 to nie ustalenie).
- Poczekalnia Teams pozostaje nierozstrzygnięta: pierwsze 139 s sesji `82c4` tor był na złym urządzeniu. Powtórzyć z MacBookiem jako domyślnym od startu.

## Zadanie 2: zmiana modelu w widoku spotkania (podsumowanie i korekta)

**Prośba użytkownika (2026-10-22):** w zakładce **Summary** możliwość zmiany przypisanego modelu; w sekcji **Transcript** („Improve transcript", poprawianie transkrypcji) także opcjonalna zmiana przypisanego modelu. Presety zostają domyślnymi wartościami (rekomendacja przyjęta w rozmowie).

**Decyzje użytkownika:** zmiana **zapisuje się przy sesji** (nie jest jednorazowa). Faza nieznana, do ustalenia. Wpis w BACKLOG: „Funkcja (użytkownik, 2026-10-21): zmiana modelu dla podsumowania bezpośrednio w zakładce Summary".

**Co jest w kodzie:**
- `Preset` ma `asr`, `correction`, `summary` (`RoleAssignment`: `providerID`, `model`, `prompt`), `Sources/MeetNotesProviders/Preset.swift`. Nowe pola w zapisywanych typach **tylko opcjonalne**.
- Podsumowanie: `NotesModel.generate(item:useCorrected:template:context:)` (`NotesModel.swift:114`), przyciski w `MeetingTabs.swift`. `summary.json` ma już pole `model`; `notes/meta.json` trzyma m.in. wydarzenie z kalendarza.
- Korekta: `NotesModel.retryCorrection`, `canRetryCorrection` (`NotesModel.swift:62–74`), przycisk „Improve transcript" w `MeetingTabs.swift:175`. Korekta zawsze bez myślenia (`chat(thinking: false)`); podsumowanie ma `GlobalSettings.summaryThinking` (domyślnie włączone).
- Lista dostawców z czatem: tylko dostawcy z `Provider.supports(.chat)`-podobnym filtrem (Correction i Summary nie oferują ElevenLabs ani Yascribe; patrz poprawka P4 w `reports/F20-lista-poprawek.md`).

**Do rozstrzygnięcia w projekcie (najpierw krótka specyfikacja, potem plan):**
- Gdzie zapisać nadpisanie (w katalogu sesji, nowe pole opcjonalne), jak pokazać, że wynik powstał innym modelem niż w presecie.
- Czy przełącznik „Thinking" idzie razem z wyborem modelu przy podsumowaniu (rekomendacja: tak, ta sama droga).
- Sposób na powrót do modelu z presetu.
- Wpływ na plakietkę „Fully local" i migawkę uruchomienia (`RunSnapshot`) — nie psuć starych `input.json`.
- Powód zadania: porównywanie jakości (oMLX kontra API, myślenie włączone i wyłączone) bez wychodzenia do Settings.

## Pozostałe otwarte wątki (skrót)

- **oMLX:** pole „API key" jest (od `fb12fe2`), użytkownik się połączył; brak pomiaru z modelem mieszczącym się w pamięci (jedyny model MLX dawał HTTP 507). BACKLOG: nie da się wyczyścić zapisanego klucza oMLX (`replaceKey` przy pustym polu).
- **Faza 2.1 „Słownik"** (obowiązkowo, decyzja użytkownika): brak specyfikacji. **AEC offline** (priorytet wysoki): faza do wyboru. **Dokąd przenieść pierwotną fazę 2.0:** decyzja użytkownika (stara sekcja „Faza 2" w ROADMAP).
- Testy użytkownika: nagranie na żywo (kryterium 3.1), para PL+EN (T11, Auto), baseline API (tylko na polecenie), test odmowy bez modelu, więcej prób podsumowania z myśleniem i bez.
- Retencja audio B7: pierwsze audio zniknie ok. 2026-11-12.
- **Poza kodem:** unieważnić klucz OpenRouter, który wyciekł w wyjściu `pgrep`.
- Użytkownik nie życzy sobie zmian domyślnego ustawienia myślenia w podsumowaniu (zostaje włączone).
