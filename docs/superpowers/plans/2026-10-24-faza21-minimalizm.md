# Minimalizm w Transcript i Summary — plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jedna linia narzędzi w zakładkach Transcript i Summary (rzadkie akcje w menu `⋯`) i czytelne nazwy modeli tam, gdzie dziś stoi `id` dostawcy.

**Architecture:** Nazwa do wyświetlenia to czysta funkcja `ModelName.display(id:apiName:)` plus mała podręczna tabela `id → nazwa` (`ModelNameCache`, plik `model-names.json`, wzorzec `ProbeCache`), zapełniana przy każdym pobraniu listy modeli. Wspólny widok `MoreMenu` (przycisk `⋯` z `Menu`) obsługuje obie zakładki; istniejące popovery modelu i „Transcribe again…" zostają, tylko otwiera je pozycja menu, a nie osobny przycisk.

**Tech Stack:** Swift 6.4 na CLT, SwiftUI bez `@State` (`ObservableObject` + `@StateObject`), `swift-testing`, testy tylko `scripts/test.sh`, migawki `scripts/snapshot.sh`.

**Spec:** `docs/superpowers/specs/2026-10-24-transcript-summary-minimalizm-design.md`. Makieta: https://claude.ai/artifact/AqP5EUBqoT6do7V8QChVnf

## Przydział modeli (decyzja użytkownika 2026-10-24: trudne Opus, łatwiejsze Sonnet i Haiku)

| Zadanie | Model | Dlaczego |
|---|---|---|
| T1 `ModelName` + `ModelNameCache` | Haiku | czysta funkcja i struktura danych, testy z gotowymi wartościami |
| T2 wpięcie w `AppModel` | Sonnet | zapis/odczyt pliku i hak w `loadModels`, bez testów jednostkowych (app) |
| T3 `MoreMenu` + Transcript | **Opus** | popover otwierany z pozycji menu, stany, kolejność decyzji w pasku |
| T4 Summary | Sonnet | ten sam wzorzec co T3, jeden widok |
| T5 migawki, dokumenty | Haiku | mechaniczne |

## Global Constraints

