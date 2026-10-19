# Plan 1.5-B — wybór modelu, Presets i Settings od nowa

> **Dla wykonawców:** najpierw `2026-10-14-faza15-00-przeglad.md` §0 i §3. Znaczniki `[haiku]` / `[sonnet]` / `[opus]` przy krokach = model wykonawcy. Kod ⚠️ (nieskompilowany w repo): błąd kompilacji napraw minimalnie i opisz; inna rozbieżność = STOP.

**Cel:** wspólny `ModelPicker` (wyszukiwarka, lista per rola, licznik zgodny z widoczną listą), ekran Presets z Save/Cancel i etykietami, ekran Settings z Save/Cancel i potwierdzeniem zmiany embeddingu.

**Spec:** `docs/superpowers/specs/2026-10-14-faza15-design.md` §3 (decyzje 7, 8, 12, 13), §5.4, §8 (testy 10); `docs/superpowers/reports/S17-uwagi-uzytkownika.md` pkt 1–6; BACKLOG „D3/odbiór: dwie identyczne nazwy dostawców".

**Wspólne ograniczenia:** przegląd, „Wspólne ograniczenia". Bez `@State`/`#Preview`: stan lokalny widoków przez `ObservableObject` + `@StateObject`.

**Zasada dla widoków (T3, T4):** po napisaniu ekranów dopisz je do `Snapshots.runAll` (T0), uruchom `scripts/snapshot.sh`, obejrzyj PNG (`Read`) **wszystkie naraz** w jasnym i ciemnym trybie, popraw **jedną partią**, potwierdź drugą rundą i **koniec** (macos.md §9: najwyżej dwie rundy). W raporcie napisz, skąd dowód: „migawka" / „lektura kodu". Jeśli T0 skończyło się STOP-em (migawki nie działają), ten krok = odbiór ręczny użytkownika po T4.

---

### Zadanie T3: `ModelPicker` i ekran Presets

Status: ⚠️ nieskompilowane. Logika w bibliotece (`ModelCatalog`, 3 testy); widoki cienkie.

**Pliki:**
- Utwórz: `Sources/MeetNotesProviders/ModelCatalog.swift`, `Sources/MeetNotesApp/ModelPicker.swift`
- Zmień: `Sources/MeetNotesApp/AppModel.swift` (listy modeli), `Sources/MeetNotesApp/PresetsView.swift` (przepisz), `Sources/MeetNotesApp/Snapshots.swift`
- Test: `Tests/MeetNotesProvidersTests/ModelCatalogTests.swift`

**Interfejsy:**
- Konsumuje: `OpenAICompatibleClient.listModels(output:)` (T2), `Preset.languageChoice`, `LanguageChoice`, `Preset.languageLabel` (T1).
- Dostarcza: `ModelCatalog.outputFilter(for: Role) -> String?`, `ModelCatalog.visible(_:role:query:) -> [ModelInfo]`; `AppModel.models(provider:role:) -> [ModelInfo]`, `AppModel.isLoadingModels(provider:role:) -> Bool`, `AppModel.loadModels(provider:role:force:) async`, `AppModel.refreshModels(_:) async` (wszystkie listy); `ModelPicker(providerID:role:selection:)`; `RoleEditor(title:role:assignment:language:promptTitle:promptHint:)`; `PresetEditorState(draft:original:)`, `PresetsView(state:)`.

