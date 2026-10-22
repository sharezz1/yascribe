# Faza 2.0.1: zmiana modelu w widoku spotkania — plan

> **Dla wykonawców:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (zalecane) albo `superpowers:executing-plans`. Kroki mają pola `- [ ]`. Stan zadań sprawdzaj wg commitów (`git log`), nie wg pól.

**Cel:** w zakładce Summary i przy „Improve transcript” (Transcript) wybrać dla tej jednej sesji inny model niż w presecie; wybór zapisuje się przy sesji.

**Architektura:** nadpisanie to nowe opcjonalne pole `modelOverrides` w `notes/meta.json` (`NoteMeta`). Cała logika wyboru (pierwszeństwo, ważność, zapis pola) żyje w `MeetNotesNotes` i ma testy; `MeetNotesApp` (bez testTargetu) tylko ją woła i rysuje chip modelu. `Preset`, `RunSnapshot`, `GlobalSettings` bez zmian.

**Stos:** Swift 6.4 (CLT), `swift-testing`, SwiftUI bez `@State`/`#Preview` (stan lokalny: `ObservableObject` + `@StateObject`).

**Spec:** `docs/superpowers/specs/2026-10-22-zmiana-modelu-w-spotkaniu-design.md` (decyzje 1–8 zaakceptowane 2026-10-22).

## Twarde zasady (CLAUDE.md, obowiązują każde zadanie)

- Testy wyłącznie `scripts/test.sh` (nigdy goły `swift test`); liczba testów rośnie o liczbę nowych `@Test`.
- Nowe pola w zapisywanych typach tylko opcjonalne (lekcja E6). Stary `meta.json` bez pola ma się czytać bez zmian.
- Mutacja każdej bramki: wprowadź → test ma paść → `git checkout <plik>` (plik musi być wcześniej zacommitowany).
- Nigdy `git add -A`/`.`; jawne ścieżki. Commit kończy `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR kończy `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Gałąź `faza201-zmiana-modelu` od `master`; zmiany tylko przez PR, scala użytkownik komendą „scal” (`--merge`, nie squash).
- Interfejs po angielsku, dokumenty po polsku. Nie wchodź shellem do `.devdata/sessions/…`.

## Decyzje wykonawcze (poza specem; do wglądu przy przeglądzie planu)

- **Prompt korekty zostaje z presetu.** Nadpisanie zmienia dostawcę i model, nie `RoleAssignment.prompt`; język korekty i notatki zostaje z presetu nagrania.
- **„Improve transcript” po udanej korekcie:** gdy sesja ma nadpisanie korekty, przycisk jest dostępny także przy gotowym `corrected.json` (bez tego nie da się porównać modeli). Ponowny przebieg nadpisuje `corrected.json`; surowy transkrypt nietknięty (jak dziś przy ponowieniu).
- **Trwający przebieg** zachowuje model wybrany w chwili startu; zmiana wyboru działa od następnego.
- **Model korekty już jest w `corrected.json`** (`CorrectedTranscript.model`, bez zmiany formatu), więc spec §6 nie wymaga nowego pola.
- **Nadpisanie pustego modelu** (`model` puste lub same spacje) jest nieważne, jak pusta rola presetu.

## Przegląd kontrolny (Review Focus)

Każda linia ma test w zadaniu, które ją posiada.

1. Stary `meta.json` bez `modelOverrides` czyta się; `readMeta()` nie rzuca (Z1).
2. Nadpisanie wskazujące usuniętego dostawcę → nieważne, wraca preset, plik pola nie traci wartości; użytkownik dostaje komunikat (Z1 logika, Z2 komunikat).
3. Reset jednej roli zostawia drugą; reset obu usuwa pole z `meta.json` (Z1).
4. Sesja, której preset nie ma roli korekty albo podsumowania: nadpisanie działa (Z1).
5. Nadpisanie z pustym modelem nie wygrywa z presetem (Z1).
6. `thinking` z nadpisania wygrywa z ustawieniem globalnym tylko dla podsumowania; korekta go nie ma (Z1: `SummaryChoice.thinking`, brak pola przy korekcie z konstrukcji typu).
7. Lokalny dostawca + „Thinking”: przełącznik niewidoczny (lokalne zawsze bez myślenia, bez zmian) (Z3, migawka).

---

### Zadanie 1: typy nadpisania i pierwszeństwo w `MeetNotesNotes`

