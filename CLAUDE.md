# MeetNotes

Natywna aplikacja macOS do notatek ze spotkań: nagrywa dwa kanały (dźwięk systemowy przez
process tap Core Audio + mikrofon), transkrybuje przez API (OpenRouter, `microsoft/mai-transcribe-2`)
i robi notatkę modelem z presetu. Jeden użytkownik, repo prywatne. Interfejs aplikacji po
angielsku, dokumenty w repo po polsku.

## Gdzie co jest

| Ścieżka | Zawartość |
|---|---|
| `docs/wymagania.md` | wymagania (W§) — m.in. język jawny domyślnie, „Auto" tylko awaryjnie |
| `docs/design/macos.md` | referencja platformy, świadome odstępstwa od HIG |
| `docs/design/inspiracje/` | Granola, Wispr Flow, Meetily — zrzuty i co przenosimy |
| `docs/superpowers/specs/` | specyfikacje: rdzeń nagrywania, warstwa dostawców, faza 1.5 |
| `docs/superpowers/plans/` | plany faz (zadania z gotowym kodem) i runbook fazy 1 |
| `docs/superpowers/reports/` | raporty sesji, przeglądy, recenzje planów |
| `docs/superpowers/spikes/` | pomiary na sprzęcie (sondy, transkrypcja na żywo, odbiór D3) |
| `docs/superpowers/BACKLOG.md` | rzeczy odłożone, z adnotacją dokąd idą |

Kod: `Sources/MeetNotesRecording` (rdzeń audio), `MeetNotesSessionFormat` (dziennik, CAF),
`MeetNotesProviders` (klient OpenAI-compatible, presety, sondy, pęk kluczy),
`MeetNotesTranscription` (bramka, pakowanie okien, wznawianie), `MeetNotesApp` (SwiftUI),
`meetnotes-cli` (narzędzie deweloperskie).

## Stan

Faza 1 zamknięta 2026-10-13 (`master`). Faza 1.5 „Notatka i wygląd" na gałęzi `faza15`:
spec `docs/superpowers/specs/2026-10-14-faza15-design.md`, plan
`docs/superpowers/plans/2026-10-14-faza15-*.md` (przydział modeli Haiku/Sonnet/Opus w pliku 00).

## Twarde zasady

- **Toolchain:** Swift 6.4, tylko Command Line Tools, bez Xcode. XCTest niedostępny — `swift-testing`.
- **Testy wyłącznie `scripts/test.sh`**, nigdy goły `swift test` (ładuje plugin makr i porównuje
  liczbę uruchomionych testów z deklaracjami `@Test`; kod 3 = usterka pluginu, 4 = rozjazd liczby).
- **SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`** (brak pluginu SwiftUIMacros w CLT).
  Stan lokalny: `ObservableObject` + `@StateObject`. `@Observable` działa.
- **Nowe pola w zapisywanych typach (`Preset`, `RunSnapshot`…) tylko opcjonalne** — wymagane pole
  psuje stare `input.json` (lekcja E6).
- **Nigdy `git add -A` ani `git add .`** — jawne ścieżki. Hook pre-commit (`core.hooksPath scripts/hooks`)
  sprawdza hashe cytowane w raportach.
- **Mutacja każdej bramki:** wprowadź → test ma paść → `git checkout <plik>`.
- **Klucze API wpisuje tylko użytkownik** (w aplikacji albo `read -s` w swoim terminalu). Nie wpisuj,
  nie loguj, nie commituj kluczy; literały testowe nie mogą wyglądać jak klucz (`test-fake-…`).
- Nie zmieniaj Ustawień systemowych, uprawnień TCC ani pęku kluczy — to robi użytkownik.
- Decyzje projektowe i bramki (STOP) należą do użytkownika; wykonawca nie naprawia „na ślepo".

## Uruchamianie

- `scripts/run.sh` — buduje i uruchamia aplikację z danymi w `.devdata/`.
- `scripts/bundle.sh` — składa `.build/MeetNotes.app`, podpis „MeetNotes Dev" (samopodpisany
  certyfikat w pęku login; stały podpis = macOS pamięta zgody na mikrofon i dźwięk systemowy).
- CLI: `B=$(swift build --show-bin-path)/meetnotes-cli`, potem `$B --help`.
- Ostrzeżenia linkera o brakujących search path przy buildzie to szum, nie błąd.
