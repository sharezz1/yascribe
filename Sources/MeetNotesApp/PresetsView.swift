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
