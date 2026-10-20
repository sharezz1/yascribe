# F20 — przegląd całości gałęzi `faza20` (T14, część B)

> 2026-10-20, Opus z delegacji użytkownika. Zakres: `git diff faza15..faza20` (83 pliki, +6764/−112; gałąź na `11fb41d` = kod `9720d3b`, raport S1
> `6f2da98`, raport T8 `aca4260` i poprawka U1 `11fb41d`). Przegląd tylko do odczytu; w repo powstały wyłącznie dwa raporty T14. Odbiór sprzętowy 2.0b:
> `F20-2.0b-odbior.md` (ten sam commit).
> `scripts/test.sh` uruchomiony raz, na końcu, na `11fb41d`: **kod 0, 548/548** (12:14–12:16, load 1,7 → 6,2).
> Scalenie `faza20` → `master` **nie** jest decyzją Opusa.

## 0. Werdykt

**Gałąź jest spójna ze specem i obiema recenzjami (R1–R14, P1–P13 zamknięte w kodzie poza P9), anty-cele mają bramki w kodzie i testy — z jednym
wyjątkiem znalezionym na sprzęcie:** Ollama 0.40.6 **obcina wejście po cichu** dla `bonsai-2` (HTTP 200, `finish_reason: "stop"`), gdy prompt jest
dłuższy niż kontekst serwera (odbiór, pkt 2b). Aplikacja dochodzi do tego stanu tylko wtedy, gdy pole „Context window” jest wyższe niż kontekst serwera,
a wykrycie (`/api/ps`) nie obniży budżetu, bo model nie jest załadowany — wtedy notatka powstaje z ok. 20 % promptu, bez instrukcji szablonu, i zapisuje się
jako sukces. To łamie anty-cel „ciche obcięcie” (spec §2) i założenie §14 („Ollama nie obcina wejścia”, zmierzone w S2 tylko na `genesys-ministral3`).
**Do decyzji użytkownika przed scaleniem** (propozycje w §5). Poza tym nic blokującego.

## 1. Bezpieczeństwo i dane

| Obszar | Wynik | Dowód |
|---|---|---|
| Klucze API | Nic nie loguje ani nie zapisuje klucza poza pękiem; nowe ścieżki: test połączenia na kluczu z pola w pamięci, `ContextProbe` wysyła nagłówek `Authorization` tylko, gdy klient ma klucz; treść błędu HTTP maskuje klucz (bez zmian). Opcjonalny klucz oMLX: pusty nie trafia do pęku. | `AppModel.swift:313, 396-408`; `ContextProbe.swift:46`; `HTTPClient.swift:18-24`; `SettingsView.swift` (`keyOptional`) |
| Klucz opcjonalny — usunięcie | Zapisanego klucza oMLX nie da się wyczyścić (pusty = „zostaw”) — już w BACKLOG. | `AppModel.swift:397` |
| Sieć bez akcji użytkownika | Lokalny ASR: ładowanie wyłącznie `AsrModels.loadLocal`, pobranie wyłącznie `AsrModels.download` z przycisku karty; w `Sources` nie ma `AsrModels.load(`/`downloadAndLoad`. 2.0b: `ContextProbe` (GET `/props`, `/api/ps`, limit 5 s) woła tylko adres dostawcy, przed korektą/notatką i w „Check”. Prawdziwy test „sieć off” (T8) — po stronie użytkownika. | `FluidAudioEngine.swift:19`; `ModelStore.swift:136-149`; `ModelCardView.swift:113,159`; `NotesModel.swift:89,138` |
| Kasowanie plików | `ModelStore.remove()` kasuje tylko `<korzeń>/parakeet-tdt-0.6b-v3` (nazwa ze stałego manifestu, bez danych z zewnątrz → brak path traversal); `force` przekazywany do FluidAudio tylko przy złym rozmiarze pliku albo `modelsExist` przy `invalid`; oba za potwierdzeniem w UI z nazwą lokalizacji. Override `MEETNOTES_MODEL_STORE` tylko w DEBUG. | `ModelStore.swift:45-57, 99-130`; `ModelCardView.swift:87-100` |
| Codable (E6) | Nowe pola zapisywane tylko opcjonalne: `Provider.contextTokens`, `RunSnapshot.modelFingerprint`, `NoteSummary.condensedParts`; brak własnych `init(from:)`; testy starych plików: `oldInputJSONWithoutFingerprintStillLoads`, `condensedParts` nieobecne w JSON przy `nil`. Nowy przypadek `ProviderKind.fluidAudio` — stary build nie wczyta nowego `providers.json` z tym wpisem (kierunek odwrotny, poza E6). | `Provider.swift:13-14`; `RunnerTests.swift` (2 nowe testy); `MapReduceTests.swift:498` |
| Pliki w gałęzi | W `faza15..faza20` brak `agentdb.rvf*`, `.devdata`, wag modeli; `Package.resolved` celowo śledzony (pin FluidAudio 0.17.7 / `503b4bd1…`). **Uwaga:** scalenie `faza20` → `master` wniesie też 7 commitów marki z `faza15` (nie ma ich w `master`): PNG 108–196 kB (w tym `zrodlo-chatgpt-zlote-pioro.png`), `AppIcon.icns` 204 kB, skrypty Pythona w `docs/design/marka/`. W katalogu głównym repo leży nieśledzony `ruvector.db` (ignorowany). | `git diff --stat master..faza20` |
| Hook pre-commit | `core.hooksPath` → `scripts/hooks`, `pre-commit` = `scripts/check-hashes.sh`; przebieg na gałęzi: kod 0. Wszystkie hashe cytowane w dokumentach F20 (16) są na `faza20`. Słabość: hook uznaje hash „na **jakiejkolwiek** gałęzi”, także `worktree-agent-*`, które znikną po sprzątaniu — po usunięciu worktree hash z niescalonej gałęzi przestanie przechodzić dopiero przy następnym commicie. | `scripts/check-hashes.sh:13-16` |

