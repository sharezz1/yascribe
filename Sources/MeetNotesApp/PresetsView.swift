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

/// Presety (spec fazy 1, §1.5; spec 1.5 §5.4; macos.md §11.5): lista 196 pt + edytor obok, pasek Save/Cancel na dole.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: PresetEditorState

    init(state: PresetEditorState = PresetEditorState()) { _state = StateObject(wrappedValue: state) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PageTitle("Presets")
                        Spacer()
                        Button { state.startNew() } label: { Label("New preset", systemImage: "plus") }
                            .buttonStyle(.pill)
                            .disabled(state.isDirty)
                            .help("New preset")
                    }
                    .padding(.bottom, 18)
                    HStack(alignment: .top, spacing: 18) {
                        list.frame(width: 196)
                        Group {
                            if state.draft != nil {
                                PresetForm(state: state)
                            } else {
                                ContentUnavailableView("Choose a preset", systemImage: "slider.horizontal.3",
                                                       description: Text("A preset ties a language to its models, so they can't drift apart."))
                                    .padding(.top, 40)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .contentColumn(700)
            }
            if state.draft != nil {
                EditorFooter(dirty: state.isDirty, error: state.error) {
                    Button("Cancel") { state.cancel() }.buttonStyle(.pill).disabled(!state.isDirty)
                    Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut("s", modifiers: .command).disabled(!state.isDirty)
                }
            }
        }
        .contentBackground()
        .navigationTitle("Presets")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.isNew, let d = state.draft {
                PresetRow(title: d.name.isEmpty ? "New preset" : d.name, subtitle: "unsaved", selected: true, dim: true)
            }
            ForEach(model.presets.presets) { p in
                Button {
                    guard !state.isDirty else { return } // nie gub niezapisanych zmian
                    state.select(p)
                } label: {
                    PresetRow(title: p.name, subtitle: meta(p), selected: state.draft?.id == p.id)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state.draft?.id == p.id ? .isSelected : [])
            }
            if state.isDirty {
                Text("Save or cancel your changes to switch presets.")
                    .font(.system(size: 11)).foregroundStyle(.mnText2).padding(.horizontal, 10).padding(.top, 8)
            }
        }
    }

    private func meta(_ p: Preset) -> String {
        var parts = [p.languageLabel, p.asr.map { $0.model.split(separator: "/").last.map(String.init) ?? $0.model } ?? "No speech-to-text model"]
        if p.id == model.settings.defaultPresetID { parts.append("default") }
        return parts.joined(separator: " · ")
    }

    private func save() {
        state.error = state.draft.flatMap { model.savePreset($0) }
        if state.error == nil { state.original = state.draft }
    }
}

/// Wiersz listy presetów i szablonów: nazwa 13 Medium + metadane 11 pt `text2`; zaznaczenie `selection`, promień 8, bez białego bloku.
struct PresetRow: View {
    let title: String
    let subtitle: String
    var selected = false
    var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(dim ? .mnText2 : .mnText).lineLimit(1)
            Text(subtitle).font(.system(size: 11)).italic(dim).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.mnSelection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Pasek na dole edytora (sticky): stan po lewej, przyciski po prawej. Tło `background`, linia `line2` u góry.
struct EditorFooter<Buttons: View>: View {
    let dirty: Bool
    var error: String?
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(spacing: 8) {
            if let error {
                StateLabel(.bad, error)
            } else if dirty {
                HStack(spacing: 6) {
                    Circle().fill(.mnText2).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("Unsaved changes").foregroundStyle(.mnText2)
                }
            }
            Spacer(minLength: 12)
            buttons
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(.mnBackground)
        .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
    }
}

/// Pole nazwy (15 Medium) w stylu pola z §11.3: tło `field`, obwódka 0,5 pt, promień 7.
struct EditorNameField: View {
    let placeholder: String
    @Binding var text: String
    /// Tylko do odczytu (szablon wbudowany): zwykły tekst w tym samym polu, bez wyszarzenia jak placeholder.
    var readOnly = false
    var body: some View {
        Group {
            if readOnly { Text(text).frame(maxWidth: .infinity, alignment: .leading) } else { TextField(placeholder, text: $text).textFieldStyle(.plain) }
        }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
    }
}

/// Wieloliniowe pole tekstowe (prompt korekty, instrukcje szablonu): `field`, obwódka 0,5 pt, promień 7.
struct EditorPromptField: View {
    @Binding var text: String
    var minHeight: CGFloat = 58
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(minHeight: minHeight)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
    }
}

