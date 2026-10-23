import AppKit
import MeetNotesNotes
import MeetNotesProviders
import SwiftUI

/// Szkic ustawień globalnych: Save / Cancel obejmuje Archive search, Correction i Summary; dostawcy zapisują się od razu (plan 1.5-B, T4).
final class SettingsDraft: ObservableObject {
    @Published var embedding: RoleAssignment?
    @Published var confirming = false
    @Published var saved = false
    /// Sekcja Correction: przełącznik i pole „Words" (F20 P2).
    @Published var removeFillers = true
    @Published var fillers = ""
    /// Sekcja Summary: „Thinking" (F20 P1).
    @Published var summaryThinking = true

    func load(_ s: GlobalSettings) {
        embedding = s.embedding; saved = false
        removeFillers = s.removeFillersEnabled
        summaryThinking = s.summaryThinkingEnabled
        fillers = FillerWords.format(s.fillerWords ?? FillerWords.defaults)
    }
}

/// Stan arkusza „Set up <dostawca>" (macos.md §11.5): nowy dostawca albo podmiana klucza istniejącego (`editing`).
/// Wynik testu: `result` (OpenAI-compatible, przed zapisem) albo `note` (neutralna uwaga). Błąd walidacji/pęku: `error`.
final class ProviderSheetState: ObservableObject {
    @Published var showing = false
    @Published var preset: ProviderPreset = .custom
    /// Logo w nagłówku: gotowy dostawca albo `nil` = własny adres.
    @Published var logo: ProviderPreset?
    @Published var editing: Provider?
    @Published var name = ""
    @Published var url = ""
    @Published var key = ""
    /// „Context window (tokens)" dla lokalnego serwera: puste = domyślne 4096.
    @Published var context = ""
    @Published var error: String?
    @Published var result: ProviderCheck?
    @Published var note: String?
    @Published var testing = false

    func setUp(_ p: ProviderPreset) {
        open(preset: p, logo: p == .custom ? nil : p, editing: nil, name: p == .custom ? "" : p.name, url: p.baseURL)
    }

    func editKey(_ provider: Provider) {
        let match = ProviderPreset.matching(provider)
        open(preset: match ?? .custom, logo: match, editing: provider, name: provider.name, url: provider.baseURL.absoluteString)
        context = provider.contextTokens.map(String.init) ?? ""
    }

