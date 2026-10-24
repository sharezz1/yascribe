# Presets i Templates jak Dictionary — plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Presets i Templates dostają układ Dictionary: pełnoszeroka lista w karcie i okno (sheet) z formularzem, a w formularzu presetu sonda i „Extra instructions" są pod zwiniętą sekcją „Advanced".

**Architecture:** Wspólny kontener okna `EditorSheet` (przewijana treść + stały pasek na dole) i wspólny wiersz listy `EditorListRow`; `PresetsView`/`TemplatesView` stają się listą w `ScrollPage(640)` z `.sheet` otwieranym, gdy `draft != nil`. Treść formularzy (`PresetForm`, `TemplateForm`) zostaje, `RoleSection` dostaje `DisclosureGroup("Advanced")`; decyzję „rozwinięta od początku" podejmuje czysta funkcja `RoleAdvanced.startsExpanded`.

**Tech Stack:** Swift 6.4 na CLT, SwiftUI bez `@State`, `swift-testing`, `scripts/test.sh`, migawki `scripts/snapshot.sh`.

**Spec:** `docs/superpowers/specs/2026-10-24-presets-templates-okno-design.md`. Wzorzec: `Sources/MeetNotesApp/DictionaryView.swift` (`DictionaryTermSheet`, `listState`) i `DictionaryViewState.swift`.

## Przydział modeli (jak poprzednio: trudne Opus, łatwiejsze Sonnet i Haiku)

| Zadanie | Model | Dlaczego |
|---|---|---|
| T1 `RoleAdvanced.startsExpanded` | Haiku | czysta funkcja z gotowymi przypadkami |
| T2 `EditorSheet`, `EditorListRow`, Presets, „Advanced" | **Opus** | wspólne komponenty, stan modalnego edytora, ryzyko utraty danych |
| T3 Templates | Sonnet | ten sam wzorzec co T2, jeden widok |
| T4 migawki i dokumenty | Haiku | mechaniczne |

## Global Constraints

- Testy wyłącznie `scripts/test.sh`; SwiftUI bez `@State`, `@Entry`, `@Animatable`, `#Preview`; nowe pola w zapisywanych typach tylko opcjonalne (tu: brak nowych pól).
- Nigdy `git add -A`/`git add .`; jawne ścieżki. Interfejs po angielsku, komentarze i dokumenty po polsku.
- Okno: szerokość 560 pt, wysokość do ok. 80% okna, tło `mnCard`, `.tint(.mnAccent)`, Esc = Cancel, ⌘S i Return = Save (jak `DictionaryTermSheet`).
- Zachowanie zapisu bez zmian: `model.savePreset`, `file.upsert`, te same komunikaty błędów; zmienia się tylko miejsce ich pokazania (w oknie, nad paskiem).
- Gałąź `faza21-okna` (od `faza21-minimalizm`).

## Review Focus

- Cancel/Esc przy niezapisanych zmianach zamyka okno bez zapisu; Save po sukcesie zamyka; Save z błędem (`state.error`) zostawia okno otwarte z komunikatem.
- Nowy, niezapisany preset/szablon: Cancel nie zostawia go na liście; po Save pojawia się na liście.
- Preset ze złym wynikiem sondy (`works == false`) i ten z niepustym „Extra instructions": „Advanced" tej roli otwiera się sam.
- Szablon: „Delete template…" pyta o potwierdzenie z poziomu okna i po usunięciu zamyka okno; „Duplicate" zostaje w oknie z kopią jako nowym szablonem; „Reset to default" (wbudowany, edytowany) zostaje w oknie z przywróconą treścią.
- Wysoki formularz (trzy role, albo szablon z wieloma sekcjami): treść przewija się, pasek na dole zostaje na widoku.
- Stan „zawsze jest ≥ 1 preset/szablon": lista nigdy nie jest pusta, ale brak presetów (`presets.presets.isEmpty`) nie może wywalić widoku.

---

### Task 1: `RoleAdvanced.startsExpanded` (Haiku)

**Files:**
- Create: `Sources/MeetNotesProviders/RoleAdvanced.swift`
- Test: `Tests/MeetNotesProvidersTests/RoleAdvancedTests.swift`

**Interfaces:**
- Produces: `public enum RoleAdvanced { public static func startsExpanded(probe: ProbeResult?, prompt: String?) -> Bool }`