## 2. Anty-cele speca (§2)

| Anty-cel | Stan | Dowód |
|---|---|---|
| Ciche przełączenie na API | Zamknięte: odmowa = `nil` klienta i komunikat; nie ma ścieżki zapasowej. | `AppModel.swift:328-345`; `RunGate.swift:41-47`; test `missingModelRefusesRunAndNeverFallsBack` |
| Pobieranie bez zgody | Zamknięte w kodzie (przycisk z rozmiarem z manifestu; „Download again” z potwierdzeniem). Sieć off — T8. | `ModelCardState.swift:49,72`; `ModelCardView.swift:87-100` |
| Zmyślone treści | Strażnik języka bez zmian; korekta tylko przez `CorrectionRules.accepts` (pasmo długości — **nie łapie zmian liczb/dat**, BACKLOG, decyzja użytkownika); mapa wymaga formatu `[m:ss] Me|Them:`. | `Corrector.swift:36-41,165-168`; `NoteGenerator.swift:156-168` |
| Ciche obcięcie transkryptu | **Otwarte częściowo.** Wyjście: `finish_reason: "length"` = błąd (zamknięte, potwierdzone na sprzęcie). Wejście: Ollama + `bonsai-2` obcina po cichu, gdy prompt > kontekst serwera (zmierzone 3×: 9987→2050, 4219→2050 tokenów, z `max_tokens` i bez). Aplikacja nie ma drugiej linii obrony (nie porównuje `usage.prompt_tokens` z długością promptu). | `OpenAICompatibleClient.swift:154`; odbiór pkt 2b |

## 3. Recenzje F20 — stan zamknięcia