- [x] **Krok 1 `[sonnet]`: testy `ModelCatalog` (najpierw).** Utwórz `Tests/MeetNotesProvidersTests/ModelCatalogTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesProviders

private let chat = ModelInfo(id: "anthropic/claude-sonnet", inputModalities: ["text", "audio"], outputModalities: ["text"])
private let stt = ModelInfo(id: "microsoft/mai-transcribe-2", inputModalities: ["audio"], outputModalities: ["transcription"])
private let emb = ModelInfo(id: "openai/text-embedding-x", inputModalities: ["text"], outputModalities: ["embeddings"])
private let bare = ModelInfo(id: "llama3") // Ollama: lista bez modalności

@Test func eachRoleSeesOnlyItsOwnKindOfModel() {
    let all = [chat, stt, emb]
    #expect(ModelCatalog.visible(all, role: .asr, query: "").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .embedding, query: "").map(\.id) == [emb.id])
    #expect(ModelCatalog.visible(all, role: .summary, query: "").map(\.id) == [chat.id])
    #expect(ModelCatalog.visible(all, role: .correction, query: "").map(\.id) == [chat.id])
    #expect(ModelCatalog.outputFilter(for: .asr) == "transcription")
    #expect(ModelCatalog.outputFilter(for: .embedding) == "embeddings")
    #expect(ModelCatalog.outputFilter(for: .summary) == nil)
}

@Test func searchMatchesAnyPartOfTheIdIgnoringCase() {
    let all = [chat, stt, emb]
    #expect(ModelCatalog.visible(all, role: .asr, query: "MAI").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .asr, query: "transcribe-2").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .asr, query: "  ").map(\.id) == [stt.id]) // same spacje = brak zapytania
    #expect(ModelCatalog.visible(all, role: .asr, query: "claude").isEmpty)
}

@Test func modelsWithoutModalitiesAreKeptForEveryRole() {
    for role in Role.allCases {
        #expect(ModelCatalog.visible([bare], role: role, query: "").map(\.id) == ["llama3"])
    }
}
```

- [x] **Krok 2 `[haiku]`: czerwone.** `scripts/test.sh` — oczekiwane: błąd kompilacji (`ModelCatalog` nie istnieje).

- [x] **Krok 3 `[sonnet]`: `ModelCatalog`.** Utwórz `Sources/MeetNotesProviders/ModelCatalog.swift`:

```swift
import Foundation

/// Która lista modeli należy do jakiej roli i jak ją zawęzić wyszukiwaniem (spec 1.5 §5.4).
/// STT i embeddingi mają osobne listy modalności; korekta i podsumowanie to modele tekstowe.
public enum ModelCatalog {
    /// Wartość `output_modalities` dla zapytania do `/models`; `nil` = lista domyślna.
    public static func outputFilter(for role: Role) -> String? {
        switch role {
        case .asr: "transcription"
        case .embedding: "embeddings"
        case .correction, .summary: nil
        }
    }

    /// Modele widoczne w pickerze: modalność roli (gdy odpowiedź ją niesie — model bez modalności zostaje)
    /// i fragment `id` bez względu na wielkość liter.
    public static func visible(_ models: [ModelInfo], role: Role, query: String) -> [ModelInfo] {
        let wanted = outputFilter(for: role) ?? "text"
        let q = query.trimmingCharacters(in: .whitespaces)
        return models.filter { m in
            (m.outputModalities.map { $0.contains(wanted) } ?? true)
                && (q.isEmpty || m.id.localizedCaseInsensitiveContains(q))
        }
    }
}
```

- [x] **Krok 4 `[haiku]`: zielone.** `scripts/test.sh` — oczekiwane: `127/127` (124 + 3 nowe `@Test`: `eachRoleSeesOnlyItsOwnKindOfModel`, `searchMatchesAnyPartOfTheIdIgnoringCase`, `modelsWithoutModalitiesAreKeptForEveryRole`).