- [ ] **Step 1: Write the failing tests** (`import Testing`, `@testable import MeetNotesProviders`; `ProbeResult(providerID: UUID(), model: "m", role: .asr, works: …, languageHandling: …)`):
  - `collapsedWithoutProbeAndPrompt`: `(nil, nil)` → `false`
  - `collapsedForWorkingProbeAndBlankPrompt`: `works: true, languageHandling: .enforced` i prompt `"  "` → `false`
  - `expandedForFailedProbe`: `works: false` → `true`
  - `expandedForUnknownLanguageHandling`: `works: true, languageHandling: .unknown` → `true`
  - `expandedForAutomaticLanguageHandling`: `.automatic` → `true`
  - `expandedForNonEmptyPrompt`: `(nil, "Keep product names")` → `true`
- [ ] **Step 2: Run** `scripts/test.sh` → FAIL (brak `RoleAdvanced`).
- [ ] **Step 3: Implement** `startsExpanded`: `true`, gdy sonda istnieje i (`!works` lub `languageHandling` ∈ {`.unknown`, `.automatic`}) albo `prompt` po przycięciu niepusty.
- [ ] **Step 4: Run** `scripts/test.sh` → PASS (+6 testów, bez kodu 3/4).
- [ ] **Step 5: Commit** — `git add Sources/MeetNotesProviders/RoleAdvanced.swift Tests/MeetNotesProvidersTests/RoleAdvancedTests.swift`, „Faza 2.1 okna: RoleAdvanced".

### Task 2: `EditorSheet`, `EditorListRow`, Presets i „Advanced" (Opus)

**Files:**
- Create: `Sources/MeetNotesApp/EditorSheet.swift`
- Modify: `Sources/MeetNotesApp/PresetsView.swift` (`PresetEditorState` `:4-21`, `PresetsView` `:24-101`, `PresetRow` `:103-123`, `EditorFooter` `:125-150` do usunięcia po T3, `RoleSection` `:262-358`)

**Interfaces:**
- Consumes: `RoleAdvanced.startsExpanded(probe:prompt:)` (T1).
- Produces: `struct EditorSheet<Leading: View, Content: View>: View` z `init(title: String, dirty: Bool, error: String?, onCancel: () -> Void, onSave: () -> Void, @ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content)`: nagłówek (14 Semibold), przewijana treść, pasek na dole (`leading` po lewej, Cancel i Save po prawej, błąd nad paskiem jako `StateLabel(.bad, …)`, Save `.disabled(!dirty)`, Esc/⌘S/Return); szerokość 560, `.background(.mnCard)`, `.tint(.mnAccent)`. `struct EditorListRow: View` z `init(title: String, subtitle: String, trailing: some View = EmptyView())` (wiersz karty jak `DictionaryRow`: nazwa 13 Medium, podpis 11 pt `mnText2`, `trailing` po prawej, `contentShape(Rectangle())`). `PresetEditorState.close()` (zeruje `draft`, `original`, `error`). `struct PresetSheet: View { init(state: PresetEditorState, onSave: () -> Void) }` (renderowalny osobno do migawek).

- [ ] **Step 1: Implement** `EditorSheet` i `EditorListRow` w `EditorSheet.swift`; `PresetEditorState.close()`; `PresetsView` jako `ScrollPage(640)`: nagłówek (`PageTitle("Presets")`, `Spacer`, „New preset" `.pill`), `Card` z wierszami (`EditorListRow`, metadane z dotychczasowego `meta(_:)`, „default" jak dziś, `FullyLocalBadge` jako `trailing`), `.sheet(isPresented: Binding(get: { state.draft != nil }, set: { if !$0 { state.close() } }))` z `PresetSheet`; zapis: `state.error = model.savePreset(draft)`, przy `nil` — `state.close()`. Usuń blokadę „Save or cancel…", wiersz „unsaved" i `EmptyEditorHint` z presetów.
- [ ] **Step 2: „Advanced" w `RoleSection`**: rząd sondy (`probeRow`) i pole `promptTitle` (Extra instructions) w jednej `DisclosureGroup("Advanced", isExpanded: …)` (wzorzec: `MeetingSettingsView.swift:101`); stan rozwinięcia lokalny (`ObservableObject` + `@StateObject`, jak reszta aplikacji) z początkową wartością `RoleAdvanced.startsExpanded(probe: model.probeCache.result(provider: a.providerID, model: a.model, role: role, language: language), prompt: a.prompt)`; po kliknięciu „Test" sekcja pozostaje w stanie wybranym przez użytkownika. `RoleSection` w Settings (embedding, przez `RoleEditor`) zachowuje się tak samo (bez zmiany sygnatury).
- [ ] **Step 3: Verify** `swift build --disable-keychain --product MeetNotesApp`; `scripts/test.sh` zielony (liczba bez zmian poza T1); ręcznie `scripts/run.sh`: lista presetów, klik otwiera okno, Cancel/Esc zamyka bez zapisu, Save zapisuje i zamyka, błąd zapisu (np. brak modelu ASR) zostawia okno z komunikatem, „Advanced" zwinięte, a przy złej sondzie rozwinięte.
- [ ] **Step 4: Commit** — `git add Sources/MeetNotesApp/EditorSheet.swift Sources/MeetNotesApp/PresetsView.swift`, „Faza 2.1 okna: Presets — lista, okno i Advanced".