    private func open(preset: ProviderPreset, logo: ProviderPreset?, editing: Provider?, name: String, url: String) {
        self.preset = preset; self.logo = logo; self.editing = editing; self.name = name; self.url = url
        key = ""; context = ""; error = nil; result = nil; note = nil; testing = false; showing = true
    }
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5). Modele STT, korekty
/// i podsumowania wybiera się w presecie. Wygląd: macos.md §11.5 (`b-settings.png`, `b-add.png`).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var sheet = ProviderSheetState()
    @StateObject private var draft = SettingsDraft()

    private var isDirty: Bool {
        draft.embedding != model.settings.embedding
            || draft.removeFillers != model.settings.removeFillersEnabled
            || draft.summaryThinking != model.settings.summaryThinkingEnabled
            || FillerWords.parse(draft.fillers) != (model.settings.fillerWords ?? FillerWords.defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollPage(640) {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle("Settings").padding(.bottom, 4)
                    // Model Yascribe (Parakeet) nie jest dostawcą: własna karta na górze, nad listą Providers (F20 P3).
                    ModelCardSection(support: model.localASR)
                    SectionHeader("Providers")
                    Card {
                        let rows = ProviderListRow.rows(for: model.providers.providers)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            ProviderRowView(row: row, sheet: sheet)
                            if i < rows.count - 1 { RowDivider() }
                        }
                    }
                    RecordingsSection() // uwaga 8: między Providers a Archive search
                    MeetingSettingsSections()
                    correctionSection
                    summarySection
                    archiveSearch
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Speech-to-text, correction and summary models are chosen in each preset.")
                        link("Open Presets") { model.section = .presets }
                    }
                    .font(.system(size: 12)).foregroundStyle(.mnText2).padding(.top, 14).padding(.leading, 2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Microphone and system audio access:")
                        link("Check Permissions…") { model.showSetup = true }
                    }
                    .font(.system(size: 12)).foregroundStyle(.mnText2).padding(.top, 6).padding(.leading, 2)
                }
            }
            footer
        }
        .contentBackground()
        .navigationTitle("Settings")
        .onAppear { draft.load(model.settings) }
        .sheet(isPresented: $sheet.showing) { ProviderSetupSheet(state: sheet) }
        .confirmationDialog("Change the embedding model?", isPresented: $draft.confirming) {
            Button("Change Model", role: .destructive) { commit() }
            Button("Keep Current Model", role: .cancel) {}
        } message: {
            Text("Changing the embedding model means the whole archive will be re-indexed when archive search arrives. Change it?")
        }
    }

    // MARK: Correction (F20 P2)

    /// Zapis przyciskiem Save. Lista idzie do polecenia dla modelu i do filtra po korekcie.
    @ViewBuilder private var correctionSection: some View {
        SectionHeader("Correction")
        Card {
            FormRow(label: "Filler sounds",
                    caption: "Removes sounds like “yyy” and “mhm” from corrected transcripts: the model is asked to drop them and the app removes any that remain. The original transcript is kept.") {
                Toggle("Filler sounds", isOn: Binding(
                    get: { draft.removeFillers },
                    set: { draft.removeFillers = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if draft.removeFillers {
                RowDivider()
                FormRow(label: "Words", caption: "Separate with commas.") {
                    HStack(spacing: 8) {
                        TextField("yyy, eee, mhm", text: $draft.fillers).textFieldStyle(.roundedBorder)
                        Button("Reset") { draft.fillers = FillerWords.format(FillerWords.defaults) }
                            .buttonStyle(.pillSmall).help("Back to the default list")
                    }
                }
            }
        }
    }

    // MARK: Summary (F20 P1)

    /// Zapis przyciskiem Save. Korekta nigdy nie myśli — to nie jest ustawienie.
    @ViewBuilder private var summarySection: some View {
        SectionHeader("Summary")
        Card {
            FormRow(label: "Thinking",
                    caption: "Lets API models reason before writing the notes. Off is faster and avoids timeouts; on may help with long or complex meetings. Local models always run without thinking, and corrections never think.") {
                Toggle("Thinking", isOn: Binding(
                    get: { draft.summaryThinking },
                    set: { draft.summaryThinking = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Archive search (uwaga 6)

    private var candidates: [Provider] { EmbeddingChoice.providers(model.providers.providers) }

    /// Dostawca, którego modele pokazujemy: wybrany (jeśli nadal jest na liście) albo jedyny kandydat.
    private var embeddingProvider: Provider? {
        candidates.first { $0.id == draft.embedding?.providerID } ?? (candidates.count == 1 ? candidates.first : nil)
    }

    @ViewBuilder private var archiveSearch: some View {
        SectionHeader("Archive search")
        Card {
            if candidates.isEmpty {
                Text("Set up OpenRouter, Ollama or a custom endpoint above to choose an embedding model.")
                    .foregroundStyle(.mnText2).padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                if EmbeddingChoice.showsProviderRow(candidates: candidates) {
                    FormRow(label: "Provider") {
                        FieldMenu(label: "Provider", value: embeddingProvider?.name ?? "Choose…", width: 180) {
                            Picker("Provider", selection: Binding(
                                get: { embeddingProvider?.id },
                                set: { draft.embedding = EmbeddingChoice.select(provider: $0, current: draft.embedding) })) {
                                Text("None").tag(UUID?.none)
                                ForEach(candidates) { p in Text(p.name).tag(Optional(p.id)) }
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                    }
                    if embeddingProvider != nil { RowDivider() }
                }
                if let p = embeddingProvider {
                    FormRow(label: "Embedding model") {
                        ModelPicker(providerID: p.id, role: .embedding, selection: Binding(
                            get: { draft.embedding?.providerID == p.id ? draft.embedding?.model ?? "" : "" },
                            set: { m in
                                var a = EmbeddingChoice.select(provider: p.id, current: draft.embedding)
                                a?.model = m
                                draft.embedding = a
                            }))
                    }
                }
            }
        }
    }

    /// Dolny pasek: Cancel / Save obejmuje tylko „Archive search".
    private var footer: some View {
        HStack(spacing: 8) {
            if draft.saved && !isDirty { StateLabel(.ok, "Saved") }
            Spacer()
            Button("Cancel") { draft.load(model.settings) }.buttonStyle(.pill).disabled(!isDirty)
            Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut("s", modifiers: .command).disabled(!isDirty)
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(.mnBackground)
        .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(.medium).foregroundStyle(.mnText).underline(color: .mnText3)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        if GlobalSettings.embeddingChangeNeedsConfirmation(old: model.settings.embedding, new: draft.embedding) {
            draft.confirming = true
        } else {
            commit()
        }
    }

    private func commit() {
        let words = FillerWords.parse(draft.fillers)
        model.settings.embedding = draft.embedding
        model.settings.removeFillers = draft.removeFillers
        model.settings.fillerWords = words == FillerWords.defaults ? nil : words
        model.settings.summaryThinking = draft.summaryThinking
        model.save()
        draft.fillers = FillerWords.format(words)
        draft.saved = true
    }
}

final class ProviderRowState: ObservableObject {
    @Published var confirmingRemove = false
}

/// Wiersz karty Providers: logo, nazwa, opis roli; po prawej stan + Retry + „⋯" (skonfigurowany) albo „Set up…" / „Add…".
private struct ProviderRowView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var rowState = ProviderRowState()
    let row: ProviderListRow
    @ObservedObject var sheet: ProviderSheetState

    private var provider: Provider? {
        switch row {
        case .preset(_, let p): p
        case .custom(let p): p
        case .addCustom: nil
        }
    }
    private var preset: ProviderPreset? {
        switch row {
        case .preset(let p, _): p
        case .custom(let p): ProviderPreset.matching(p)
        case .addCustom: .custom
        }
    }
    private var title: String {
        switch row {
        case .preset(let p, _): p.name
        case .custom(let p): p.name
        case .addCustom: ProviderPreset.custom.name
        }
    }
    private var subtitle: String {
        switch row {
        case .preset(let p, _): p.role
        case .custom(let p): ProviderPreset.displayAddress(p.baseURL) + (preset.map { " · " + $0.role } ?? "")
        case .addCustom: ProviderPreset.custom.role
        }
    }
    private var key: KeyStatus? { provider.map { p in KeyStatus.of({ try model.secrets.get(p.id) }) } }
    private var failure: String? {
        // „On this Mac": stan modelu opisuje karta poniżej, więc bez czerwonej linii i bez Retry (nic do ponowienia przez sieć).
        guard let p = provider, p.api != .fluidAudio, !model.providerVerifying.contains(p.id),
              case .failed(let why)? = model.providerChecks[p.id] else { return nil }
        return why
    }

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(preset: preset)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle)
                if case .unreadable(let why)? = key {
                    // Błąd pęku kluczy to nie „No key" (S18 §2.4): ikona + słowo, w kolorze ostrzeżenia.
                    Label("Couldn't read the key from Keychain", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.mnWarn).help(why)
                }
                if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.mnRec).lineLimit(2) }
                if let p = provider, p.isLocal, p.api == .openAICompatible {
                    // Ustawione przez użytkownika i/lub wykryte przy „Test again" (ten sam komunikat, który widzi budżet).
                    let parts = [p.contextTokens.map { "Context window: \($0) tokens" }, model.detectedContexts[p.id]].compactMap { $0 }
                    if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(2) }
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .confirmationDialog("Remove \(title)?", isPresented: $rowState.confirmingRemove) {
            Button("Remove", role: .destructive) { if let p = provider { model.removeProvider(p.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The provider and its saved key are deleted. Presets that use it will need another provider.")
        }
    }

    @ViewBuilder private var trailing: some View {
        if let p = provider {
            state(p)
            if failure != nil {
                Button("Retry") { Task { await model.verifyProvider(p.id) } }
                    .buttonStyle(.pillSmall).help("Test the connection again")
            }
            Menu {
                if preset.map({ $0.needsKey || $0.keyOptional }) ?? true { Button("Edit key…") { sheet.editKey(p) } }
                if p.isLocal && p.api == .openAICompatible { Button("Context window…") { sheet.editKey(p) } }
                Button("Test again") { Task { await model.verifyProvider(p.id) } }
                Button("Refresh Models") { Task { await model.refreshModels(p.id) } }
                Divider()
                Button("Remove…", role: .destructive) { rowState.confirmingRemove = true }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.mnText2).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More actions for \(p.name)")
            .accessibilityLabel("More actions for \(p.name)")
        } else if case .preset(let p, _) = row {
            Button("Set up…") { sheet.setUp(p) }.buttonStyle(.pillSmall).help("Set up \(p.name)")
        } else {
            Button("Add…") { sheet.setUp(.custom) }.buttonStyle(.pillSmall).help("Add a custom OpenAI-compatible endpoint")
        }
    }

    @ViewBuilder private func state(_ p: Provider) -> some View {
        if model.providerVerifying.contains(p.id) {
            StateLabel(.progress(nil), "Verifying…")
        } else {
            switch model.providerChecks[p.id] {
            case .verified? where p.api == .fluidAudio: StateLabel(.ok, "Ready")
            case .verified(let n)?: StateLabel(.ok, "Verified · \(n) model\(n == 1 ? "" : "s")")
            case .failed(let why)? where p.api == .fluidAudio: WarnLabel("Model not ready").help(why)
            case .failed(let why)?: StateLabel(.bad, "Failed").help(why)
            case .limited(let why)?: WarnLabel(why)
            case nil: StateLabel(.neutral, "Not verified")
            }
        }
    }
}

/// Arkusz konfiguracji (macos.md §11.5, `b-add.png`): adres, klucz, link do klucza, Test connection z wynikiem w tej samej linii, Cancel / Save.
/// Save zapisuje dostawcę od razu (`addProvider`) albo podmienia klucz (`replaceKey`); Cancel nie zapisuje nic — test przed zapisem
/// idzie na kluczu z pola (w pamięci), więc anulowanie nie zostawia klucza w pęku bez dostawcy.
struct ProviderSetupSheet: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: ProviderSheetState

    private var preset: ProviderPreset { state.preset }
    private var editing: Bool { state.editing != nil }
    private var title: String {
        if let p = state.editing { return showsKeyField ? "Edit key for \(p.name)" : "Edit \(p.name)" }
        return preset == .custom ? "Set up custom endpoint" : "Set up \(preset.name)"
    }
    /// „Paste your key first." dotyczy tylko `needsKey`; klucz opcjonalny (oMLX) ma pole, ale można je zostawić puste.
    private var needsKey: Bool { preset.needsKey }
    private var showsKeyField: Bool { preset.needsKey || preset.keyOptional }
    private var editableAddress: Bool { preset == .custom && !editing }
    /// Pole kontekstu tylko dla lokalnego serwera OpenAI-compatible (Ollama, llama.cpp, oMLX, własny na loopbacku).
    private var showsContext: Bool {
        guard let url = state.editing?.baseURL ?? URL(string: state.url.trimmingCharacters(in: .whitespaces)) else { return false }
        let p = Provider(name: "", baseURL: url, kind: state.editing?.kind ?? preset.kind)
        return p.isLocal && p.api == .openAICompatible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderLogo(preset: state.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.mnText)
                    Text(preset.role).font(.system(size: 11)).foregroundStyle(.mnText2)
                }
            }
            .padding(.bottom, 12)
            if editableAddress {
                FormRow(label: "Address", labelWidth: 70) { TextField("https://example.com/v1", text: $state.url).textFieldStyle(.plain).fieldBox() }
                FormRow(label: "Name", labelWidth: 70) { TextField("Name", text: $state.name).textFieldStyle(.plain).fieldBox() }
            } else {
                FormRow(label: "Address", labelWidth: 70) { Text(state.url).foregroundStyle(.mnText).textSelection(.enabled) }
            }
            if showsKeyField {
                FormRow(label: "API key", labelWidth: 70) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField(preset.keyOptional ? "Optional" : "Paste your key", text: $state.key).textFieldStyle(.plain).fieldBox()
                        if preset.keyOptional {
                            Text("Optional — only if you set a key in \(preset.name).").font(.system(size: 11)).foregroundStyle(.mnText2)
                        }
                        if let page = preset.keyPage { keyLink(page) }
                    }
                }
            }
            if showsContext {
                FormRow(label: "Context", labelWidth: 70) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Context window (tokens) — default 4096", text: $state.context).textFieldStyle(.plain).fieldBox()
                        Text("Ollama uses 4096 unless you raise it (OLLAMA_CONTEXT_LENGTH or Ollama's Context length setting). Enter the server's value here.")
                            .font(.system(size: 11)).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            testLine.padding(.leading, 98).padding(.trailing, 8).padding(.top, 4)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { state.showing = false }.buttonStyle(.pill).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18).padding(.trailing, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 20)
        .frame(width: 480)
        .background(.mnCard)
        .onChange(of: state.key) { _, _ in state.result = nil; state.note = nil; state.error = nil }
        .onChange(of: state.context) { _, _ in state.error = nil }
    }

    private func keyLink(_ page: URL) -> some View {
        HStack(spacing: 0) {
            Button { NSWorkspace.shared.open(page) } label: {
                Text("Get an API key").fontWeight(.medium).foregroundStyle(.mnText).underline(color: .mnText3)
            }
            .buttonStyle(.plain)
            Text(" on \(page.host()?.replacingOccurrences(of: "www.", with: "") ?? "")").foregroundStyle(.mnText2)
        }
        .font(.system(size: 11))
    }

    /// „Test connection" + wynik w tej samej linii; gdy tekst się nie mieści, pod przyciskiem.
    private var testLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { testButton; resultLabel; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 6) { testButton; resultLabel }
        }
    }

    private var testButton: some View {
        Button("Test connection") { Task { await test() } }
            .buttonStyle(.pillSmall).disabled(state.testing)
            .help("Checks the address and key without saving anything")
    }

    @ViewBuilder private var resultLabel: some View {
        if state.testing {
            StateLabel(.progress(nil), "Testing…")
        } else if let e = state.error {
            StateLabel(.bad, e).wrapping()
        } else if let r = state.result {
            switch r {
            case .verified(let n): StateLabel(.ok, "Verified · \(n) model\(n == 1 ? "" : "s") available")
            case .failed(let why): StateLabel(.bad, why).wrapping()
            case .limited(let why): WarnLabel(why)
            }
        } else if let n = state.note {
            StateLabel(.neutral, n)
        }
    }

    // MARK: Akcje

    private func trimmedKey() -> String { state.key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func address() -> URL? {
        guard let u = URL(string: state.url.trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(u.scheme), u.host() != nil else {
            state.error = "Enter a full address, e.g. https://openrouter.ai/api/v1."
            return nil
        }
        return u
    }

    private func test() async {
        state.error = nil; state.result = nil; state.note = nil
        let key = trimmedKey()
        if needsKey && key.isEmpty && !editing { state.error = "Paste your key first."; return }
        guard let url = state.editing?.baseURL ?? address() else { return }
        let kind = state.editing?.kind ?? preset.kind
        state.testing = true
        defer { state.testing = false }
        // Edit key… z pustym polem: test zapisanego klucza. Inaczej: klucz z pola, bez zapisu do pęku.
        if let id = state.editing?.id, key.isEmpty {
            await model.verifyProvider(id)
            state.result = model.providerChecks[id]
        } else {
            state.result = await AppModel.testConnection(baseURL: url, kind: kind, key: key,
                                                             name: preset == .custom ? (state.name.isEmpty ? "The server" : state.name) : preset.name)
        }
    }

    /// Pole „Context window": puste = `nil` (4096); poza zakresem albo nie liczba = błąd w arkuszu.
    private func contextTokens() -> Result<Int?, ContextFieldError> {
        let text = state.context.trimmingCharacters(in: .whitespaces)
        guard showsContext, !text.isEmpty else { return .success(nil) }
        guard let n = Int(text), ContextBudget.userRange.contains(n) else { return .failure(ContextFieldError()) }
        return .success(n)
    }

    private struct ContextFieldError: Error {}

    private func save() {
        state.error = nil
        let key = trimmedKey()
        if needsKey && key.isEmpty { state.error = "Paste your key first."; return }
        guard case .success(let context) = contextTokens() else {
            state.error = "Context window: enter a number from \(ContextBudget.userRange.lowerBound) to \(ContextBudget.userRange.upperBound), or leave it empty for \(ContextBudget.defaultTokens)."
            return
        }
        if let p = state.editing {
            // Podmiana klucza istniejącego dostawcy (adres i nazwa bez zmian): zapis i ponowna weryfikacja.
            if let e = model.replaceKey(p.id, key: key) { state.error = e } else {
                if showsContext { model.setContextTokens(p.id, context) }
                state.showing = false
            }
            return
        }
        guard let url = address() else { return }
        if let e = model.addProvider(name: preset == .custom ? state.name : preset.name, baseURL: url, key: key, kind: preset.kind, contextTokens: context) {
            state.error = e // duplikat nazwy albo błąd pęku kluczy; arkusz zostaje otwarty
        } else {
            state.showing = false
        }
    }
}

extension View {
    /// Pole tekstowe wg makiety: 28 pt, `field`, obwódka 0,5 pt, promień 7 (jak ModelField).
    func fieldBox() -> some View {
        padding(.horizontal, 10).frame(height: 28)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
    }
}
