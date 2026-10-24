import MeetNotesProviders
import SwiftUI

final class PresetEditorState: ObservableObject {
    /// Edytowana kopia; okno edycji jest otwarte, gdy nie jest `nil` (jak `DictionaryViewState.draft`).
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
    /// Zamyka okno bez zapisu; nowy, niezapisany preset znika razem z oknem.
    func close() { draft = nil; original = nil; error = nil }
}

/// Presety (faza 2.1 „okna", wzorzec Dictionary): lista w karcie, klik w wiersz otwiera okno edycji.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: PresetEditorState

    init(state: PresetEditorState = PresetEditorState()) { _state = StateObject(wrappedValue: state) }

    var body: some View {
        ScrollPage(640) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    PageTitle("Presets")
                    Spacer()
                    Button { state.startNew() } label: { Label("New preset", systemImage: "plus") }
                        .buttonStyle(.pill)
                        .help("New preset")
                }
                .padding(.bottom, 18)
                Card {
                    ForEach(Array(model.presets.presets.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { RowDivider() }
                        Button { state.select(p) } label: {
                            EditorListRow(title: p.name, subtitle: meta(p),
                                          trailing: p.isFullyLocal(providers: model.providers.providers) ? FullyLocalBadge() : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .contentBackground()
        .navigationTitle("Presets")
        .sheet(isPresented: Binding(get: { state.draft != nil }, set: { if !$0 { state.close() } })) {
            PresetSheet(state: state) { save() }
        }
    }

    private func meta(_ p: Preset) -> String {
        var parts = [p.languageLabel, p.asr.map { $0.model.split(separator: "/").last.map(String.init) ?? $0.model } ?? "No speech-to-text model"]
        if p.id == model.settings.defaultPresetID { parts.append("default") }
        return parts.joined(separator: " · ")
    }

    /// Błąd zapisu zostawia okno otwarte z komunikatem; sukces je zamyka.
    private func save() {
        state.error = state.draft.flatMap { model.savePreset($0) }
        if state.error == nil { state.close() }
    }
}

/// Okno edycji presetu; renderowalne samodzielnie (migawki: `ImageRenderer`/`NSHostingView` nie łapią `.sheet`).
struct PresetSheet: View {
    @ObservedObject var state: PresetEditorState
    var onSave: () -> Void

    var body: some View {
        EditorSheet(title: state.isNew ? "New preset" : "Edit preset", dirty: state.isDirty, error: state.error,
                    onCancel: { state.close() }, onSave: onSave) {
            EmptyView()
        } content: {
            PresetForm(state: state)
        }
    }
}

/// Wiersz listy presetów i szablonów: nazwa 13 Medium + metadane 11 pt `text2`; zaznaczenie `selection`, promień 8, bez białego bloku.
struct PresetRow: View {
    let title: String
    let subtitle: String
    var selected = false
    var dim = false
    /// Plakietka „Fully local" pod metadanymi (wszystkie role presetu są lokalne).
    var fullyLocal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(dim ? .mnText2 : .mnText).lineLimit(1)
            Text(subtitle).font(.system(size: 11)).italic(dim).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
            if fullyLocal { FullyLocalBadge().padding(.top, 3) }
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
            .font(.system(size: 15)) // makieta: nazwa zwykłym 15 pt, nie pogrubiona
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
            .font(.system(size: 13)).foregroundStyle(.mnText)
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
                if state.draft?.isFullyLocal(providers: model.providers.providers) == true { FullyLocalBadge() }
            }
            RoleSection(title: "Speech to text", role: .asr, assignment: draft.asr, language: draft.wrappedValue.language) {
                // 🔴 Bez wartości domyślnej (P7). „Auto" to opcja awaryjna na końcu listy, z ostrzeżeniem.
                FormRow(label: "Language") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldMenu(label: "Language", value: languageName(draft.languageChoice.wrappedValue), width: 180) {
                            Picker("Language", selection: draft.languageChoice) {
                                Text("Choose…").tag(LanguageChoice.unset)
                                ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                                Divider()
                                Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
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
                    FieldMenu(label: "Notes language",
                              value: draft.notesLanguage.wrappedValue.map { languageName(.code($0)) } ?? "Same as preset", width: 180) {
                        Picker("Notes language", selection: draft.notesLanguage) {
                            Text("Same as preset").tag(LanguageCode?.none)
                            ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    }
                }
            }
            Text("Embeddings are set once for the whole archive in Settings.")
                .font(.system(size: 11)).foregroundStyle(.mnText2).padding(.top, 14).padding(.leading, 2)
        }
    }
}

/// Ostrzeżenie: ikona + słowa w `warn` (nigdy sam kolor).
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
/// `extra` to dodatkowe wiersze karty (np. język w ASR); sonda i własne instrukcje są w zwiniętej sekcji „Advanced".
struct RoleSection<Extra: View>: View {
    /// Stan rozwinięcia „Advanced"; `nil` = użytkownik jeszcze nie wybrał, liczy się `RoleAdvanced.startsExpanded`.
    final class AdvancedState: ObservableObject { @Published var open: Bool? }

    @Environment(AppModel.self) private var model
    @StateObject private var advanced = AdvancedState()
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var promptTitle: String?
    var promptHint: String?
    @ViewBuilder var extra: Extra

    private var hasExtra: Bool { Extra.self != EmptyView.self }
    private var optional: Bool { role == .correction }
    /// Tylko dostawcy obsługujący rolę (F20 P4) plus bieżący wybór zapisanego presetu (`RoleProviders.choices`).
    private var providers: [Provider] { RoleProviders.choices(model.providers.providers, role: role, current: assignment?.providerID) }

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
                FieldMenu(label: "Provider", value: providers.first { $0.id == assignment?.providerID }?.roleLabel ?? "None", width: 180) {
                    Picker("Provider", selection: Binding(get: { assignment?.providerID }, set: { id in
                        assignment = id.map { RoleAssignment(providerID: $0, model: assignment?.model ?? "", prompt: assignment?.prompt) }
                    })) {
                        Text("None").tag(UUID?.none)
                        ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
        }
        if let a = assignment {
            if showProvider { RowDivider() }
            FormRow(label: "Model") {
                ModelPicker(providerID: a.providerID, role: role,
                            selection: Binding(get: { assignment?.model ?? "" }, set: { assignment?.model = $0 }))
            }
            if let p = providers.first(where: { $0.id == a.providerID }), p.isLocal {
                if role == .asr, p.api == .fluidAudio {
                    OnThisMacRoleRow(support: model.localASR)
                } else {
                    LocalRoleNote(warnsAboutCorrection: role == .correction)
                }
            }
            if hasExtra { RowDivider(); extra }
            RowDivider()
            // Wzorzec: „Advanced" w `MeetingSettingsView`. Stan zamrażany przy pojawieniu się, żeby wynik „Test" ani pisanie w polu go nie przełączały.
            DisclosureGroup("Advanced", isExpanded: advancedOpen(a)) {
                VStack(alignment: .leading, spacing: 0) {
                    probeRow(a)
                    if promptTitle != nil { RowDivider(); promptRow(a) }
                }
                .padding(.top, 6).padding(.leading, -16)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .onAppear { if advanced.open == nil { advanced.open = startsExpanded(a) } }
        } else if hasExtra {
            RowDivider(); extra
        }
    }

    private func startsExpanded(_ a: RoleAssignment) -> Bool {
        RoleAdvanced.startsExpanded(probe: model.probeCache.result(provider: a.providerID, model: a.model, role: role, language: language), prompt: a.prompt)
    }

    private func advancedOpen(_ a: RoleAssignment) -> Binding<Bool> {
        Binding(get: { advanced.open ?? startsExpanded(a) }, set: { advanced.open = $0 })
    }

    @ViewBuilder private func promptRow(_ a: RoleAssignment) -> some View {
        if let promptTitle {
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

/// Znacznik „On this Mac" (ikona układu + słowa): rola, której dostawca działa na tym komputerze (`Provider.isLocal`).
struct OnThisMacTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu").font(.system(size: 11)).accessibilityHidden(true)
            Text("On this Mac")
        }
        .font(.callout).foregroundStyle(.mnText2)
    }
}

/// Plakietka „Fully local" na presecie: wszystkie przypisane role są lokalne (`Preset.isFullyLocal`).
struct FullyLocalBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu").font(.system(size: 10)).accessibilityHidden(true)
            Text("Fully local").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.mnText2)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(.mnField, in: Capsule())
        .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Rola z lokalnym serwerem tekstowym (Ollama, llama.cpp, oMLX, własny na loopbacku): znacznik „On this Mac"; przy korekcie ostrzeżenie,
/// że mały model potrafi zmienić nazwy, liczby i daty. Aplikacja nie poleca żadnych modeli (spec fazy 2.0 §14 pkt 6).
struct LocalRoleNote: View {
    static let correctionWarning = "Small local models can change names, numbers or dates while correcting. Compare with the original transcript."
    var warnsAboutCorrection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OnThisMacTag()
            if warnsAboutCorrection { WarnLabel(Self.correctionWarning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Nazwa wyboru języka do pola `FieldMenu`.
func languageName(_ c: LanguageChoice) -> String {
    switch c {
    case .unset: "Choose…"
    case .auto: "Auto (mixed languages)"
    case .code(let code): LanguageCode.selectable.first { $0.code == code }?.name ?? "\(code)"
    }
}

/// Pusty edytor (nic nie wybrano): dwie linie tekstu na tokenach, bez systemowej ikony (§11.6).
struct EmptyEditorHint: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
            Text(text).font(.callout).foregroundStyle(.mnText2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