### Task 3: Templates (Sonnet)

**Files:**
- Modify: `Sources/MeetNotesApp/TemplatesView.swift` (`TemplateEditorState` `:4-24`, `TemplatesView` `:29-153`, `TemplateForm` `:161-262` — menu `⋯` przechodzi do paska okna), `Sources/MeetNotesApp/PresetsView.swift` (usunąć nieużywane `EditorFooter`, `PresetRow`, `EmptyEditorHint`, jeśli nikt ich już nie używa — sprawdź grep)

**Interfaces:**
- Consumes: `EditorSheet`, `EditorListRow` (T2).
- Produces: `TemplateEditorState.close()`; `struct TemplateSheet: View { init(state: TemplateEditorState, meta: String, builtin: Bool, edited: Bool, onSave: () -> Void, onDuplicate: () -> Void, onReset: () -> Void) }`.

- [ ] **Step 1: Implement** `TemplatesView` jak `PresetsView` (lista w karcie z „Built-in" / „Built-in · edited" / „Custom" jako podpisem, `.sheet` po `draft != nil`); akcje z menu `⋯` formularza trafiają do `leading` paska okna: „Duplicate", „Reset to default" (tylko wbudowany, nieaktywny bez edycji), „Delete template…" (tylko własny; `confirmationDialog` jak dziś, po usunięciu `close()`); Save: istniejące komunikaty błędów w `state.error`, sukces zamyka okno.
- [ ] **Step 2: Verify** build, `scripts/test.sh`; ręcznie: edycja wbudowanego i zapis, Reset, Duplicate (kopia otwarta w oknie jako nowy szablon), Delete z potwierdzeniem, Cancel/Esc bez zapisu.
- [ ] **Step 3: Commit** — jawne ścieżki dwóch plików, „Faza 2.1 okna: Templates — lista i okno".

### Task 4: Migawki i dokumenty (Haiku)

**Files:**
- Modify: `Sources/MeetNotesApp/Snapshots.swift` (migawki Presets `:105-114`, `:387-389`, `:422-425`, `:522-524`; Templates `:271-275`), `CLAUDE.md` (jedna linia w „Stan")

- [ ] **Step 1: Implement** migawki: lista presetów (`presets`) i szablonów (`templates-list`), a ekrany „editing" renderują `PresetSheet`/`TemplateSheet` bezpośrednio (`ImageRenderer` nie łapie `.sheet`; wzorzec: dotychczasowe migawki `dictionary-edit`), jak sąsiednie wywołania z pętlą jasny/ciemny; dodaj migawkę okna presetu z „Advanced" rozwiniętym (zła sonda) i zwiniętym.
- [ ] **Step 2: Verify** `scripts/snapshot.sh` bez błędu; obejrzyj nowe PNG w `.design/review/` (Read) i opisz to, co widzisz, nie to, co zakładasz; `scripts/test.sh` zielony.
- [ ] **Step 3: CLAUDE.md** — jedna linia w „Stan" po linii o minimalizmie: Presets i Templates jak Dictionary (lista + okno, „Advanced" w formularzu presetu), gałąź `faza21-okna`, spec i plan, „do odbioru użytkownika".
- [ ] **Step 4: Commit** — `git add Sources/MeetNotesApp/Snapshots.swift CLAUDE.md`, „Faza 2.1 okna: migawki i dokumenty".

## Odbiór użytkownika (nie dla agenta)

Wysokość i szerokość okna presetu; czy „Advanced" nie chowa tego, czego używasz często (sonda „Test"); lista w ciemnym motywie; edycja, Reset, Duplicate i Delete szablonu.