struct PresetForm: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: PresetEditorState

    private var draft: Binding<Preset> {
        Binding(get: { state.draft ?? Preset(name: "", language: nil, asr: nil) }, set: { state.draft = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EditorNameField(placeholder: "Name", text: draft.name)
                if state.draft?.id == model.settings.defaultPresetID {
                    Text("Default preset").font(.system(size: 12)).foregroundStyle(.mnText2)
                }
            }
            RoleSection(title: "Speech to text", role: .asr, assignment: draft.asr, language: draft.wrappedValue.language, extraBeforeProbe: true) {
                // 🔴 Bez wartości domyślnej (P7). „Auto" to opcja awaryjna na końcu listy, z ostrzeżeniem.
                FormRow(label: "Language") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Language", selection: draft.languageChoice) {
                            Text("Choose…").tag(LanguageChoice.unset)
                            ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                            Divider()
                            Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                        }
                        .labelsHidden().fixedSize()
                        if draft.wrappedValue.isAutoLanguage {
                            WarnLabel("Lower quality, risk of invented text. Use Auto only for meetings that mix languages.")
                        }
                    }
                }
            }
            RoleSection(title: "Correction", role: .correction, assignment: draft.correction, language: nil,
                        promptTitle: "Extra instructions",
                        promptHint: "Added to the correction prompt, e.g. “Keep product names unchanged.”") { EmptyView() }
            RoleSection(title: "Summary", role: .summary, assignment: draft.summary, language: nil) {
                FormRow(label: "Notes language",
                        caption: draft.wrappedValue.isAutoLanguage && draft.wrappedValue.notesLanguage == nil
                            ? "With Auto, notes are written in the language that predominates in the transcript." : nil) {
                    Picker("Notes language", selection: draft.notesLanguage) {
                        Text("Same as preset").tag(LanguageCode?.none)
                        ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Text("Embeddings are set once for the whole archive in Settings.")
                .font(.system(size: 11)).foregroundStyle(.mnText2).padding(.top, 14).padding(.leading, 2)
        }
    }
}

/// Ostrzeżenie: ikona + słowa w `warn` (nigdy sam kolor).
struct WarnLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 10, weight: .bold))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.mnWarn)
        .accessibilityElement(children: .combine)
    }
}

/// Dostawca + model z wyszukiwarką + wynik sondy (+ własne instrukcje tylko tam, gdzie mają sens).
/// Sekcja z nagłówkiem i kartą; używana też w Settings (embedding). Sygnatura bez zmian względem wersji sprzed Designu B.
struct RoleEditor: View {
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var promptTitle: String?
    var promptHint: String?

    var body: some View {
        RoleSection(title: title, role: role, assignment: $assignment, language: language,
                    promptTitle: promptTitle, promptHint: promptHint) { EmptyView() }
    }
}

