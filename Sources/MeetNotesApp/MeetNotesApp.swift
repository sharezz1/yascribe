import SwiftUI

/// 🔴 Bez Xcode nie ma pluginu `SwiftUIMacros`, a w SDK macOS 27 `@State`,
/// `@Entry`, `@Animatable` i `#Preview` są makrami. Nie używamy ich: model
/// aplikacji jest stałą struktury `App` (tworzonej raz), a stan lokalny widoków
/// mieszka w `ObservableObject` pod `@StateObject` (zwykłe opakowanie właściwości).
@main
struct MeetNotesApp: App {
    private let model = AppModel()

    init() {
        if Snapshots.directory != nil {
            let model = self.model
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshots.runAll(model: model) } }
        }
    }

    var body: some Scene {
        WindowGroup("MeetNotes") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            // 🔀 Odstępstwo 3 (macos.md §10): ustawienia są zakładką, ale Settings… i Cmd-, zostają.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Recording") {
                Button(model.recording.isRecording ? "Stop Recording" : "Record Meeting") {
                    model.recording.isRecording ? model.recording.stop() : model.startRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Show Recording Window") { model.recording.showPanel(model: model) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.section) {
                SwiftUI.Section {
                    Label(Section.meetings.rawValue, systemImage: Section.meetings.symbol).tag(Section.meetings)
                }
                SwiftUI.Section("Setup") {
                    ForEach([Section.presets, .templates, .settings]) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch model.section {
            case .meetings: MeetingsView()
            case .presets: PresetsView()
            case .templates: TemplatesView()
            case .settings: SettingsView()
            case .tasks: LaterPhaseView(title: "Tasks", text: "Tasks with owners across meetings arrive with notes and speaker identity.")
            case .dictation: LaterPhaseView(title: "Dictation", text: "Dictation arrives in a later phase.")
            case .dictionary: LaterPhaseView(title: "Dictionary", text: "Your vocabulary and corrections from transcripts will live here.")
            }
        }
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct LaterPhaseView: View {
    let title: String
    let text: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "clock", description: Text(text))
    }
}