- [x] **Krok 5 `[haiku]`: mutacja (rozdział list).** W `ModelCatalog.visible` zamień `(m.outputModalities.map { $0.contains(wanted) } ?? true)` na `true`. Przepis §0.5: `scripts/test.sh --filter eachRoleSeesOnlyItsOwnKindOfModel` — **pada**; `git checkout Sources/MeetNotesProviders/ModelCatalog.swift` (po zastage'owaniu zadania); pełne — `127/127`.

- [x] **Krok 6 `[sonnet]`: listy modeli w `AppModel`.** W `Sources/MeetNotesApp/AppModel.swift` usuń `var models: [UUID: [ModelInfo]] = [:]` i dotychczasowe `refreshModels`; przed `@MainActor @Observable final class AppModel` dodaj `struct ModelListKey: Hashable { var provider: UUID; var filter: String }` (`filter == ""` = lista domyślna), a w klasie:

```swift
    var modelLists: [ModelListKey: [ModelInfo]] = [:]
    private(set) var loadingModels: Set<ModelListKey> = []

    private func key(_ provider: UUID, _ role: Role) -> ModelListKey {
        ModelListKey(provider: provider, filter: ModelCatalog.outputFilter(for: role) ?? "")
    }

    func models(provider: UUID, role: Role) -> [ModelInfo] { modelLists[key(provider, role)] ?? [] }
    func isLoadingModels(provider: UUID, role: Role) -> Bool { loadingModels.contains(key(provider, role)) }

    /// Lista modeli dla roli: pobierana raz na dostawcę i rolę (`force` = odśwież).
    func loadModels(provider: UUID, role: Role, force: Bool = false) async {
        let k = key(provider, role)
        guard force || modelLists[k] == nil, !loadingModels.contains(k), let c = client(for: provider) else { return }
        loadingModels.insert(k)
        defer { loadingModels.remove(k) }
        do { modelLists[k] = try await c.listModels(output: ModelCatalog.outputFilter(for: role)) } catch {
            lastError = "Couldn't load models: \(error)"
        }
    }

    /// Przycisk „Refresh Models" w Settings: transkrypcja, embeddingi i lista tekstowa.
    func refreshModels(_ id: UUID) async {
        for role in [Role.asr, .embedding, .summary] { await loadModels(provider: id, role: role, force: true) }
    }
```

- [x] **Krok 7 `[sonnet]`: `ModelPicker`.** Utwórz `Sources/MeetNotesApp/ModelPicker.swift`:

```swift
import MeetNotesProviders
import SwiftUI

final class ModelPickerState: ObservableObject {
    @Published var showing = false
    @Published var query = ""
}

/// Przycisk z nazwą modelu → popover z wyszukiwarką i listą dla roli (spec 1.5 §5.4).
/// Licznik pokazuje to, co widać; model spoza listy (np. wpisany z ręki) wybiera się wierszem „Use …".
struct ModelPicker: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = ModelPickerState()
    let providerID: UUID
    let role: Role
    @Binding var selection: String

    private var all: [ModelInfo] { model.models(provider: providerID, role: role) }
    private var visible: [ModelInfo] { ModelCatalog.visible(all, role: role, query: state.query) }
    private var kindName: String {
        switch role {
        case .asr: "transcription"
        case .embedding: "embedding"
        case .correction, .summary: "text"
        }
    }
    /// Wpisany identyfikator, którego nie ma na liście.
    private var typed: String? {
        let q = state.query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || all.contains { $0.id == q } ? nil : q
    }

    var body: some View {
        Button {
            state.query = ""
            state.showing = true
            Task { await model.loadModels(provider: providerID, role: role) }
        } label: {
            HStack(spacing: 6) {
                Text(selection.isEmpty ? "Choose model" : selection).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
        }
        .popover(isPresented: $state.showing, arrowEdge: .bottom) { content }
        .help("Search and choose a model")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search models", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let typed { pick(typed) } }
            if model.isLoadingModels(provider: providerID, role: role) && all.isEmpty {
                ProgressView("Loading models…")
            } else {
                Text("\(visible.count) of \(all.count) \(kindName) models").font(.caption).foregroundStyle(.secondary)
            }
            List(visible, id: \.id) { m in
                Button { pick(m.id) } label: {
                    HStack {
                        Text(m.id)
                        Spacer()
                        if m.id == selection { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 200)
            if let typed { Button("Use “\(typed)”") { pick(typed) } }
        }
        .padding(12)
        .frame(width: 380, height: 380)
    }

    private func pick(_ id: String) {
        selection = id
        state.showing = false
    }
}
```

- [x] **Krok 8 `[sonnet]`: ekran Presets.** Zastąp całą zawartość `Sources/MeetNotesApp/PresetsView.swift`:

```swift
import MeetNotesProviders
import SwiftUI

final class PresetEditorState: ObservableObject {
    @Published var draft: Preset?
    /// Zapisana wersja edytowanego presetu; `nil` = nowy, jeszcze niezapisany.
    @Published var original: Preset?
    @Published var error: String?

    init(draft: Preset? = nil, original: Preset? = nil) {
        self.draft = draft
        self.original = original
    }

    var isNew: Bool { draft != nil && original == nil }
    var isDirty: Bool { draft != nil && draft != original }

    func select(_ p: Preset?) { draft = p; original = p; error = nil }
    func startNew() { draft = Preset(name: "New preset", language: nil, asr: nil); original = nil; error = nil }
    func cancel() { draft = original; error = nil }
}

/// Presety (spec fazy 1, §1.5; spec 1.5 §5.4): język i modele jako jeden byt. Edycja na szkicu: Save / Cancel.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: PresetEditorState

    init(state: PresetEditorState = PresetEditorState()) { _state = StateObject(wrappedValue: state) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { state.draft?.id }, set: { id in
                    guard !state.isDirty else { return } // nie gub niezapisanych zmian
                    state.select(model.presets.presets.first { $0.id == id })
                })) {
                    if state.isNew, let d = state.draft {
                        PresetRow(title: d.name.isEmpty ? "New preset…" : d.name, subtitle: "Unsaved").tag(d.id)
                    }
                    ForEach(model.presets.presets) { p in
                        PresetRow(title: p.name, subtitle: "\(p.languageLabel) · \(p.asr?.model ?? "No speech-to-text model")").tag(p.id)
                    }
                }
                if state.isDirty {
                    Text("Save or cancel your changes to switch presets.")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300, maxHeight: .infinity)
            Group {
                if state.draft != nil {
                    PresetForm(state: state)
                } else {
                    ContentUnavailableView("Choose a preset", systemImage: "slider.horizontal.3",
                                           description: Text("A preset ties a language to its models, so they can't drift apart."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button { state.startNew() } label: { Label("New Preset", systemImage: "plus") }
                    .help("New preset")
                    .disabled(state.isDirty)
            }
        }
        .navigationTitle("Presets")
    }
}

struct PresetRow: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PresetForm: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: PresetEditorState

    private var draft: Binding<Preset> {
        Binding(get: { state.draft ?? Preset(name: "", language: nil, asr: nil) }, set: { state.draft = $0 })
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                TextField("Name", text: draft.name)
                // 🔴 Bez wartości domyślnej (P7). „Auto" to opcja awaryjna na końcu listy, z ostrzeżeniem.
                Picker("Language", selection: draft.languageChoice) {
                    Text("Choose…").tag(LanguageChoice.unset)
                    ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                    Divider()
                    Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                }
                if draft.wrappedValue.isAutoLanguage {
                    Label("Lower quality, risk of invented text. Use Auto only for meetings that mix languages.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            RoleEditor(title: "Speech to text", role: .asr, assignment: draft.asr, language: draft.wrappedValue.language)
            RoleEditor(title: "Correction (optional)", role: .correction, assignment: draft.correction, language: nil,
                       promptTitle: "Extra instructions (optional)",
                       promptHint: "Added to the correction prompt, e.g. “Keep product names unchanged.”")
            RoleEditor(title: "Summary and titles", role: .summary, assignment: draft.summary, language: nil)
            SwiftUI.Section {
                Picker("Notes language", selection: draft.notesLanguage) {
                    Text("Same as preset").tag(LanguageCode?.none)
                    ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
                }
                if draft.wrappedValue.isAutoLanguage && draft.wrappedValue.notesLanguage == nil {
                    Text("With Auto, notes are written in the language that predominates in the transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Embeddings are set once for the whole archive in Settings.").font(.caption).foregroundStyle(.secondary)
            }
            if let e = state.error { Text(e).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { state.cancel() }
                    .disabled(!state.isDirty)
                Button("Save") {
                    state.error = state.draft.flatMap { model.savePreset($0) }
                    if state.error == nil { state.original = state.draft }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!state.isDirty)
            }
        }
        .formStyle(.grouped)
    }
}

/// Dostawca + model z wyszukiwarką + wynik sondy (+ własne instrukcje tylko tam, gdzie mają sens).
struct RoleEditor: View {
    @Environment(AppModel.self) private var model
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var promptTitle: String?
    var promptHint: String?

    var body: some View {
        SwiftUI.Section(title) {
            Picker("Provider", selection: Binding(get: { assignment?.providerID }, set: { id in
                assignment = id.map { RoleAssignment(providerID: $0, model: assignment?.model ?? "", prompt: assignment?.prompt) }
            })) {
                Text("None").tag(UUID?.none)
                ForEach(model.providers.providers) { p in Text(p.name).tag(Optional(p.id)) }
            }
            if let a = assignment {
                LabeledContent("Model") {
                    ModelPicker(providerID: a.providerID, role: role,
                                selection: Binding(get: { assignment?.model ?? "" }, set: { assignment?.model = $0 }))
                }
                HStack {
                    // `language` jest ustawiony tylko dla roli ASR — dla pozostałych to nil, jak przy zapisie.
                    ProbeBadges(result: model.probeCache.result(provider: a.providerID, model: a.model, role: role, language: language))
                    Spacer()
                    Button("Test") { Task { await model.probe(providerID: a.providerID, model: a.model, role: role, language: language) } }
                        .disabled(a.model.isEmpty)
                        .help("Sends a short test request to check this model works in this role")
                }
                if let promptTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(promptTitle).font(.callout)
                        TextEditor(text: Binding(get: { a.prompt ?? "" }, set: { assignment?.prompt = $0 }))
                            .frame(minHeight: 60)
                            .font(.body)
                        if let promptHint { Text(promptHint).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}

/// Wynik sondy jako znaczniki, nie przypis drobnym drukiem (spec fazy 1, §9).
struct ProbeBadges: View {
    let result: ProbeResult?

    var body: some View {
        HStack(spacing: 6) {
            if let r = result {
                if r.works {
                    Label("Verified", systemImage: "checkmark.seal")
                    switch r.languageHandling {
                    case .enforced: Label("Language enforced", systemImage: "lock")
                    case .automatic:
                        Label("This model detects language itself — your language setting can't be enforced",
                              systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    case .filtered: Label("Language filtered", systemImage: "line.3.horizontal.decrease")
                    case .unknown: Label("Language handling unknown", systemImage: "questionmark.circle").foregroundStyle(.orange)
                    case nil: EmptyView()
                    }
                    if r.shape == .chatAudio { Text("No word timings").foregroundStyle(.secondary) }
                } else {
                    Label("Doesn't work in this role", systemImage: "xmark.octagon").foregroundStyle(.red).help(r.failure ?? "")
                }
            } else {
                Text("Not tested").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
```

W `SettingsView.swift` zmiany wywołania `RoleEditor(... hasPrompt …)` i `model.models[...]` robi T4 — **w T3 dopasuj tylko tyle, żeby się kompilowało:** w `SettingsView` wywołanie `RoleEditor(title: "Embeddings (whole archive)", role: .embedding, assignment: $model.settings.embedding, language: nil)` działa bez zmian (nowe parametry mają wartości domyślne).

- [x] **Krok 9 `[haiku]`: kompilacja i testy.** `scripts/test.sh` — oczekiwane: `127/127`. (Ten krok kompiluje też cel `MeetNotesApp`; błąd kompilacji widoków → napraw minimalnie, opisz w raporcie.)

- [x] **Krok 10 `[sonnet]`: migawki i jedna partia poprawek.** Dopisz w `Snapshots.runAll` po istniejących ekranach:

```swift
            let editing = PresetEditorState()
            editing.select(model.presets.presets.first)
            for dark in [false, true] {
                try render("presets-editing", size: CGSize(width: 900, height: 640), dark: dark, model: model) { PresetsView(state: editing) }
            }
```
Uruchom `scripts/snapshot.sh`, obejrzyj `presets-light.png`, `presets-dark.png`, `presets-editing-*.png`. Sprawdź: (a) lista z jednym presetem nie jest białym blokiem w połowie wysokości, (b) formularz ma etykiety pól, pole „Extra instructions" ma podpis i podpowiedź, (c) Save/Cancel na dole, (d) kontrast w ciemnym. Popraw jedną partią; druga runda tylko potwierdza.

- [x] **Krok 11 `[sonnet]`: commit.**

```bash
git add Package.swift Sources Tests scripts Resources docs .gitignore
git commit -m "T3: ModelPicker (wyszukiwarka, lista per rola) i nowy ekran Presets (Save/Cancel, Auto, etykiety)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Zadanie T4: ekran Settings

Status: ⚠️ nieskompilowane. Logika w bibliotece (3 testy).

**Reguła granicy Save/Cancel (decyzja planu):** **dostawcy są zapisywani od razu** — dodanie ma własny arkusz z Add/Cancel, usunięcie jest natychmiastowe (klucz ląduje w pęku kluczy albo jest z niego usuwany w tej samej chwili). **Save/Cancel obejmuje tylko sekcję „Archive" (embedding).** Napis w interfejsie to mówi. Dzięki temu Cancel nigdy nie zostawia klucza w pęku bez dostawcy na liście.

> ✏️ **2026-10-15:** arkusz z kroków niżej (i kafelki z odbioru T13, uwaga 7, commit `36db9a6`) zastąpiło dodawanie
> w miejscu w karcie Providers — wiersz „Add: OpenRouter · Ollama · Custom…” (`docs/design/macos.md` §11.5, spec §5.4).
> Reguła granicy Save/Cancel bez zmian: dostawca zapisuje się od razu, przyciskiem „Save & verify” w rozwiniętym wierszu.
> Kod w krokach poniżej to stan historyczny.

**Pliki:**
- Zmień: `Sources/MeetNotesProviders/Preset.swift` (`GlobalSettings`), `Sources/MeetNotesProviders/Stores.swift` (`ProvidersFile`), `Sources/MeetNotesProviders/SecretStore.swift` (`KeyStatus`), `Sources/MeetNotesApp/AppModel.swift` (`addProvider`), `Sources/MeetNotesApp/SettingsView.swift` (przepisz), `Sources/MeetNotesApp/Snapshots.swift`
- Test: `Tests/MeetNotesProvidersTests/SettingsLogicTests.swift`

**Interfejsy:**
- Dostarcza: `GlobalSettings.embeddingChangeNeedsConfirmation(old:new:) -> Bool`, `ProvidersFile.nameError(_:) -> String?`, `KeyStatus` (`.set(String)`, `.missing`, `.unreadable(String)`; `KeyStatus.of(_ read: () throws -> String?)`), `AppModel.addProvider(name:baseURL:key:) -> String?` (nil = dodano).

- [x] **Krok 1 `[sonnet]`: testy.** Utwórz `Tests/MeetNotesProvidersTests/SettingsLogicTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesProviders

@Test func embeddingChangeAsksOnlyWhenOneWasAlreadySet() {
    let a = RoleAssignment(providerID: UUID(), model: "emb-a")
    let b = RoleAssignment(providerID: a.providerID, model: "emb-b")
    #expect(!GlobalSettings.embeddingChangeNeedsConfirmation(old: nil, new: a)) // pierwsze ustawienie — bez pytania
    #expect(!GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: a))
    #expect(GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: b))
    #expect(GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: nil))
}

@Test func duplicateProviderNamesAreRejected() {
    let file = ProvidersFile(providers: [openRouter])
    #expect(file.nameError("openrouter ") != nil) // ta sama nazwa, inna wielkość liter i spacja
    #expect(file.nameError("Ollama") == nil)
    #expect(file.nameError("  ") != nil)
}

@Test func keychainFailureIsNotShownAsNoKey() {
    struct Boom: Error {}
    #expect(KeyStatus.of { "test-fake-abcd1234" } == .set("••••1234")) // fałszywy klucz testowy, nie prawdziwy
    #expect(KeyStatus.of { nil } == .missing)
    if case .unreadable = KeyStatus.of({ throw Boom() }) {} else { Issue.record("oczekiwano .unreadable") }
}
```

- [x] **Krok 2 `[haiku]`: czerwone.** `scripts/test.sh` — oczekiwane: błąd kompilacji (brak `embeddingChangeNeedsConfirmation`, `nameError`, `KeyStatus`).

- [x] **Krok 3 `[sonnet]`: logika.** W `Preset.swift` w `GlobalSettings` dodaj:

```swift
    /// Zmiana modelu embeddingu przeindeksuje całe archiwum (P13) — pytamy tylko, gdy jakiś model już był.
    public static func embeddingChangeNeedsConfirmation(old: RoleAssignment?, new: RoleAssignment?) -> Bool {
        guard let old else { return false }
        return old.providerID != new?.providerID || old.model != new?.model
    }
```
W `Stores.swift` w `ProvidersFile` dodaj:

```swift
    /// Powód odmowy dla nazwy nowego dostawcy; `nil` = można dodać. Nazwy muszą się różnić, żeby komunikaty
    /// („No API key for <nazwa>…") wskazywały jednego dostawcę.
    public func nameError(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give the provider a name." }
        if providers.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(n) == .orderedSame }) {
            return "A provider named “\(n)” already exists."
        }
        return nil
    }