| Punkt | Stan | Dowód (plik:linia) |
|---|---|---|
| R1 bramka klucza | zamknięte | `Provider.swift` `isLocal`/`requiresKey`; `AppModel.swift:313` |
| R2 dwa limity czasu | zamknięte | `OpenAICompatibleClient.swift:136-153`; `ChatLimits.swift:25-39` |
| R3 materiał S1 | zamknięte (dokumenty; S1 wykonany — `6f2da98`) | spec §13 pkt 1 |
| R4 cztery miejsca `ProviderKind` | zamknięte | `AppModel.swift:436`; `ProviderSetup.swift:72`; `Probe.swift:78` |
| R5 `.filtered` | zamknięte | `Probe.swift:78` |
| R6 budżet korekty / `/api/show` | zamknięte w kodzie (`/api/show` odpada, wykrycie tylko obniża); **założenie „Ollama nie obcina wejścia” obalone** dla `bonsai-2` | `ContextBudget.swift:39-43`; `ContextProbe.swift:15-25`; `Corrector.swift:123-127` |
| R7 kontrakt map-reduce | zamknięte (format linii, My notes tylko w reduce, zdanie „condensed”) | `NotePrompt.swift` (`mapPrompt`, `condensedSentence`); `NoteGenerator.swift:106-152` |
| R8 cykl życia modelu ASR | zamknięte (`actor`, `release()` w sondzie i po przebiegu) | `LocalASRClient.swift:23,67`; `AppModel.swift:455,657` |
| R9 serwery S2 | zamknięte (S2 wykonany) | raport S2 |
| R10 Parakeet na dysku | zamknięte (spec §3.5) | — |
| R11 `CorrectionRules.accepts` | zamknięte | `Corrector.swift:36` |
| R12 suma kontrolna | zamknięte jako manifest rozmiarów + odcisk małych plików (sufit opisany) | `ModelStore.swift:59-97` |
| R13 odcisk w migawce | zamknięte (pole opcjonalne) | `RunGate.swift:37-39`; `AppModel.swift:601` |
| R14 kolejność | zamknięte | spec §7, §11.2 |
| P1 odcisk na ścieżce aplikacji | zamknięte (`RunGate.checkResume` przed `run`, także w CLI) | `AppModel.swift:621`; `CLI.swift:219` |
| P2 budżet end-to-end | zamknięte w kodzie (`max_tokens` mapy, warunek reduce ≤ limit, dzielenie długiej linii, limit na wywołanie) | `NoteGenerator.swift:142,183-190`; `TranscriptSplitter.swift` |
| P3 magazyn (wstrzyknięcie, stan, manifest, wariant) | zamknięte | `ModelStore.swift:35-40,59-79`; `RunGate.swift:25` |
| P4 override magazynu w aplikacji | zamknięte (DEBUG) | `ModelStore.swift:45-50` |
| P5 `ContextProbe` z modelem, droga do `NotesModel`, znaki/token | zamknięte (wykrycie w chwili użycia; 2,4 zn./tok. — na sprzęcie 2,8–3,3) | `NotesModel.swift:89,138` |
| P6 `timedOut` ≠ „serwer nie działa” | zamknięte | `ProviderSetup.swift:191-197` |
| P7 `Package.resolved` | zamknięte (`a6d6568`) | `Package.resolved` |
| P8 „Preparing model…” | zamknięte | `LocalASRClient.swift:88`; `ModelCardState.swift:9` |
| P9 baseline jakości S2 | **otwarte** — baseline API wymaga klucza użytkownika | odbiór pkt 11 |
| P10 `AutoTitle` | zamknięte (`ChatLimits .title`) | `NotesModel.swift:201-205` |
| P11 `Preset.isFullyLocal` | zamknięte | `Preset.swift:79` |
| P12 rozmiar z manifestu | zamknięte | `ModelCardState.swift:49,72` |
| P13 `ContextError` API vs lokalnie | zamknięte | `ContextError.swift:44-50` |

## 3a. Commity po rozpoczęciu przeglądu: T8 i U1

- **Raport T8** (`F20-2.0a-odbior.md`, `cec0263`/`aca4260`): odbiór 2.0a bez kroków użytkownika — wszystkie kroki agenta przeszły, Wi-Fi off,
  „Download”, „Preparing…” w `.app` i 3.1 czekają na użytkownika; wykrył **U1** (słowa rozciągnięte przez wyciętą ciszę na sklejeniach okien).
  Raport nie przeczy kodowi; liczby czasów i pamięci przyjmuję z raportu (nie powtarzałem).
- **U1** (`11fb41d`): `Chunk.sourceSpan` mapuje oba końce słowa w obrębie fragmentu, w którym słowo się zaczyna; `Merger` używa go zamiast dwóch osobnych
  `sourceSeconds`. Przeczytane: przycięcie jest monotoniczne (`max(s, e)` zostaje), słowa w całości w jednym fragmencie bez zmian, słowo w całości w przerwie →
  zerowa długość na początku następnego fragmentu; warunek `segments` niepuste — ten sam co w istniejącym `sourceSeconds` (paker nie tworzy pustych okien).
  4 nowe testy w `RunnerTests` (sklejenie, środek fragmentu, start w przerwie, początek wypowiedzi). Dotyczy też ścieżki API (wspólny `Merger`) — zmiana
  czasu słów, nie tekstu. Bez uwag.

## 4. Zgodność dokumentów z kodem