**Pliki:**
- Create: `Sources/MeetNotesNotes/ModelOverrides.swift`
- Modify: `Sources/MeetNotesNotes/NoteTitle.swift` (`NoteMeta`), `Sources/MeetNotesNotes/SummaryModel.swift`
- Test: `Tests/MeetNotesNotesTests/ModelOverridesTests.swift` (nowy), `Tests/MeetNotesNotesTests/SummaryModelTests.swift`

**Interfejsy (produkuje; Z2 i Z3 ich używają):**
```swift
public struct RoleOverride: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    public var thinking: Bool?          // tylko podsumowanie; nil = ustawienie globalne
    public init(providerID: UUID, model: String, thinking: Bool? = nil)
}
public struct ModelOverrides: Codable, Equatable, Sendable {
    public var summary: RoleOverride?
    public var correction: RoleOverride?
    public init(summary: RoleOverride? = nil, correction: RoleOverride? = nil)
    public var isEmpty: Bool
    /// `role` ∈ {.summary, .correction}, inaczej `nil`. Nieważne (→ `nil`): model pusty/same spacje albo `providerID ∉ knownProviders`.
    public func usable(_ role: Role, knownProviders: Set<UUID>) -> RoleOverride?
    public func raw(_ role: Role) -> RoleOverride?     // bez sprawdzania; do pokazania w chipie
    public mutating func set(_ role: Role, _ value: RoleOverride?)
}
extension NoteMeta {                      // NoteMeta.modelOverrides: ModelOverrides? (nowe pole, opcjonalne)
    public mutating func setOverride(_ role: Role, _ value: RoleOverride?)  // wynik pusty → modelOverrides = nil
}
public enum CorrectionModel {
    /// override ważny (już przefiltrowany przez `usable`) wygrywa; `prompt` zawsze z `frozen?.correction?.prompt`.
    /// Inaczej rola korekty presetu z niepustym modelem, inaczej `nil`.
    public static func resolve(frozen: Preset?, override: RoleOverride?) -> RoleAssignment?
}
// SummaryChoice: nowe pola `public var isOverride: Bool = false`, `public var thinking: Bool?`
// SummaryModel.resolve(frozen:override: RoleOverride? = nil, defaultPresetID:presets:) — override (już ważny) → SummaryChoice(isOverride: true, thinking: override.thinking, presetName = nazwa zamrożonego presetu albo "")
```

- [ ] **Krok 1: testy (czerwone)** w `ModelOverridesTests.swift`, wszystkie `@Test`:
  - `oldMetaWithoutOverridesStillDecodes`: JSON `{"manualTitle":"A"}` → `NoteMeta`, `modelOverrides == nil`.
  - `overridesRoundTripThroughMetaJSON`: zapis i odczyt `NoteMeta` z `summary: RoleOverride(providerID: p, model: "m", thinking: false)`.
  - `usableDropsEmptyModelAndUnknownProvider`: model `"  "` → `nil`; `providerID ∉ known` → `nil`; `raw(.summary)` nadal zwraca wartość.
  - `resettingOneRoleKeepsTheOtherAndResettingBothClearsTheField`: `setOverride(.summary, x)`, `setOverride(.correction, y)`, `setOverride(.summary, nil)` → `modelOverrides?.correction == y`; potem `setOverride(.correction, nil)` → `modelOverrides == nil`.
  - `correctionOverrideWinsAndKeepsThePresetPrompt`: preset z `correction: RoleAssignment(providerID: a, model: "old", prompt: "P")`, override `(b, "new")` → `(b, "new", prompt "P")`.
  - `correctionOverrideWorksWhenPresetHasNoCorrection`: preset bez `correction` + override → przypisanie z override, `prompt == nil`; bez override → `nil`.
  - W `SummaryModelTests.swift`: `overrideWinsOverFrozenPresetAndCarriesThinking` (`isOverride == true`, `assignment.model` z override, `thinking == false`, `label == nil`), `overrideWorksWhenNoPresetHasASummary`, `noOverrideKeepsTheOldResult` (istniejące trzy testy zostają zielone bez zmian).
- [ ] **Krok 2: uruchom** `scripts/test.sh` → nowe testy nie kompilują się / padają.
- [ ] **Krok 3: implementacja** wg bloku „Interfejsy”. `NoteMeta` dostaje tylko pole (init bez zmian; nie psuje `CalendarTitleTests`). `ModelOverrides.set` ignoruje role inne niż `.summary`/`.correction`.
- [ ] **Krok 4: uruchom** `scripts/test.sh` → wszystko zielone (oczekiwana liczba: 582 na `master` + 9 nowych `@Test` = 591; sprawdź w wyniku skryptu).
- [ ] **Krok 5: mutacje** (po commicie kroku 6, potem `git checkout`): (a) `usable` bez sprawdzenia `knownProviders`; (b) `setOverride` nie czyści pola, gdy wynik pusty; (c) `CorrectionModel.resolve` bierze `prompt` z override zamiast z presetu — każda ma zawalić dokładnie wskazany test.
- [ ] **Krok 6: commit** `git add Sources/MeetNotesNotes/ModelOverrides.swift Sources/MeetNotesNotes/NoteTitle.swift Sources/MeetNotesNotes/SummaryModel.swift Tests/MeetNotesNotesTests/ModelOverridesTests.swift Tests/MeetNotesNotesTests/SummaryModelTests.swift` → „Nadpisanie modelu sesji: typy, pierwszeństwo, reset”.