/// Wspólna sekcja roli: `SectionHeader` (dla korekty z „— optional” i przełącznikiem) + `Card` z `FormRow`.
/// `extra` to dodatkowe wiersze karty (np. język w ASR); `extraBeforeProbe` ustawia je przed linią wyniku sondy.
struct RoleSection<Extra: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var promptTitle: String?
    var promptHint: String?
    var extraBeforeProbe = false
    @ViewBuilder var extra: Extra

    private var hasExtra: Bool { Extra.self != EmptyView.self }
    private var optional: Bool { role == .correction }
    private var providers: [Provider] { model.providers.providers }

    private var enabled: Binding<Bool> {
        Binding(get: { assignment != nil }, set: { on in
            assignment = on ? providers.first.map { RoleAssignment(providerID: $0.id, model: "") } : nil
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title, note: optional ? "— optional" : nil) {
                if optional {
                    Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(providers.isEmpty && assignment == nil)
                        .help("Use a \(title.lowercased()) step")
                }
            }
            if !optional || assignment != nil { Card { rows } }
        }
    }

    @ViewBuilder private var rows: some View {
        let showProvider = providers.count > 1 || assignment == nil
        if showProvider {
            FormRow(label: "Provider") {
                Picker("Provider", selection: Binding(get: { assignment?.providerID }, set: { id in
                    assignment = id.map { RoleAssignment(providerID: $0, model: assignment?.model ?? "", prompt: assignment?.prompt) }
                })) {
                    Text("None").tag(UUID?.none)
                    ForEach(providers) { p in Text(p.name).tag(Optional(p.id)) }
                }
                .labelsHidden().fixedSize()
            }
        }
        if let a = assignment {
            if showProvider { RowDivider() }
            FormRow(label: "Model") {
                ModelPicker(providerID: a.providerID, role: role,
                            selection: Binding(get: { assignment?.model ?? "" }, set: { assignment?.model = $0 }))
            }
            if extraBeforeProbe && hasExtra { RowDivider(); extra }
            probeRow(a)
            if !extraBeforeProbe && hasExtra { RowDivider(); extra }
            if let promptTitle {
                RowDivider()
                // Etykieta przy górnej krawędzi pola (jak w makiecie), nie przy linii bazowej.
                HStack(alignment: .top, spacing: 12) {
                    Text(promptTitle).foregroundStyle(.mnText2).frame(width: 130, alignment: .leading).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        EditorPromptField(text: Binding(get: { a.prompt ?? "" }, set: { assignment?.prompt = $0 }))
                        if let promptHint { Text(promptHint).font(.subheadline).foregroundStyle(.mnText2) }
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 16)
            }
        } else if hasExtra {
            RowDivider(); extra
        }
    }

    /// `language` jest ustawiony tylko dla roli ASR — dla pozostałych to nil, jak przy zapisie.
    private func probeRow(_ a: RoleAssignment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ProbeBadges(result: model.probeCache.result(provider: a.providerID, model: a.model, role: role, language: language))
            Spacer(minLength: 0)
            Button("Test") { Task { await model.probe(providerID: a.providerID, model: a.model, role: role, language: language) } }
                .buttonStyle(.pillSmall)
                .disabled(a.model.isEmpty)
                .help("Sends a short test request to check this model works in this role")
        }
        .padding(.leading, 158).padding(.trailing, 16).padding(.bottom, 10)
    }
}

/// Wynik sondy jako linia `StateLabel`, nie przypis drobnym drukiem (spec fazy 1, §9): ok = ✓, problem = ✗/ostrzeżenie, nieznane = neutralnie.
struct ProbeBadges: View {
    let result: ProbeResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = result {
                if r.works {
                    HStack(spacing: 14) {
                        StateLabel(.ok, "Verified")
                        switch r.languageHandling {
                        case .enforced: StateLabel(.ok, "Language enforced")
                        case .filtered: StateLabel(.neutral, "Language filtered")
                        case .unknown: WarnLabel("Language handling unknown")
                        case .automatic, nil: EmptyView()
                        }
                        if r.shape == .chatAudio { StateLabel(.neutral, "No word timings") }
                    }
                    if r.languageHandling == .automatic {
                        WarnLabel("This model detects language itself — your language setting can't be enforced")
                    }
                } else {
                    StateLabel(.bad, "Doesn't work in this role").help(r.failure ?? "")
                }
            } else {
                StateLabel(.neutral, "Not tested")
            }
        }
    }
}
