import MeetNotesProviders
import SwiftUI

/// Formularz dodawania dostawcy w miejscu (karta Providers, macos.md §11.5). `preset == nil` = zwinięty.
/// Dostawca zapisuje się od razu przy „Save & verify"; `savedID` pamięta go, żeby kolejne „Save & verify"
/// (poprawiony klucz) tylko podmieniło klucz (`replaceKey`) zamiast dodawać duplikat.
final class AddProviderState: ObservableObject {
    @Published var preset: ProviderPreset?
    @Published var name = ""
    @Published var url = ""
    @Published var key = ""
    /// Błąd przed zapisem (adres, nazwa, brak klucza, pęk kluczy). Wynik weryfikacji czytamy z `AppModel.providerChecks`.
    @Published var error: String?
    @Published var savedID: UUID?

    func open(_ p: ProviderPreset) { preset = p; name = p.name; url = p.baseURL; key = ""; error = nil; savedID = nil }
    func close() { preset = nil; key = ""; error = nil; savedID = nil }
}

/// Szkic sekcji „Archive": Save / Cancel obejmuje tylko ją; dostawcy zapisują się od razu (plan 1.5-B, T4).
final class SettingsDraft: ObservableObject {
    @Published var embedding: RoleAssignment?
    @Published var confirming = false
    @Published var saved = false