1. **`CLAUDE.md` i `docs/wymagania.md` są nieaktualne po `6f2da98` i `aca4260`:** piszą „pliku S1 nie ma” / „S1 nie została zmierzona” i „brak raportu”
   T8, a oba raporty są na gałęzi. `CLAUDE.md` podaje też stan „na `e36b8bd`” (bez U1). Poprawka dokumentów — przy scaleniu (nie w tym commicie: T14 commituje tylko raporty).
2. **Definicja „lokalny”:** spec §11.5 i `wymagania.md` wymieniają `localhost`, `127.0.0.1`, `::1`, `*.localhost`; kod (po przeglądzie T10, `a95096e`) uznaje też
   całe `127.0.0.0/8` i `0.0.0.0` (z testami). Rozszerzenie jest rozsądne (loopback), ale dokumenty go nie mówią — od tego zależą `requiresKey` i wysyłka
   `reasoning_effort`.
3. **Ponowienie bez `reasoning_effort`:** spec §14 pkt 2 — treść błędu zawiera `reasoning`; kod — `reasoning` **albo** `think`
   (`OpenAICompatibleClient.swift:147`). Szersze, nieszkodliwe; do dopisania w specu.
4. **Spec §14 / `wymagania.md`: „Ollama nie obcina wejścia (HTTP 400)”** — prawda dla `genesys-ministral3`, **fałsz dla `bonsai-2`** (odbiór pkt 2b). Do poprawy po decyzji.
5. `max_tokens` części mapy: spec §14 pkt 5 mówi `0,5 × wejścia`, kod (po `4ff727b`) daje miejsce po prompcie, najwyżej `1,0 × wejścia`. Świadoma zmiana
   z przeglądu T13; spec niezaktualizowany.
6. Plan: pola `- [ ]` przy T11, T12, T14 nieodhaczone (już w BACKLOG).

## 5. Ryzyka i co musi zrobić / zdecydować użytkownik

**Decyzje przed scaleniem**
1. **Ciche obcięcie wejścia przez Ollamę (bonsai-2)** — propozycje do wyboru: (a) w `chat` dla dostawców lokalnych porównać `usage.prompt_tokens` z długością
   promptu (np. `(system+user).count / prompt_tokens > 5` → błąd „the server cut the input”; zmierzone normalnie 2,8–3,3, przy obcięciu 6,6–14,8) — jedna gałąź,
   test na atrapie; (b) wymagać wykrycia kontekstu (gdy pole > 4096, a `/api/ps` nic nie zwraca — najpierw załadować model albo odmówić); (c) zostawić i opisać.
   Rekomendacja Opusa: (a) — tania, działa też dla oMLX, gdzie wykrycia nie ma.
2. **Scalenie `faza20` → `master`** (wnosi też markę z `faza15`).
3. Pozycje „Do potwierdzenia rano” 1–14 z `F20-decyzje-opusa.md` — bez zmian; pomiar dorzuca do pkt 9 (lokalna korekta) i pkt 10 (kontekst): przy 4096 notatka
   z 60 min **nie powstaje** (`bonsai-2` nie skondensował części 1 z 11 w limicie), przy 8192 też nie (8 części, 16,8 min, potem jawne wczesne
   przerwanie — mapa skraca do 0,62–0,78 zamiast ≤ 0,40). Realnie potrzebny kontekst serwera ≥ 16384 (niezmierzone end-to-end).

**Kroki ręczne (tylko użytkownik)**
- T8: powtórzenie przy wyłączonym Wi-Fi (pełny przebieg „Fully local”), kliknięcie „Download (483 MB)” na karcie (albo przeniesienie kopii z `.devdata/model-store`),
  nagranie na żywo dla kryterium 3.1 i pary PL+EN (T11).
- oMLX: model mieszczący się w pamięci i własny klucz w aplikacji — inaczej oMLX zostaje niezmierzony.
- Baseline API (ta sama notatka i korekta przez API) — klucz, koszt, wysyłka do chmury.
- Poprawki dokumentów z §4 przy scaleniu.

**Ryzyka bez decyzji (znane, w BACKLOG albo tutaj)**
- Tytuł z modelem, który nie kończy jednej linii w 64 tokenach (`genesys-ministral3`), zawsze kończy się `length` → cicho „Untitled” (odbiór pkt 3).
- Hook hashy ufa gałęziom `worktree-agent-*` (§1).
- Lokalna korekta zmienia formy fleksyjne; liczby/daty/nazwiska w pomiarze T14 nietknięte, ale S2 pokazał zmianę daty — bramka liczb/dat nadal tylko w BACKLOG.
