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
| `docs/superpowers/specs/` | specyfikacje: rdzeń nagrywania, warstwa dostawców, faza 1.5, 1.6, 2.0 |
| `docs/superpowers/plans/` | plany faz (zadania z gotowym kodem) i runbook fazy 1 |
| `docs/superpowers/reports/` | raporty sesji, przeglądy, recenzje planów |
| `docs/superpowers/spikes/` | pomiary na sprzęcie (sondy, transkrypcja na żywo, odbiór D3) |
| `docs/superpowers/BACKLOG.md` | rzeczy odłożone, z adnotacją dokąd idą |
| `docs/superpowers/ROADMAP.md` | co w 1.5b, fazie 2, 3 i bez przydziału — ze źródłami |

Kod: `Sources/MeetNotesRecording` (rdzeń audio), `MeetNotesSessionFormat` (dziennik, CAF),
`MeetNotesProviders` (klient OpenAI-compatible, presety, sondy, pęk kluczy; od 2.0 także budżet kontekstu `ContextBudget`/`ContextProbe`,
limity czatu `ChatLimits`, `ThinkingStripper`, `finish_reason`, lokalność `isLocal`),
`MeetNotesLocalASR` (od 2.0a; **jedyny moduł importujący FluidAudio**: magazyn modelu Parakeet, klient lokalnego ASR, bramka wznowienia, karta modelu),
`MeetNotesTranscription` (bramka, pakowanie okien, wznawianie), `MeetNotesApp` (SwiftUI),
`MeetNotesNotes` (notatki, szablony, korekta, retencja i przenoszenie nagrań; od 2.0b map-reduce dla podsumowania i `TranscriptSplitter`), `MeetNotesMeetings` (kalendarz, wykrywanie spotkań, Coming up), `meetnotes-cli` (narzędzie deweloperskie; `transcribe … local://fluidaudio`).

## Stan

Faza 1 zamknięta 2026-10-13 (`master`).
**Faza 1.5** („Notatka i wygląd": 1.5a, 1.5b „Wyciszanie torów", 1.6 „Kalendarz i wykrywanie spotkań", Coming up)
**scalona do `master` 2026-10-19** (`--no-ff`, tag `faza-1.5` na commicie scalenia; wcześniejsze tagi: `faza-1.5a` → `b4f5804`,
`faza-1.6` → `49c4980`, `faza-1.5b-wyciszanie`), 355/355. Przegląd całości: `docs/superpowers/reports/F15-przeglad-calosci.md`
(poprawki P1, P2, P4: `docs/superpowers/reports/F15-poprawki-P1-P2-P4.md`).
Spec i plany: `docs/superpowers/specs/2026-10-14-faza15-design.md`, `docs/superpowers/plans/2026-10-14-faza15-*.md`
(przydział modeli Haiku/Sonnet/Opus w pliku 00); 1.6: `docs/superpowers/specs/2026-10-16-faza16-kalendarz-design.md`,
`docs/superpowers/plans/2026-10-16-faza16-kalendarz.md`.
Raporty: 1.5a `docs/superpowers/reports/F15-T13-czesc-B.md`; 1.5b `docs/superpowers/reports/F15b-wyciszanie.md`;
1.6 `docs/superpowers/reports/F16-odbior.md`, `docs/superpowers/reports/F16-przeglad.md`.
**Niezamknięta:** poczekalnia Teams (spec §6 pkt 2) niezmierzona i bez decyzji; lekarz/urodziny/OOO tylko z testów;
pomiar T11 (Auto, para PL+EN) czeka na nagranie użytkownika.

**Faza 2.0 „Lokalne modele"** — na gałęzi `faza20` (stan na `e36b8bd`), **nie scalona do `master`, bez tagu**; scalenie to wyłącznie decyzja użytkownika.
Decyzje fazy podjął Opus z delegacji użytkownika (noc 2026-10-20): `docs/superpowers/reports/F20-decyzje-opusa.md` (w tym lista „Do potwierdzenia rano").
- **2.0a — lokalny ASR** (Parakeet TDT v3 w procesie przez FluidAudio, pin `exact: "0.17.7"`, `.v3`/`.int8`): kod T2–T7 jest na gałęzi
  (`ProviderKind.fluidAudio`, `MeetNotesLocalASR`, odmowa bez modelu i bez cichego fallbacku do API, karta modelu w Settings).
  Model pobiera wyłącznie użytkownik przyciskiem; ładowanie tylko `AsrModels.loadLocal`.
- **2.0b — lokalny model tekstowy** przez Ollamę, llama.cpp albo oMLX (zwykły `Provider` na loopbacku): kod T10–T13 jest na gałęzi
  (`finish_reason: "length"` = błąd, `reasoning_effort: "none"` tylko dla lokalnych, limity czatu, budżet kontekstu z polem „Context window",
  numeracja partii korekty 1…N, map-reduce dla podsumowania). Aplikacja nie rekomenduje modeli.
- **Niezamknięte w 2.0:** S1 (jakość Parakeet vs `mai-transcribe-2`; T1) — brak raportu w `docs/superpowers/spikes/`; odbiór 2.0a na sprzęcie (T8:
  sieć off, pierwsze „Download", nagranie na żywo) — brak raportu; odbiór 2.0b i przegląd całości (T14, STOP) — niewykonane; oMLX niezmierzony (HTTP 507);
  baseline API niezmierzony (wymaga klucza użytkownika). Stan zadań wg commitów (`git log faza15..faza20`), nie wg pól `- [ ]` w planie.
- Spec: `docs/superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md` (§13 decyzje po S0, §14 po S2); plan: `docs/superpowers/plans/2026-10-20-faza20-lokalne-modele.md`.
  Recenzje: `docs/superpowers/reports/F20-recenzja-design.md`, `docs/superpowers/reports/F20-recenzja-planu.md`; przeglądy Opusa po T4, T10 i T13 zostały
  tylko w komunikatach commitów `6b32807`, `a95096e`, `4ff727b` (brak osobnych raportów). Spiki: `docs/superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md` (S0, GO),
  `docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md` (S2, commit `38ac47f`); pliku S1 nie ma.

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
- SwiftPM: `swift package --disable-keychain resolve` po zmianie `Package.swift` lub `rm -rf .build` — bez flagi pobranie `binaryTarget` FluidAudio wisi na pęku kluczy.
  `scripts/test.sh`, `bundle.sh` i `snapshot.sh` same przekazują flagę (wyłącza tylko odczyt poświadczeń SwiftPM z pęku, niczego w nim nie zmienia).
- Lokalny ASR w buildzie DEBUG: `MEETNOTES_MODEL_STORE` wskazuje kopię magazynu modelu (np. `.devdata/model-store`) zamiast wspólnego
  `~/Library/Application Support/FluidAudio/Models`, który należy do użytkownika i innych aplikacji — nie zapisuj do niego i nie kasuj z niego.
