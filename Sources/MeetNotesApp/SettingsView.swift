import AppKit
import MeetNotesProviders
import SwiftUI

/// Szkic sekcji „Archive": Save / Cancel obejmuje tylko ją; dostawcy zapisują się od razu (plan 1.5-B, T4).
final class SettingsDraft: ObservableObject {
    @Published var embedding: RoleAssignment?
    @Published var confirming = false
    @Published var saved = false

    func load(_ s: GlobalSettings) { embedding = s.embedding; saved = false }
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
    }

    private func open(preset: ProviderPreset, logo: ProviderPreset?, editing: Provider?, name: String, url: String) {
        self.preset = preset; self.logo = logo; self.editing = editing; self.name = name; self.url = url
        key = ""; error = nil; result = nil; note = nil; testing = false; showing = true
    }
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5). Modele STT, korekty
/// i podsumowania wybiera się w presecie. Wygląd: macos.md §11.5 (`b-settings.png`, `b-add.png`).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var sheet = ProviderSheetState()
    @StateObject private var draft = SettingsDraft()

    private var isDirty: Bool { draft.embedding != model.settings.embedding }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle("Settings").padding(.bottom, 4)
                    SectionHeader("Providers")
                    Card {
                        let rows = ProviderListRow.rows(for: model.providers.providers)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            ProviderRowView(row: row, sheet: sheet)
                            if i < rows.count - 1 { RowDivider() }
                        }
                    }
                    RecordingsSection() // uwaga 8: między Providers a Archive search
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
                .contentColumn(640)
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
        model.settings.embedding = draft.embedding
        model.save()
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
        guard let p = provider, !model.providerVerifying.contains(p.id), case .failed(let why)? = model.providerChecks[p.id] else { return nil }
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
                if preset?.needsKey ?? true { Button("Edit key…") { sheet.editKey(p) } }
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
            case .verified(let n)?: StateLabel(.ok, "Verified · \(n) model\(n == 1 ? "" : "s")")
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
        if let p = state.editing { return "Edit key for \(p.name)" }
        return preset == .custom ? "Set up custom endpoint" : "Set up \(preset.name)"
    }
    private var needsKey: Bool { preset.needsKey }
    private var editableAddress: Bool { preset == .custom && !editing }

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
            if needsKey {
                FormRow(label: "API key", labelWidth: 70) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("Paste your key", text: $state.key).textFieldStyle(.plain).fieldBox()
                        if let page = preset.keyPage { keyLink(page) }
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
            StateLabel(.bad, e)
        } else if let r = state.result {
            switch r {
            case .verified(let n): StateLabel(.ok, "Verified · \(n) model\(n == 1 ? "" : "s") available")
            case .failed(let why): StateLabel(.bad, why)
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
            state.result = await AppModel.testConnection(baseURL: url, kind: kind, key: key)
        }
    }

    private func save() {
        state.error = nil
        let key = trimmedKey()
        if needsKey && key.isEmpty { state.error = "Paste your key first."; return }
        if let p = state.editing {
            // Podmiana klucza istniejącego dostawcy (adres i nazwa bez zmian): zapis i ponowna weryfikacja.
            if let e = model.replaceKey(p.id, key: key) { state.error = e } else { state.showing = false }
            return
        }
        guard let url = address() else { return }
        if let e = model.addProvider(name: preset == .custom ? state.name : preset.name, baseURL: url, key: key, kind: preset.kind) {
            state.error = e // duplikat nazwy albo błąd pęku kluczy; arkusz zostaje otwarty
        } else {
            state.showing = false
        }
    }
}

private extension View {
    /// Pole tekstowe wg makiety: 28 pt, `field`, obwódka 0,5 pt, promień 7 (jak ModelField).
    func fieldBox() -> some View {
        padding(.horizontal, 10).frame(height: 28)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
    }
}
