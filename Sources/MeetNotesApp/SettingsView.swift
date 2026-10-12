import MeetNotesProviders
import SwiftUI

final class AddProviderState: ObservableObject {
    @Published var showing = false
    @Published var name = "OpenRouter"
    @Published var url = "https://openrouter.ai/api/v1"
    @Published var key = ""
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var add = AddProviderState()

    var body: some View {
        @Bindable var model = model
        Form {
            SwiftUI.Section("Providers") {
                ForEach(model.providers.providers) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(p.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                            Text((try? model.secrets.get(p.id)).flatMap { $0 }.map(maskedKey) ?? "No key")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await model.refreshModels(p.id) } } label: { Label("Refresh Models", systemImage: "arrow.clockwise") }
                            .help("Refresh the model list")
                        Button(role: .destructive) { model.removeProvider(p.id) } label: { Label("Remove", systemImage: "trash") }
                            .help("Remove this provider and its key")
                    }
                }
                Button("Add Provider…") { add.showing = true }
            }
            SwiftUI.Section("Archive") {
                RoleEditor(title: "Embeddings (whole archive)", role: .embedding, assignment: $model.settings.embedding, language: nil)
                Text("Changing the embedding model re-indexes the whole archive, never part of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Setup") {
                Button("Check Permissions…") { model.showSetup = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: model.settings) { model.save() }
        .sheet(isPresented: $add.showing) {
            Form {
                TextField("Name", text: $add.name)
                TextField("Base URL", text: $add.url)
                SecureField("API key", text: $add.key)
                HStack {
                    Button("Cancel") { add.showing = false }
                    Spacer()
                    Button("Add") {
                        if let u = URL(string: add.url) { model.addProvider(name: add.name, baseURL: u, key: add.key) }
                        add.key = ""
                        add.showing = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 420)
        }
    }
}
