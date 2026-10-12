import MeetNotesProviders
import SwiftUI

final class PresetEditorState: ObservableObject {
    @Published var draft: Preset?
    @Published var error: String?
}

/// Presety (spec fazy 1, §1.5): język i modele jako jeden byt.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = PresetEditorState()

    var body: some View {
        HSplitView {
            List(model.presets.presets, selection: Binding(get: { state.draft?.id }, set: { id in
                state.draft = model.presets.presets.first { $0.id == id }
                state.error = nil
            })) { p in
                VStack(alignment: .leading) {
                    Text(p.name)
                    Text(p.asr?.model ?? "No speech-to-text model").font(.caption).foregroundStyle(.secondary)
                }
                .tag(p.id)
            }
            .frame(minWidth: 180, idealWidth: 200)
            .toolbar {
                Button { state.draft = Preset(name: "New preset", language: nil, asr: nil); state.error = nil } label: {
                    Label("New Preset", systemImage: "plus")
                }
                .help("New preset")
            }
            if state.draft != nil {
                PresetForm(state: state)
            } else {
                ContentUnavailableView("Choose a preset", systemImage: "slider.horizontal.3",
                                       description: Text("A preset ties a language to its models, so they can't drift apart."))
            }
        }
        .navigationTitle("Presets")
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
            TextField("Name", text: draft.name)
            // 🔴 Bez wartości domyślnej i bez „Automatic" — P7.
            Picker("Language", selection: draft.language) {
                Text("Choose…").tag(LanguageCode?.none)
                ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
            }
            RoleEditor(title: "Speech to text", role: .asr, assignment: draft.asr, language: draft.wrappedValue.language)
            RoleEditor(title: "Correction", role: .correction, assignment: draft.correction, language: nil, hasPrompt: true)
            RoleEditor(title: "Summary", role: .summary, assignment: draft.summary, language: nil, hasPrompt: true)
            Picker("Notes language", selection: draft.notesLanguage) {
                Text("Same as preset").tag(LanguageCode?.none)
                ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
            }
            Text("Embeddings are set once for the whole archive in Settings.").font(.caption).foregroundStyle(.secondary)
            if let e = state.error { Text(e).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Save") { state.error = state.draft.flatMap { model.savePreset($0) } }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
    }
}

/// Dostawca + model (z listy albo wpisany z ręki — §4.3) + wynik sondy.
struct RoleEditor: View {
    @Environment(AppModel.self) private var model
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var hasPrompt = false

    var body: some View {
        SwiftUI.Section(title) {
            Picker("Provider", selection: Binding(get: { assignment?.providerID }, set: { id in
                assignment = id.map { RoleAssignment(providerID: $0, model: assignment?.model ?? "", prompt: assignment?.prompt) }
            })) {
                Text("None").tag(UUID?.none)
                ForEach(model.providers.providers) { p in Text(p.name).tag(Optional(p.id)) }
            }
            if let a = assignment {
                // Lista to wygoda; wpisanie z ręki jest wymagane — mai-transcribe-2 nie jest na liście.
                TextField("Model", text: Binding(get: { a.model }, set: { assignment?.model = $0 }), prompt: Text("microsoft/mai-transcribe-2"))
                if let all = model.models[a.providerID], !all.isEmpty {
                    // Filtr wstępny po modalnościach (spec fazy 1, §4, krok 2): zawęża, nie rozstrzyga —
                    // rozstrzyga sonda. Model transkrypcyjny i tak nie jest na liście (wpisanie z ręki).
                    let audio = all.filter { $0.inputModalities?.contains("audio") == true }
                    let list = role == .asr && !audio.isEmpty ? audio : all
                    Menu("Choose from \(list.count) models") {
                        ForEach(list.prefix(300), id: \.id) { m in Button(m.id) { assignment?.model = m.id } }
                    }
                }
                HStack {
                    ProbeBadges(result: model.probeCache.result(provider: a.providerID, model: a.model, role: role))
                    Spacer()
                    Button("Test") { Task { await model.probe(providerID: a.providerID, model: a.model, role: role, language: language) } }
                        .disabled(a.model.isEmpty)
                        .help("Sends a short test request to check this model works in this role")
                }
                if hasPrompt {
                    TextEditor(text: Binding(get: { a.prompt ?? "" }, set: { assignment?.prompt = $0 }))
                        .frame(minHeight: 60)
                        .font(.body.monospaced())
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