```
W `SecretStore.swift` dopisz na końcu:

```swift
/// Stan klucza dostawcy dla interfejsu. Błąd pęku kluczy to NIE „brak klucza" — inaczej użytkownik
/// dodałby dostawcę ponownie albo wpisał klucz nad działającym (S18 §2.4).
public enum KeyStatus: Equatable, Sendable {
    case set(String)        // zamaskowany klucz
    case missing
    case unreadable(String) // opis błędu

    public static func of(_ read: () throws -> String?) -> KeyStatus {
        do { return try read().map { .set(maskedKey($0)) } ?? .missing } catch { return .unreadable("\(error)") }
    }
}
```

- [x] **Krok 4 `[haiku]`: zielone.** `scripts/test.sh` — oczekiwane: `130/130` (127 + 3 nowe `@Test`: `embeddingChangeAsksOnlyWhenOneWasAlreadySet`, `duplicateProviderNamesAreRejected`, `keychainFailureIsNotShownAsNoKey`).

- [x] **Krok 5 `[haiku]`: mutacje (duplikat nazwy i predykat embeddingu).** (a) W `nameError` zamień `caseInsensitiveCompare(n) == .orderedSame` na `== n` (rozróżnia wielkość liter). Przepis §0.5: `scripts/test.sh --filter duplicateProviderNamesAreRejected` — **pada**; `git checkout Sources/MeetNotesProviders/Stores.swift`. (b) W `embeddingChangeNeedsConfirmation` zamień `guard let old else { return false }` na `guard let old else { return true }`. `scripts/test.sh --filter embeddingChangeAsksOnlyWhenOneWasAlreadySet` — **pada**; `git checkout Sources/MeetNotesProviders/Preset.swift`. Pełne — `130/130`.

- [x] **Krok 6 `[sonnet]`: `addProvider` w `AppModel`.** Zastąp istniejące `addProvider`:

```swift
    /// `nil` = dodano; tekst = powód odmowy (duplikat nazwy albo błąd pęku kluczy).
    func addProvider(name: String, baseURL: URL, key: String) -> String? {
        if let e = providers.nameError(name) { return e }
        let p = Provider(name: name.trimmingCharacters(in: .whitespaces), baseURL: baseURL)
        do {
            if !key.isEmpty { try secrets.set(p.id, key) }
            providers.providers.append(p)
            save()
            return nil
        } catch {
            return "Couldn't store the key in Keychain: \(error)"
        }
    }
