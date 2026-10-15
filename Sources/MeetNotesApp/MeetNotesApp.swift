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
            SidebarList(selection: $model.section)
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
        .tint(.mnAccent) // 🔀 odstępstwo 5 (macos.md §10): stały akcent w treści
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

/// Sidebar (D7, macos.md §11.5): Meetings na górze; Presets / Templates / Settings na dole, bez nagłówka sekcji.
/// Dolna grupa to druga lista z tym samym wyborem, przypięta `safeAreaInset` (lista nie umie dosunąć wierszy do dołu).
struct SidebarList: View {
    @Binding var selection: Section

    var body: some View {
        List(selection: $selection) {
            Label(Section.meetings.rawValue, systemImage: Section.meetings.symbol).tag(Section.meetings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            List(selection: $selection) {
                ForEach([Section.presets, .templates, .settings]) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s)
                }
            }
            .scrollDisabled(true)
            .frame(height: 3 * 28 + 16)
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
