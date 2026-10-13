# BACKLOG — kosmetyki i drobiazgi (bez rundy poprawek)

Zasada (decyzja użytkownika, 2026-10-12): uwagi kosmetyczne (komentarze, notki, nazwy, styl testów)
trafiają tutaj i czekają; rundy poprawek dotyczą wyłącznie błędów funkcjonalnych i brakujących
testów na bramkach. **Przed S18 jedna sesja K czyści ten plik.**

## Otwarte
- [ ] `scripts/test.sh` nie pokrywa skryptów składania (`bundle.sh`/`run.sh`/`Info.plist`) — bramka podpisu była ręczna i jednorazowa; rozważyć w S16/S18. *(check S14 #3)*
  - **Do decyzji przy S18 / faza 2** — pokrycie wymaga podpisu certyfikatem z pęku kluczy i składania paczki — poza `swift test`; decyzja, czy i jak (np. ad-hoc `MEETNOTES_SIGN_IDENTITY=-` + `plutil -lint`), należy do S18.
- [ ] D3/Info.plist: process tap (dźwięk systemowy) a klucze TCC — plan D3 krok 1 oczekuje panelu „Nagrywanie ekranu i dźwięku systemowego", a w plist nie ma `NSScreenCaptureUsageDescription`; sprawdzić przy D3, ewentualna poprawka plist wróci do D1. *(check S14 #7)*
  - **Do decyzji przy S18 / faza 2** — zależy od wyniku kroku 1 planu D3 na sprzęcie (który panel TCC się pokaże); zmiana plist bez tego pomiaru byłaby zgadywaniem.
- [ ] `Package.swift` `.macOS(15.0)` vs `Info.plist` `LSMinimumSystemVersion 27.0` — rozjazd tolerowany, ale niezweryfikowany. *(check S14 #8)*
  - **Do decyzji przy S18 / faza 2** — wymaga decyzji produktowej (minimalna wersja systemu) i weryfikacji na starszym macOS — nie da się tego sprawdzić na tej maszynie.
- [ ] `MeetNotesApp` nie ma targetu testowego (executable) — logika aplikacji (blokady, `preset.json`, `latestRun`, odtwarzanie) niemieszczalna w testach bez zmiany struktury (biblioteka + testTarget); rozważyć jako zadanie fazy 2 / przy S18. *(check S15 #7)*
  - **Do decyzji przy S18 / faza 2** — zmiana struktury pakietu (biblioteka + testTarget) i bramki liczby testów — poza zakresem sesji czyszczącej.
- [ ] `AppModel.reloadSessions()` parsuje journale/transkrypty na MainActorze (init, startRecording, koniec przebiegu) — zawieszenie UI przy pełnym archiwum; `SettingsView.onChange` zapisuje wszystkie pliki przy każdym znaku. *(check S15 #10)*
  - **Do decyzji przy S18 / faza 2** — przeniesienie parsowania poza MainActor i debounce zapisu ustawień to zmiana zachowania aplikacji, nie kosmetyka; przy obecnej liczbie sesji niewidoczne.

## Zapisane (dla kroniki)
- 2026-10-12 — `RunError.inputMismatch`: komentarz + „progi przesłuchu" → `0dd84ef`.
- 2026-10-12 — test przesłuchu: zakres z sekund + `#expect(mic.count >= …)` → `0dd84ef`.
- 2026-10-13 — S16: `scripts/test.sh` — usunięte zbędne `rm -f "$OUT"` (sprząta `trap`); wzorzec zacieśniony do prefiksów z `Tests/` (`mn-((fit|session|tr)-)?<UUID>`), komentarz opisuje, że `mn-corpus-<UUID>` nie pasuje.
- 2026-10-13 — S16: CLI `transcribe` — błędy użycia (zły katalog sesji, `--language`, `--shape`/`--run`) przed budową klienta; brak `journal.jsonl` → „to nie katalog sesji", kod 64.
- 2026-10-13 — S16: CLI `client()` (models/probe/transcribe) — baseURL bez `http://`/`https://` albo bez hosta → „zły adres … podaj pełny adres", kod 64.
- 2026-10-13 — S16: CLI `transcribe` — postęp `NN% (okna d/N)` od startu pętli (licznik widoczny przed pierwszym oknem), `fflush`.
- 2026-10-13 — S16: CLI `probe` — `--language` bez wartości → kod 64 (wspólny helper `CLI.value`, używany też przez `transcribe`).
- 2026-10-13 — S16: CLI `session-from-file` — istniejący `journal.jsonl` sprawdzany przed czytaniem audio; komunikat z podpowiedzią „świeży katalog na każdy plik korpusu" (nadal odmowa, kod 1).
- 2026-10-13 — S16: oś sesji vs offsety plików — notka w pomocy CLI („czas w pliku ścieżki = czas na osi − przesunięcie z summarize").
- 2026-10-13 — S16: `AppModel.startRecording` — zapis `preset.json` przez do-catch → `lastError` (nagranie trwa dalej).