```

- [x] **Krok 7 `[sonnet]`: ekran Settings.** Zastąp całą zawartość `Sources/MeetNotesApp/SettingsView.swift`:

```swift
import MeetNotesProviders
import SwiftUI

final class AddProviderState: ObservableObject {
    @Published var showing = false
    @Published var name = "OpenRouter"
    @Published var url = "https://openrouter.ai/api/v1"
    @Published var key = ""
    @Published var error: String?

    func reset() { name = "OpenRouter"; url = "https://openrouter.ai/api/v1"; key = ""; error = nil }
}

/// Szkic sekcji „Archive": Save / Cancel obejmuje tylko ją; dostawcy zapisują się od razu (plan 1.5-B, T4).
final class SettingsDraft: ObservableObject {
    @Published var embedding: RoleAssignment?
    @Published var confirming = false
    @Published var saved = false

    func load(_ s: GlobalSettings) { embedding = s.embedding; saved = false }
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5). Modele STT, korekty
/// i podsumowania wybiera się w presecie.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var add = AddProviderState()
    @StateObject private var draft = SettingsDraft()

    private var isDirty: Bool { draft.embedding != model.settings.embedding }

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(model.providers.providers) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(p.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                            keyLabel(p)
                        }
                        Spacer()
                        Button { Task { await model.refreshModels(p.id) } } label: { Label("Refresh Models", systemImage: "arrow.clockwise") }
                            .help("Refresh the model lists")
                        Button(role: .destructive) { model.removeProvider(p.id) } label: { Label("Remove", systemImage: "trash") }
                            .help("Remove this provider and its key")
                    }
                }
                Button("Add Provider…") { add.reset(); add.showing = true }
            } header: {
                Text("Providers")
            } footer: {
                Text("Providers are saved as soon as you add or remove them.").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                RoleEditor(title: "Embeddings (whole archive)", role: .embedding, assignment: $draft.embedding, language: nil)
                Text("Changing the embedding model re-indexes the whole archive, never part of it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if draft.saved && !isDirty { Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Cancel") { draft.load(model.settings) }.disabled(!isDirty)
                    Button("Save") { save() }.keyboardShortcut("s", modifiers: .command).disabled(!isDirty)
                }
            } header: {
                Text("Archive")
            }
            SwiftUI.Section("Models for meetings") {
                Text("Speech-to-text, correction and summary models are chosen in each preset.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Presets") { model.section = .presets }
            }
            SwiftUI.Section("Setup") {
                Button("Check Permissions…") { model.showSetup = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { draft.load(model.settings) }
        .confirmationDialog("Change the embedding model?", isPresented: $draft.confirming) {
            Button("Change Model", role: .destructive) { commit() }
            Button("Keep Current Model", role: .cancel) {}
        } message: {
            Text("Changing the embedding model means the whole archive will be re-indexed when archive search arrives. Change it?")
        }
        .sheet(isPresented: $add.showing) { addSheet }
    }

    private func save() {
        if GlobalSettings.embeddingChangeNeedsConfirmation(old: model.settings.embedding, new: draft.embedding) {
            draft.confirming = true
        } else {
            commit()
        }
    }

    private func commit() {
        model.settings.embedding = draft.embedding
        model.save()
        draft.saved = true
    }

    @ViewBuilder private func keyLabel(_ p: Provider) -> some View {
        switch KeyStatus.of({ try model.secrets.get(p.id) }) {
        case .set(let masked): Text(masked).font(.caption.monospaced()).foregroundStyle(.secondary)
        case .missing: Text("No key").font(.caption).foregroundStyle(.secondary)
        case .unreadable(let why):
            Label("Couldn't read the key from Keychain", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).help(why)
        }
    }

    private var addSheet: some View {
        Form {
            TextField("Name", text: $add.name)
            TextField("Base URL", text: $add.url)
            SecureField("API key", text: $add.key)
            if let e = add.error { Text(e).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancel") { add.showing = false }
                Spacer()
                Button("Add") {
                    guard let u = URL(string: add.url), ["http", "https"].contains(u.scheme), u.host() != nil else {
                        add.error = "Enter a full address, e.g. https://openrouter.ai/api/v1."
                        return
                    }
                    if let e = model.addProvider(name: add.name, baseURL: u, key: add.key) {
                        add.error = e
                    } else {
                        add.reset()
                        add.showing = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
```
(`model.save()` zostaje wywoływane przez `commit()` i przez operacje na dostawcach; usunięty jest autozapis przy każdej zmianie `onChange`.)

- [x] **Krok 8 `[haiku]`: kompilacja i testy.** `scripts/test.sh` — oczekiwane: `130/130`.

- [x] **Krok 9 `[sonnet]`: migawki i jedna partia poprawek.** Dopisz w `Snapshots.runAll` ekran `settings` (jasny/ciemny): `try render("settings", size: CGSize(width: 900, height: 640), dark: dark, model: model) { SettingsView() }`. Obejrzyj; sprawdź: tekst o modelach w presecie z przyciskiem „Open Presets", brak „Save" w sekcji Providers, Save/Cancel pod „Archive", brak przewijanego natywnego menu modeli (zastąpione pickerem).

- [x] **Krok 10 `[haiku]`: BACKLOG.** W `docs/superpowers/BACKLOG.md` oznacz `- [x]` pozycję „D3/odbiór: dwie identyczne nazwy dostawców dozwolone" z adnotacją „zrobione w T4 (`nameError`)". Nie zmieniaj innych pozycji.

- [x] **Krok 11 `[sonnet]`: commit.**

```bash
git add Package.swift Sources Tests scripts Resources docs .gitignore
git commit -m "T4: Settings z Save/Cancel dla embeddingu, potwierdzenie zmiany, blokada duplikatu dostawcy, KeyStatus" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
