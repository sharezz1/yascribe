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
limity czatu `ChatLimits`, `ThinkingStripper`, `finish_reason`, lokalność `isLocal`; `chat(thinking:)`, `Provider.supports(_:)`/`RoleProviders` — kto może obsłużyć rolę),
`MeetNotesLocalASR` (od 2.0a; **jedyny moduł importujący FluidAudio**: magazyn modelu Parakeet, klient lokalnego ASR, bramka wznowienia, karta modelu),
`MeetNotesTranscription` (bramka, pakowanie okien, wznawianie), `MeetNotesApp` (SwiftUI),
`MeetNotesNotes` (notatki, szablony, korekta, retencja i przenoszenie nagrań; od 2.0b map-reduce dla podsumowania i `TranscriptSplitter`; `FillerWords` — filtr przerywników), `MeetNotesMeetings` (kalendarz, wykrywanie spotkań, Coming up), `meetnotes-cli` (narzędzie deweloperskie; `transcribe … local://fluidaudio`).

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

**Faza 2.0 „Lokalne modele"** — **scalona do `master` 2026-10-20 przez PR #1** (commit scalenia `7eebaea`, `--merge`, nie squash; tag `faza-2.0` na nim),
pełny przebieg `scripts/test.sh`: **580/580** (po poprawkach P6–P10: **581/581**). **Cofnięcie:** `git revert -m 1 7eebaea` (albo „Revert" na stronie PR). Gałąź `faza20` zostaje na GitHubie.
Poprawki po odbiorach (P1–P5) są w tym samym PR; lista z dowodami i niezweryfikowanym: `docs/superpowers/reports/F20-lista-poprawek.md`.
Decyzje fazy podjął Opus z delegacji użytkownika (noc 2026-10-20): `docs/superpowers/reports/F20-decyzje-opusa.md` (w tym lista „Do potwierdzenia rano").
- **2.0a — lokalny ASR** (Parakeet TDT v3 w procesie przez FluidAudio, pin `exact: "0.17.7"`, `.v3`/`.int8`): kod T2–T7 jest na gałęzi
  (`ProviderKind.fluidAudio`, `MeetNotesLocalASR`, odmowa bez modelu i bez cichego fallbacku do API, karta modelu w Settings).
  Model pobiera wyłącznie użytkownik przyciskiem; ładowanie tylko `AsrModels.loadLocal`.
  **S1 wykonany** (`6f2da98`): kompletność 102,7 % słów FluidVoice, mediana 32 słów/wypowiedź, powtarzalność tekstu i czasów, 0 flag języka na PL,
  RTF ~0,006; wynik to pomiar bez progu go/no-go. **Odbiór T8 wykonany bez kroków użytkownika** (`cec0263`, `aca4260`): wszystko, co agent mógł zrobić, przeszło.
  Wykryta **U1** (słowa rozciągnięte przez wyciętą ciszę na sklejeniach okien) **naprawiona** w `11fb41d` (`Chunk.sourceSpan`: słowo przycinane do fragmentu,
  w którym się zaczyna; dotyczy też ścieżki API, zmienia czasy słów, nie tekst).
- **2.0b — lokalny model tekstowy** przez Ollamę, llama.cpp albo oMLX (zwykły `Provider` na loopbacku): kod T10–T13 jest na gałęzi
  (`finish_reason: "length"` = błąd, `reasoning_effort: "none"` tylko dla lokalnych, limity czatu, budżet kontekstu z polem „Context window",
  numeracja partii korekty 1…N, map-reduce dla podsumowania). Aplikacja nie rekomenduje modeli. **Odbiór sprzętowy T14 wykonany** (`a8ad702`):
  korekta, notatka jednym przebiegiem przy 16384, `reasoning_effort`, anulowanie, awarie serwera i wykrywanie kontekstu zaliczone; map-reduce 60 min przy 4096 i 8192
  kończy się jawnym błędem (notatka z 60 min powstaje dopiero przy kontekście serwera ≥ 16384 — end-to-end niezmierzone).
  **Znalezisko sprzętowe:** Ollama 0.40.6 z `bonsai-2` **obcina wejście po cichu** (HTTP 200, `finish_reason: "stop"`), gdy prompt jest dłuższy niż kontekst serwera,
  a pole „Context window" jest wyższe niż serwer i model nie jest załadowany (wykrycie `/api/ps` go nie obniży); nie do wykrycia także na oMLX. Spec §14 i `wymagania.md`
  mówiły inaczej (prawda tylko dla `genesys-ministral3`) — poprawione notą „korekta". **Obrona wdrożona (T14b, `606ee39`):** w `chat` dla dostawców lokalnych porównanie
  `usage.prompt_tokens` z długością promptu (prompt ≥ 4000 znaków i > 5,0 znaku na token → `ProviderError.inputTruncated`, jawny błąd zamiast notatki); działa też na oMLX.
- **Poprawki P1–P5 (2026-10-20, zgłoszone przez użytkownika)** — szczegóły i dowody w `F20-lista-poprawek.md`:
  - **P1** (`9602466`): korekta przez API dostawała „myślenie" modelu hybrydowego (`deepseek-v4.1-flash` milczał ponad 120 s, keep-alive odświeża `timeoutInterval`). Teraz `chat(thinking: false)`
    wysyła `reasoning: {"enabled": false}` (jedno ponowienie bez pola po 400/422 z „reasoning"/„think"); korekta i sonda korekty zawsze bez myślenia. Podsumowanie:
    `GlobalSettings.summaryThinking` (opcjonalne, domyślnie włączone), przełącznik w Settings → Summary → Thinking; lokalne serwery zawsze bez myślenia (`reasoning_effort: "none"`).
  - **P2** (`2765a9b`): przerywniki (yyy, mhm…) — lista idzie do polecenia korektora i do deterministycznego filtra po korekcie (`FillerWords`); Settings → Correction (przełącznik, edytowalna lista, Reset).
    Surowy transkrypt nietknięty; wypowiedź złożona tylko z przerywników zostaje.
  - **P3** (`148d9ea`): karta „Yascribe model" (Parakeet) na górze Settings z jednobarwnym znakiem Yascribe; Parakeet nie jest wierszem listy Providers (rekord `.fluidAudio` zostaje i jest dopisywany przy starcie,
    bo presety trzymają jego `providerID`); ikony llama.cpp i oMLX jednobarwne (źródła i odstępstwo w `docs/design/makiety/logo-dostawcow/ZRODLA.md`).
  - **P4** (`8736c68`, `849e25f`): Correction i Summary oferują tylko dostawców z czatem (bez ElevenLabs i Yascribe), „Yascribe" to etykieta w menu (rekord bez zmiany nazwy); preset, który już wskazuje
    nieobsługującego dostawcę, zachowuje go w menu.
  - **P5**: szerokość paska bocznego przy otwartym spotkaniu — nie odtworzono (pomiar na drugiej instancji i na prawdziwej aplikacji), użytkownik potwierdził „jest ok", bez zmiany w kodzie.
- **Niezamknięte w 2.0 (kroki użytkownika i klucze):** (zaliczone przez użytkownika 2026-10-22: usunięcie modelu, „Download" i lokalna transkrypcja presetem „Parakeet PL" w `.app`; stan Wi-Fi przy przebiegu nie jest zapisany w danych, korekta przez API poszła o 00:29 przy działającej sieci) nagranie na żywo
  dla kryterium 3.1 i para PL+EN (T11); oMLX (model mieszczący się w pamięci + własny klucz) niezmierzony; baseline API (klucz, koszt) niezmierzony. Po P1–P5 dochodzi: test jakości podsumowania z myśleniem i bez (jedna próba na wariant 2026-10-21, nierozstrzygająca — `F20-lista-poprawek.md`, na końcu; domyślnie nadal włączone),
  (żywe wywołanie OpenRoutera po P1 i wygląd sekcji Correction i Summary w Settings potwierdzone 2026-10-21; **priorytet wysoki:** echo głośników w mikrofonie — BACKLOG) (embedding w Archive search działa, potwierdzone 2026-10-21).
  Stan zadań wg commitów (`git log faza15..faza20`), nie wg pól `- [ ]` w planie.
- Spec: `docs/superpowers/specs/2026-10-19-faza20-lokalne-modele-design.md` (§13 decyzje po S0, §14 po S2, nota „korekta po T14" na końcu §14); plan: `docs/superpowers/plans/2026-10-20-faza20-lokalne-modele.md`.
  Recenzje: `docs/superpowers/reports/F20-recenzja-design.md`, `docs/superpowers/reports/F20-recenzja-planu.md`; przeglądy Opusa po T4, T10 i T13 zostały
  tylko w komunikatach commitów `6b32807`, `a95096e`, `4ff727b` (brak osobnych raportów).
  Spiki: `docs/superpowers/spikes/2026-10-20-f20-s0-fluidaudio.md` (S0, GO), `docs/superpowers/spikes/2026-10-20-f20-s1-jakosc-asr.md` (S1),
  `docs/superpowers/spikes/2026-10-20-f20-s2-serwery-tekstowe.md` (S2, commit `38ac47f`).
  Odbiory i przegląd: `docs/superpowers/reports/F20-2.0a-odbior.md` (T8), `docs/superpowers/reports/F20-2.0b-odbior.md` (T14, sprzęt),
  `docs/superpowers/reports/F20-przeglad-calosci.md` (T14, przegląd całości gałęzi: spójna ze specem, jeden wyjątek — ciche obcięcie wejścia).

**Faza 2.0.1 „Zmiana modelu w spotkaniu"** (scalona do `master` 2026-10-22: PR #19 plan `bed13d5`, PR #20 kod `0409a3f`, `--merge`): chip modelu w Summary i przy „Improve transcript", wybór zapisany przy sesji w `notes/meta.json` (`modelOverrides`, opcjonalne),
preset i `RunSnapshot` bez zmian. `master` po PR #17 (pigułka: wyjście i „No system audio yet"): **582/582**; gałąź 2.0.1: **592/592**. Odbiór na żywo zaliczony przez użytkownika 2026-10-22.
Spec: `docs/superpowers/specs/2026-10-22-zmiana-modelu-w-spotkaniu-design.md`, plan: `docs/superpowers/plans/2026-10-22-faza201-zmiana-modelu.md`.

**Faza 2.0.2 „Nagrywanie na słuchawkach"** (scalona do `master` 2026-10-23 przez PR #23, commit scalenia `c33bd48`, `--merge`; testy **622/622**): tor `system` na słuchawkach Bluetooth. Format tapa czytany z urządzenia zbiorczego (`CoreAudioDevices.captureFormat`), układ `AggregateLayout.tapOnly` domyślny (bez podurządzeń, jak w Chromium), nasłuch częstotliwości z `RebuildGate`, ostrzeżenie o złej prędkości toru (`SessionSummary.Track.rateMismatch`), `PillHint.systemStalled` i menu wejścia w pigułce (`InputChoice`, `RawMicrophoneSource.select`). Narzędzie `meetnotes-cli tap-rate`. **Odbiór M4 2026-10-23** (sesja `2f1c`, słuchawki jako wejście i wyjście, 27,5 min): tor `system` 47 998,9 Hz, „Them" kompletny. Niezmierzone: menu wejścia, fałszywy alarm pigułki, B, poczekalnia Teams, przypadek `08f6`. ScreenCaptureKit (Task 10) pominięty. Spec `docs/superpowers/specs/2026-10-22-faza202-sluchawki-design.md`, plan `docs/superpowers/plans/2026-10-22-faza202-sluchawki.md`, pomiary `docs/superpowers/spikes/2026-10-22-f202-s0-sluchawki.md`. **Jakość transkrypcji** (Parakeet myli terminy, korekta bez słownika i uczestników) czeka na fazę 2.1 „Słownik".

**Faza 2.1a „Słownik"** (gałąź `faza21-slownik`, **niescalona do `master`**, testy **730/730**; kod, CLI `dictionary-check`, migawki i raport gotowe, czeka na odbiór użytkownika i PR): Dictionary (Term/Alias, Risky, Priority; `dictionary.json`), Replacement przy odczycie transkryptu (surowy `transcript.json` nietknięty),
import/eksport `vocab_core.txt` i `replacements.tsv`, zakładka Dictionary, Termy i Attendee hint w poleceniach korektora i podsumowania (ślad `runs/<przebieg>/vocabulary.txt`), **D13 „Transcribe again…"** (kolejny przebieg z innym modelem ASR; bieżący = najnowszy ukończony, niepusty, bez luk).
Spec `docs/superpowers/specs/2026-10-23-faza21-slownik-design.md`, plan `docs/superpowers/plans/2026-10-23-faza21-slownik.md`, raport odbioru agenta `docs/superpowers/reports/F21-odbior.md` (kroki użytkownika w §4), odłożone w BACKLOG „Z fazy 2.1".
**Otwarte:** odbiór użytkownika (prawdziwe Termy/Aliasy, import GCX, nagranie z wydarzeniem na presecie z korektą, „Transcribe again…" na nagraniu z 2026-10-21), **2.1b** (klik na słowo → Alias), spike word boostingu.
**Minimalizm w Transcript i Summary** (gałąź `faza21-minimalizm` od `faza21-slownik`, niescalona; jedna linia narzędzi + menu ⋯, czytelne nazwy modeli przez `ModelName`/`ModelNameCache`; testy **738/738**; spec `docs/superpowers/specs/2026-10-24-transcript-summary-minimalizm-design.md`, plan `docs/superpowers/plans/2026-10-24-faza21-minimalizm.md`; do odbioru użytkownika: popover z ⋯, ciemny motyw, wąskie okno).

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
- **Artefakt „Mapa faz Yascribe"** (https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz, prywatny): każda zmiana w `BACKLOG.md`, ROADMAP i w postępie prac
  (zamknięta faza/zadanie, tag, scalony PR, liczba testów, wynik odbioru) ma też zaktualizować ten artefakt (`Artifact` read, edycja, publikacja pod tym samym URL-em; polecenie użytkownika 2026-10-21).

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