---

### Zadanie 2: `NotesModel` używa nadpisania i je zapisuje

**Pliki:**
- Modify: `Sources/MeetNotesApp/NotesModel.swift` (`summaryChoice`, `canRetryCorrection`, `retryCorrection`, `generate`; nowe: `overrides(for:)`, `setOverride`), `Sources/MeetNotesApp/AppModel.swift` (podłączenie `knownProviderIDs`)

**Interfejsy:**
- Konsumuje (Z1): `ModelOverrides.usable`, `NoteMeta.setOverride`, `CorrectionModel.resolve`, `SummaryModel.resolve(frozen:override:…)`.
- Produkuje:
```swift
var knownProviderIDs: () -> Set<UUID> = { [] }                     // podłącza AppModel: Set(providers.providers.map(\.id))
func overrides(for item: SessionItem) -> ModelOverrides            // item.notes.meta.modelOverrides ?? .init()
func presetSummaryChoice(for item: SessionItem) -> SummaryChoice?   // jak summaryChoice, ale bez nadpisania (do „Use preset (<model>)”)
func presetCorrection(for item: SessionItem) -> RoleAssignment?     // CorrectionModel.resolve(frozen: presetFor(item.url), override: nil)
func correctionAssignment(for item: SessionItem) -> RoleAssignment? // z ważnym nadpisaniem
func setOverride(_ role: Role, _ value: RoleOverride?, item: SessionItem)  // updateMeta → report(note) → onChange()
```

- [ ] **Krok 1:** `summaryChoice(for:)` przekazuje `overrides(for:).usable(.summary, knownProviders: knownProviderIDs())` do `SummaryModel.resolve`. `generate` ustawia `generator.thinking = choice.thinking ?? summaryThinking()`.
- [ ] **Krok 2:** `canRetryCorrection` i `retryCorrection` biorą przypisanie z `correctionAssignment(for:)` (zamiast `presetFor(item.url)?.correction`); `canRetryCorrection` dodatkowo zwraca `true` przy ważnym nadpisaniu korekty, gdy reszta strażników przechodzi (decyzja wykonawcza wyżej).
- [ ] **Krok 3:** nadpisanie, które jest, ale nieważne (`raw` ≠ nil, `usable` = nil z powodu nieznanego dostawcy): `generate` i `retryCorrection` wołają `report("The model you chose for this meeting is no longer available. Using the preset's.")` i idą dalej z presetem. Plik nie jest ruszany.
- [ ] **Krok 4:** `setOverride` robi `try NotesStore(session: item.url).updateMeta { $0.setOverride(role, value) }` (komunikat z `updateMeta` → `report`), blokada `isMoving()` jak przy innych zapisach, na końcu `onChange()`. Niczego nie uruchamia.
- [ ] **Krok 5:** `AppModel` (`notes.knownProviderIDs = { … }` obok `notes.presetFor`).
- [ ] **Krok 6: weryfikacja:** `scripts/test.sh` zielony (zadanie nie dodaje testów: logika leży w Z1; app nie ma testTargetu). Ręcznie dopiero w Z3.
- [ ] **Krok 7: commit** (`NotesModel.swift`, `AppModel.swift`) „NotesModel: model z nadpisania sesji, zapis w meta.json”.

---

### Zadanie 3: chip modelu w Summary i Transcript

**Pliki:**
- Create: `Sources/MeetNotesApp/MeetingModelChip.swift`
- Modify: `Sources/MeetNotesApp/MeetingTabs.swift` (`SummaryTab.bar` ok. `Text(c.assignment.model)`, `TranscriptTab` obok „Improve transcript”), `Sources/MeetNotesApp/Snapshots.swift`

