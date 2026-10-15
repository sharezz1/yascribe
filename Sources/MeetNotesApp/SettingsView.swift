import MeetNotesProviders
import SwiftUI

final class AddProviderState: ObservableObject {
    @Published var showing = false
    @Published var preset = ProviderPreset.openRouter
    @Published var name = ProviderPreset.openRouter.name
    @Published var url = ProviderPreset.openRouter.baseURL
    @Published var key = ""
    @Published var error: String?

    /// Kafelek podstawia gotowy adres i nazwę; użytkownik wkleja tylko klucz (Ollama — bez klucza).
    func reset(_ p: ProviderPreset = .openRouter) { preset = p; name = p.name; url = p.baseURL; key = ""; error = nil }
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
                        checkLabel(p)
                        Button { Task { await model.refreshModels(p.id) } } label: { Label("Refresh Models", systemImage: "arrow.clockwise") }
                            .help("Refresh the model lists")
                        Button(role: .destructive) { model.removeProvider(p.id) } label: { Label("Remove", systemImage: "trash") }
                            .help("Remove this provider and its key")
                    }
                }
                HStack {
                    Text("Add provider").foregroundStyle(.secondary)
                    ForEach(ProviderPreset.all) { preset in
                        Button(preset.name) { add.reset(preset); add.showing = true }
                            .help(preset.note ?? preset.baseURL)
                    }
                }
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

    /// Verified · N models / powód / Verifying / Not verified + ponowna próba.
    @ViewBuilder private func checkLabel(_ p: Provider) -> some View {
        if model.providerVerifying.contains(p.id) {
            ProgressView().controlSize(.small)
        } else {
            switch model.providerChecks[p.id] {
            case .verified(let n)?:
                Label("Verified · \(n) models", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .failed(let why)?:
                Label(why, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red).lineLimit(2).help(why)
            case nil:
                Text("Not verified").font(.caption).foregroundStyle(.secondary)
            }
            Button("Verify") { Task { await model.verifyProvider(p.id) } }
                .help("Test the connection (lists the provider's models)")
        }
    }

    private var addSheet: some View {
        Form {
            Text("Add \(add.preset.name)").font(.headline)
            if let note = add.preset.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            TextField("Name", text: $add.name)
            TextField("Base URL", text: $add.url)
            if add.preset.needsKey { SecureField("API key", text: $add.key) }
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
                        add.reset(add.preset)
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