    func load(_ s: GlobalSettings) { embedding = s.embedding; saved = false }
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5). Modele STT, korekty
/// i podsumowania wybiera się w presecie. Wygląd: macos.md §11.5 (`b-settings.png`, `b-add.png`).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var add: AddProviderState
    @StateObject private var draft = SettingsDraft()

    init(add: AddProviderState = AddProviderState()) { _add = StateObject(wrappedValue: add) }

    private var isDirty: Bool { draft.embedding != model.settings.embedding }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle("Settings").padding(.bottom, 4)
                    SectionHeader("Providers")
                    Card {
                        ForEach(model.providers.providers) { p in
                            ProviderRow(provider: p)
                            RowDivider()
                        }
                        if add.preset != nil { AddProviderForm(add: add) } else { addRow }
                    }
                    SectionHeader("Archive search")
                    Card {
                        RoleEditor(title: "Embedding model", role: .embedding, assignment: $draft.embedding, language: nil)
                    }
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
        .confirmationDialog("Change the embedding model?", isPresented: $draft.confirming) {
            Button("Change Model", role: .destructive) { commit() }
            Button("Keep Current Model", role: .cancel) {}
        } message: {
            Text("Changing the embedding model means the whole archive will be re-indexed when archive search arrives. Change it?")
        }
    }

    /// „Add: OpenRouter · Ollama · Custom…" — małe pigułki; dostawca już dodany jest nieaktywny (Custom nigdy).
    private var addRow: some View {
        HStack(spacing: 6) {
            Text("Add:").foregroundStyle(.mnText2).padding(.trailing, 4)
            ForEach(ProviderPreset.all) { preset in
                Button(preset == .custom ? "Custom…" : preset.name) { add.open(preset) }
                    .buttonStyle(.pillSmall)
                    .disabled(preset.isAdded(in: model.providers.providers))
                    .help(preset.isAdded(in: model.providers.providers) ? "\(preset.name) is already added" : "Add \(preset.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
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

/// Wiersz dostawcy: nazwa, pod nią adres (+ ograniczenie gotowego dostawcy), po prawej stan, Retry przy błędzie i menu „⋯".
private struct ProviderRow: View {
    @Environment(AppModel.self) private var model
    let provider: Provider

    private var preset: ProviderPreset? { ProviderPreset.matching(provider.baseURL) }
    private var key: KeyStatus { KeyStatus.of({ try model.secrets.get(provider.id) }) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                Text(meta).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle)
                if case .unreadable(let why) = key {
                    // Błąd pęku kluczy to nie „No key" (S18 §2.4): ikona + słowo, w kolorze ostrzeżenia.
                    Label("Couldn't read the key from Keychain", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.mnWarn).help(why)
                }
            }
            Spacer(minLength: 8)
            state
            if case .failed? = model.providerChecks[provider.id], !model.providerVerifying.contains(provider.id) {
                Button("Retry") { Task { await model.verifyProvider(provider.id) } }
                    .buttonStyle(.pillSmall).help("Test the connection again")
            }
            Menu {
                Button("Verify") { Task { await model.verifyProvider(provider.id) } }
                Button("Refresh Models") { Task { await model.refreshModels(provider.id) } }
                Divider()
                Button("Remove", role: .destructive) { model.removeProvider(provider.id) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.mnText2).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More actions for \(provider.name)")
            .accessibilityLabel("More actions for \(provider.name)")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// „openrouter.ai/api/v1 · <ograniczenie> · <zamaskowany klucz | No key>".
    private var meta: String {
        var parts = [ProviderPreset.displayAddress(provider.baseURL)]
        if let note = preset?.note { parts.append(note) }
        switch key {
        case .set(let masked): parts.append(masked)
        case .missing: if preset?.needsKey ?? true { parts.append("No key") }
        case .unreadable: break
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var state: some View {
        if model.providerVerifying.contains(provider.id) {
            StateLabel(.progress(nil), "Verifying…")
        } else {
            switch model.providerChecks[provider.id] {
            case .verified(let n)?: StateLabel(.ok, "Verified · \(n) models")
            case .failed(let why)?: StateLabel(.bad, "Verification failed").help(why)
            case nil: StateLabel(.neutral, "Not verified")
            }
        }
    }
}

/// Rozwinięty formularz w karcie (tło `sunk`, linia `line2` u góry): adres, nazwa (Custom), klucz, wynik, Cancel / Save & verify.
private struct AddProviderForm: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var add: AddProviderState

    private var preset: ProviderPreset { add.preset ?? .custom }
    /// Dostawca już zapisany tym formularzem (nie usunięty w międzyczasie z „⋯").
    private var savedID: UUID? { add.savedID.flatMap { id in model.providers.providers.contains { $0.id == id } ? id : nil } }
    private var verified: Bool { savedID.map { if case .verified? = model.providerChecks[$0] { true } else { false } } ?? false }

    private var description: String {
        switch preset.id {
        case "openrouter": "transcription, correction and summary"
        default: preset.note ?? ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(preset.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
                Text(description).font(.system(size: 11)).foregroundStyle(.mnText2)
            }
            .padding(.bottom, 6)
            // Po zapisie adres i nazwa są tylko do odczytu: zmiana = Remove w „⋯" i dodanie od nowa.
            if preset == .custom && savedID == nil {
                row("Address") { TextField("https://example.com/v1", text: $add.url).textFieldStyle(.plain).fieldBox() }
                row("Name") { TextField("Name", text: $add.name).textFieldStyle(.plain).fieldBox() }
            } else {
                row("Address") { Text(add.url).foregroundStyle(.mnText2).textSelection(.enabled) }
                if preset == .custom { row("Name") { Text(add.name).foregroundStyle(.mnText2) } }
            }
            if preset.needsKey {
                row("API key") { SecureField("Paste your key", text: $add.key).textFieldStyle(.plain).fieldBox() }
            }
            HStack(spacing: 8) {
                result.help(resultText ?? "")
                Spacer(minLength: 8)
                if verified {
                    Button("Done") { add.close() }.buttonStyle(.pillPrimary).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { add.close() }.buttonStyle(.pill)
                    Button("Save & verify") { saveAndVerify() }.buttonStyle(.pillPrimary).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 8).padding(.leading, 82)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.mnSunk)
        .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
    }

    /// `FormRow` z etykietą 70 pt i ciaśniejszymi marginesami (makieta: `.adding .form-row`, 6/0).
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        FormRow(label: label, labelWidth: 70, content: content)
            .padding(.horizontal, -16).padding(.vertical, -4)
    }

    private var resultText: String? {
        if let id = savedID {
            if model.providerVerifying.contains(id) { return "Verifying…" }
            switch model.providerChecks[id] {
            case .verified(let n)?: return "Verified · \(n) models available"
            case .failed(let why)?: return why
            case nil: return nil
            }
        }
        return add.error
    }

    @ViewBuilder private var result: some View {
        if let id = savedID, model.providerVerifying.contains(id) {
            StateLabel(.progress(nil), "Verifying…")
        } else if let text = resultText {
            StateLabel(verified ? .ok : .bad, text)
        }
    }

    private func saveAndVerify() {
        add.error = nil
        let key = add.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset.needsKey && key.isEmpty { add.error = "Paste your key first."; return }
        // Po błędzie weryfikacji: tylko nowy klucz dla tego samego dostawcy (drugi `addProvider` zablokowałby duplikat nazwy).
        if let id = savedID {
            add.error = model.replaceKey(id, key: key)
            return
        }
        guard let u = URL(string: add.url.trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(u.scheme), u.host() != nil else {
            add.error = "Enter a full address, e.g. https://openrouter.ai/api/v1."
            return
        }
        if let e = model.addProvider(name: add.name, baseURL: u, key: key) {
            add.error = e
        } else {
            let n = add.name.trimmingCharacters(in: .whitespaces)
            add.savedID = model.providers.providers.last { $0.name == n }?.id
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