**Interfejsy:**
- Konsumuje (Z2): `NotesModel.overrides(for:)`, `presetSummaryChoice(for:)`, `presetCorrection(for:)`, `correctionAssignment(for:)`, `summaryChoice(for:)`, `setOverride(_:_:item:)`; istniejące `ModelPicker`, `FieldMenu`, `RoleProviders.choices`, `OnThisMacBadge`-podobny znacznik z `PresetsView.swift` (użyj istniejącego, nie twórz nowego).
- Produkuje: `struct MeetingModelChip: View { init(role: Role, item: SessionItem) }` (`role` ∈ `.summary`, `.correction`) i `final class MeetingModelChipState: ObservableObject` (`@Published showing`, `providerID: UUID?`, `model: String`).

- [ ] **Krok 1: chip.** Przycisk „Model · <id modelu> ⌄” (jedna linia, skracanie w środku, `lineLimit(1)`), znacznik „On this Mac” dla dostawcy `isLocal`, dopisek „changed” (`mnText2`, nie kolor ostrzeżenia), gdy jest ważne nadpisanie. Popover: (a) wiersz „Use preset (<model presetu>)” — widoczny tylko przy nadpisaniu, woła `setOverride(role, nil, …)`; (b) menu dostawcy z `RoleProviders.choices(providers, role: role, current:)`; (c) `ModelPicker` dla roli; zapis do `meta.json` dopiero gdy `model` niepusty (zmiana dostawcy czyści `model` w stanie lokalnym i niczego nie zapisuje); (d) tylko `.summary` i tylko dostawca nielokalny: przełącznik „Thinking” (wartość: nadpisanie → inaczej `GlobalSettings` przez istniejący odczyt), zapis `thinking` razem z bieżącym dostawcą i modelem.
- [ ] **Krok 2: wpięcie.** Summary: chip zastępuje `Text(c.assignment.model)` w `bar` (ten sam `layoutPriority(1)`); gdy `choice == nil` (żaden preset nie ma modelu podsumowania), chip nadal się pokazuje z „Choose model”, a „Generate notes” działa po wyborze. Transcript: chip stoi tuż przed „Improve transcript” w tej samej linii; widoczny, gdy `item.transcript` ma wypowiedzi (jak dziś przycisk). `help` przycisku: „Run the correction model on this transcript”.
- [ ] **Krok 3: pochodzenie wyniku (spec 6).** Summary: gdy `item.notes.summary.model` ≠ model, który dałby preset (`presetSummaryChoice`), pod paskiem jedna linia `mnText2`: „Made with <model> (preset: <model presetu>)”. Transcript: gdy `item.corrected.model` ≠ `presetCorrection(for:)?.model`, obok „N parts kept as heard” linia „Corrected with <model>”. Obie znikają po zgodności.
- [ ] **Krok 4: migawki** w `Snapshots.swift`: chip domyślny, zmieniony (z „changed”), lokalny (znacznik „On this Mac”, brak „Thinking”), oraz popover otwarty w Summary. Uruchom `scripts/snapshot.sh`, obejrzyj jasny i ciemny; długi id modelu (`deepseek/…-flash`) nie wypycha przycisku „Regenerate”.
- [ ] **Krok 5: odbiór na żywo (użytkownik)** — poza agentem: zmiana modelu w Summary → „Regenerate” używa nowego; restart aplikacji zachowuje wybór; „Use preset” wraca; „Improve transcript” z innym modelem na sesji z gotową korektą.
- [ ] **Krok 6: `scripts/test.sh`** zielony, **commit** (`MeetingModelChip.swift`, `MeetingTabs.swift`, `Snapshots.swift`) „Chip modelu w Summary i Transcript”.

---

### Zadanie 4: dokumenty i zamknięcie

**Pliki:** `docs/superpowers/BACKLOG.md`, `docs/superpowers/ROADMAP.md`, `CLAUDE.md` (sekcja Stan), artefakt „Mapa faz Yascribe”.

- [ ] **Krok 1:** BACKLOG: wpis „zmiana modelu w Summary” → zrobione (z numerem PR); lista „Zostaje” z decyzji wykonawczych, jeśli użytkownik ich nie zmienił. ROADMAP: faza 2.0.1 w sekcji zrobionych. `CLAUDE.md`: jedna linia stanu (faza 2.0.1, liczba testów z `scripts/test.sh`), popraw też liczbę testów po PR #17 (582).
- [ ] **Krok 2:** artefakt (`Artifact read` → edycja kopii w scratchpadzie → publikacja pod `https://claude.ai/artifact/NH8mCRJsz9Y8AxVVBz7bKz`): faza 2.0.1 ze statusami wg commitów i wynik odbioru Z3 kroku 5.
- [ ] **Krok 3:** PR (`gh pr create`), opis z listą zadań i liczbą testów; scala użytkownik.