- Testy wyłącznie `scripts/test.sh`, nigdy goły `swift test`.
- SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`.
- Nowe pola w zapisywanych typach tylko opcjonalne (`ModelInfo.name: String?`).
- Nigdy `git add -A` ani `git add .`; jawne ścieżki. Mutacja bramki: wprowadź → test pada → `git checkout <plik>`.
- Interfejs po angielsku, dokumenty po polsku. Gałąź `faza21-minimalizm` (od `faza21-slownik`; `TranscribeAgainButton` i „Transcribe again…" są z 2.1a).
- Każda dzisiejsza akcja z paska ma zostać osiągalna w co najwyżej dwóch kliknięciach; żaden komunikat nie znika, tylko zmienia miejsce.
- Pełne `id` modelu zostaje w `.help` i w `ModelPicker` (tam wybór musi być jednoznaczny). `MeetingModelChip` w popoverze i `ModelPicker` nie zmieniają się.
- Zakres nazw: tylko Transcript i Summary. Presets, Templates, Settings bez zmian.

## Review Focus

- `id` bez `/` (`qwen3:8b`, `llama3`): zostaje bez zmian.
- `id` z wieloma `/` (`hf.co/org/model:Q4`): bierze się część po ostatnim `/`.
- Nazwa API bez dwukropka albo pusta/same spacje: pusta → cofnięcie do `id`; bez dwukropka → cała nazwa.
- Nazwa API z dwukropkiem w środku (`Qwen: Qwen3: 8B`): obcinamy tylko pierwszy przedrostek.
- Plik `model-names.json` uszkodzony: `read(...)` w `AppModel.load()` odkłada go na bok i startuje z pustą tabelą.
- Akcje wyłączone w trakcie przenoszenia nagrań (`moving`), korekty (`correcting`) i transkrypcji (`busy`): pozycje menu mają te same `.disabled` co dzisiejsze przyciski.
- Pasek przy wąskim oknie (900 pt) nie ucina i nie nakłada elementów.

---

### Task 1: `ModelName` i `ModelNameCache` (Haiku)

**Files:**
- Create: `Sources/MeetNotesProviders/ModelName.swift`
- Modify: `Sources/MeetNotesProviders/OpenAICompatibleClient.swift:11-15` (pole `name`), `:98-102` (odczyt `name` z `/models`)
- Test: `Tests/MeetNotesProvidersTests/ModelNameTests.swift`

**Interfaces:**
- Produces: `ModelInfo.name: String?`; `ModelName.display(id: String, apiName: String?) -> String`; `struct ModelNameCache: Codable, Equatable, Sendable { var names: [String: String]; mutating func record(_ models: [ModelInfo]) -> Bool; func display(_ id: String) -> String }` (`record` zwraca `true`, gdy tabela się zmieniła).

- [ ] **Step 1: Write the failing tests** w `ModelNameTests.swift` (`import Testing`, `@testable import MeetNotesProviders`):
  - `displayStripsVendorPrefixFromApiName`: `display(id: "deepseek/deepseek-v4.1-flash", apiName: "DeepSeek: V4.1 Flash") == "V4.1 Flash"`
  - `displayKeepsOnlyFirstPrefix`: `apiName: "Qwen: Qwen3: 8B"` → `"Qwen3: 8B"`
  - `displayUsesWholeApiNameWithoutColon`: `apiName: "Parakeet TDT"` → `"Parakeet TDT"`
  - `displayFallsBackToIdTail`: `display(id: "nvidia/parakeet-tdt-0.6b-v3", apiName: nil) == "parakeet-tdt-0.6b-v3"`, `apiName: "  "` → to samo
  - `displayKeepsLocalIds`: `display(id: "qwen3:8b", apiName: nil) == "qwen3:8b"`; `display(id: "hf.co/org/model:Q4", apiName: nil) == "model:Q4"`
  - `cacheRecordsNamesAndReportsChange`: `record([ModelInfo(id: "a/b", name: "A: B")])` zwraca `true`, drugie wywołanie tym samym `false`; `display("a/b") == "B"`; `display("x/y") == "y"`
  - `cacheIgnoresModelsWithoutName`: `record([ModelInfo(id: "a/b")]) == false`
  - `modelInfoDecodesOldFileWithoutName`: dekodowanie `{"id":"a/b"}` daje `name == nil`
- [ ] **Step 2: Run** `scripts/test.sh` → FAIL (brak `ModelName`).
- [ ] **Step 3: Implement** `ModelName.display` (przedrostek ucinany do pierwszego `": "` tylko gdy reszta niepusta; fallback: ostatni segment `id` po `/`) i `ModelNameCache` (klucz = samo `id`, bo ta sama nazwa u różnych dostawców jest taka sama); dodaj `public var name: String?` na końcu `ModelInfo`, w `listModels` `name: m["name"] as? String`.
- [ ] **Step 4: Run** `scripts/test.sh` → PASS (liczba testów rośnie o 8, brak kodu 3/4).
- [ ] **Step 5: Commit** — `git add Sources/MeetNotesProviders/ModelName.swift Sources/MeetNotesProviders/OpenAICompatibleClient.swift Tests/MeetNotesProvidersTests/ModelNameTests.swift`, „Faza 2.1 minimalizm: ModelName i tabela nazw".

### Task 2: Tabela nazw w `AppModel` (Sonnet)

**Files:**
- Modify: `Sources/MeetNotesProviders/Stores.swift:19` (nowy `public var modelNames: URL { root.appendingPathComponent("model-names.json") }`), `Sources/MeetNotesApp/AppModel.swift` (pole przy `:81`, odczyt przy `:169`, `loadModels` przy `:495`)

**Interfaces:**
- Consumes: `ModelNameCache` z T1.
- Produces: `AppModel.modelNames: ModelNameCache`; `AppModel.modelDisplayName(_ id: String) -> String` (bez dostawcy; `modelNames.display(id)`).

- [ ] **Step 1: Implement** pole `var modelNames = ModelNameCache()`; wczytanie `modelNames = read(paths.modelNames, ModelNameCache())` obok `probeCache`; w `loadModels` po udanym `listModels`: `if modelNames.record(list) { try? JSONFile.save(modelNames, to: paths.modelNames) }`; `func modelDisplayName(_ id: String) -> String`. Zapis w tle nie jest potrzebny (plik ma kilkadziesiąt KB).
- [ ] **Step 2: Verify** `swift build --disable-keychain --product MeetNotesApp` bez błędów; `scripts/test.sh` zielony (bez zmiany liczby testów).
- [ ] **Step 3: Commit** — `git add Sources/MeetNotesProviders/Stores.swift Sources/MeetNotesApp/AppModel.swift`, „Faza 2.1 minimalizm: tabela nazw w AppModel".

Znane ograniczenie: tabela zapełnia się dopiero po pobraniu listy modeli (otwarcie pickera albo „Refresh Models"). Do tego czasu aplikacja pokazuje `id` bez przedrostka dostawcy. Aplikacja nie pobiera list sama przy starcie (to byłoby ciche wywołanie sieci z kluczem).

### Task 3: `MoreMenu` i zakładka Transcript (Opus)

**Files:**
- Create: `Sources/MeetNotesApp/MoreMenu.swift`
- Modify: `Sources/MeetNotesApp/MeetingTabs.swift:135-203` (pasek i banery `TranscriptTab`), `Sources/MeetNotesApp/MeetingModelChip.swift`, `Sources/MeetNotesApp/TranscribeAgainButton.swift`

**Interfaces:**
- Consumes: `AppModel.modelDisplayName(_:)`.
- Produces: `struct MoreMenu<Content: View>: View` — przycisk `⋯` 28 × 28 (kółko, `mnLine`, jak `CircleIconButtonStyle`), `@ViewBuilder content` to zawartość `Menu`, `.accessibilityLabel("More actions")`; używany też w T4. `MeetingModelChip` i `TranscribeAgainButton` dostają tryb „sterowany z zewnątrz": popover otwiera się, gdy przekazany `Binding<Bool>` ma `true`, i kotwiczy się do `⋯`; dotychczasowy chip i przycisk znikają z paska (nie z kodu migawek, patrz T5).

Układ docelowy (makieta, plansze „A — …"): jedna linia `[Version ▾] … [Improve transcript]? [Copy] [⋯]`.
- „Improve transcript" na wierzchu (`.pillPrimary`) tylko gdy nie ma jeszcze korekty (`item.corrected == nil`) i `canRetryCorrection`; w innych stanach to pozycja „Improve transcript again" w `⋯`.
- `⋯`: „Improve transcript again", „Correction model: <modelDisplayName>…" (+ „ · changed" przy zmienionym modelu; otwiera popover chipa), separator, „Transcribe again…" (otwiera popover z `TranscribeAgainButton`; `disabled(blocker != nil)` jak dziś), separator, nieklikalna notka 11 pt `mnText2`: „Corrected with <nazwa>" (gdy korekta innym modelem niż przypisany) i „N parts kept as heard" (gdy `failedBatches + rejectedLines > 0`). Menu jest puste tylko wtedy, gdy nie ma żadnej pozycji — wtedy `⋯` się nie rysuje.
- Stany przejściowe: korekta trwa (`StateLabel(.progress …)`), korekta padła (`ErrorLine` z Retry), nowa transkrypcja w toku albo nieukończona (jedna linia; „Resume" jako `.pillSmall` w tej samej linii) — każdy jako **jedna linia** nad paskiem narzędzi, nie stos. Tekst błędu i `help(Self.why(a.reason))` zostają.
- „Corrected with …" i „parts kept as heard" znikają z paska (są w notce `⋯`); pozostałe komunikaty (`trackProblems`, „Transcribing again…") bez zmian.
- Nazwy modeli w tej zakładce (`Corrected with`, `runLabel`, chip) przez `modelDisplayName`; `.help` z pełnym `id`.

- [ ] **Step 1: Spike** (nieodrzucany kod, 30 min): czy `.popover` przypięty do `Menu`/przycisku `⋯` otwiera się po wybraniu pozycji menu, gdy pozycja ustawia `Binding<Bool>`? Sprawdź uruchamiając `scripts/run.sh` na nagraniu z `.devdata/`. Jeśli popover nie otwiera się albo znika razem z menu — zamiast popovera użyj `.sheet`/`.popover` na wierszu paska wyzwalanym po `DispatchQueue.main.async` po zamknięciu menu; opisz wybór w komunikacie commita.
- [ ] **Step 2: Implement** `MoreMenu` i przebuduj `TranscriptTab` wg układu wyżej; `MeetingModelChip`/`TranscribeAgainButton` wystawiają `content` do użycia z `Binding<Bool>` bez zmiany logiki zapisu (`save()`, `submit()`).
- [ ] **Step 3: Verify** `scripts/test.sh` zielony; `swift build --disable-keychain --product MeetNotesApp`; ręcznie w aplikacji: każda z akcji z dzisiejszego paska działa z `⋯` (Improve again, zmiana modelu, Transcribe again…), Copy działa, wąskie okno 900 pt nie ucina paska.
- [ ] **Step 4: Commit** — `git add Sources/MeetNotesApp/MoreMenu.swift Sources/MeetNotesApp/MeetingTabs.swift Sources/MeetNotesApp/MeetingModelChip.swift Sources/MeetNotesApp/TranscribeAgainButton.swift`, „Faza 2.1 minimalizm: Transcript — jedna linia i menu ⋯".

### Task 4: Zakładka Summary (Sonnet)

**Files:**
- Modify: `Sources/MeetNotesApp/MeetingTabs.swift:333-492` (`SummaryTab.body`, `bar`, `modelLine`, `madeWithLine`)

**Interfaces:**
- Consumes: `MoreMenu`, tryb sterowany `MeetingModelChip` z T3, `AppModel.modelDisplayName(_:)`.

Układ docelowy (makieta „Summary — propozycja A"): bez wnęki `mnSunk`; jedna linia `[Template ▾] [Add context] … [Regenerate | Generate notes] [Copy] [⋯]`.
- Przed notatką jedyny wyróżniony przycisk to „Generate notes" (⌘↩ jak dziś, `.disabled` jak dziś); po notatce „Regenerate" (`.pill`) i „Copy" (`.pill`, tekst zamiast ikony).
- „Add context" rozwija `ContextEditor` pod linią (jak dziś); po wpisaniu etykieta to „Context: <początek>" w `mnText2`, `lineLimit(1)`.
- `⋯`: „Summary model: <modelDisplayName>…" (otwiera popover chipa), separator, notka 11 pt: „Made with <nazwa> (preset: <nazwa>)" (gdy inny niż preset) i „Long meeting: condensed in N parts before summarizing." (gdy `condensedParts`). Obie linie znikają z treści zakładki.
- `modelLine` (brak presetu z modelem podsumowania: ostrzeżenie `mnWarn`; zastępstwo: „Using … from preset …") zostaje widoczne jedną linią pod paskiem — to stan wymagający uwagi, nie informacja.
- Linie stanu pustego i generowania (`generatingRow`, `correcting`, `disabledReason`, `errorView`) bez zmian.

- [ ] **Step 1: Implement** wg układu.
- [ ] **Step 2: Verify** `scripts/test.sh` zielony; build; ręcznie: „Generate notes", „Regenerate", zmiana modelu z `⋯`, rozwijanie kontekstu, wąskie okno.
- [ ] **Step 3: Commit** — `git add Sources/MeetNotesApp/MeetingTabs.swift`, „Faza 2.1 minimalizm: Summary — jedna linia i menu ⋯".

### Task 5: Migawki i dokumenty (Haiku)

**Files:**
- Modify: `Sources/MeetNotesApp/Snapshots.swift:147-170` (migawki popoverów i zakładek wciąż renderują `MeetingModelChip(... inlinePopover: true)` i `TranscribeAgainButton(... inlinePopover: true)`; dostosuj do trybu sterowanego z T3), `CLAUDE.md` (jedna linia w sekcji „Stan": minimalizm w Transcript i Summary, gałąź, liczba testów), `docs/superpowers/specs/2026-10-24-transcript-summary-minimalizm-design.md` (tylko jeśli T3/T4 zmienią ustalenia; korekta o popoverach zrobiona przy pisaniu planu)

- [ ] **Step 1: Implement** dostosowanie migawek; dodaj migawki: `meeting-transcript-calm` (korekta gotowa), `meeting-transcript-not-corrected` (Improve na wierzchu), `meeting-summary-calm`; ciemny motyw tak jak reszta.
- [ ] **Step 2: Verify** `scripts/snapshot.sh` generuje PNG w `.design/review/` bez błędu; `scripts/test.sh` zielony.
- [ ] **Step 3: Commit** — jawne ścieżki trzech plików, „Faza 2.1 minimalizm: migawki i dokumenty".

## Odbiór użytkownika (nie dla agenta)

Ciemny motyw i wąskie okno oglądane w prawdziwej aplikacji; czy dwa kliknięcia do zmiany modelu nie przeszkadzają; czy „Transcribe again…" nie powinno wrócić na wierzch; czy nazwy modeli są czytelne po pierwszym „Refresh Models".
