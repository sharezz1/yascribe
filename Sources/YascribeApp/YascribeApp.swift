import SwiftUI
import YascribeUpdates

/// 🔴 Bez Xcode nie ma pluginu `SwiftUIMacros`, a w SDK macOS 27 `@State`,
/// `@Entry`, `@Animatable` i `#Preview` są makrami. Nie używamy ich: model
/// aplikacji jest stałą struktury `App` (tworzonej raz), a stan lokalny widoków
/// mieszka w `ObservableObject` pod `@StateObject` (zwykłe opakowanie właściwości).
@main
struct YascribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model: AppModel

    init() {
        // Migracja katalogu danych przed `AppModel()`: model od razu czyta pliki i zapisuje domyślne.
        LegacyMigration.moveDataIfNeeded()
        Probes.runIfRequested()
        model = AppModel()
        AppDelegate.model = model
        LegacyMigration.migrateKeys(model: model)
        if Snapshots.directory != nil {
            let model = self.model
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshots.runAll(model: model) } }
        } else {
            model.monitor.start()
        }
    }

    var body: some Scene {
        // `id`: „Open note” w pigułce otwiera okno na nowo, gdy użytkownik je zamknął (`openWindow(id: "main")`).
        WindowGroup("Yascribe", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            // Po „About Yascribe”: Sparkle pyta o nową wersję, a instalacja nigdy nie przerywa nagrania (RestartGate).
            CommandGroup(after: .appInfo) { CheckForUpdatesButton(updater: model.updater) }
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
                // Pigułka jest widoczna tylko podczas nagrywania; ta pozycja wynosi ją na wierzch i wciąga na ekran.
                Button("Show Recording Window") { model.recording.showPanel(model: model) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(!model.recording.isRecording)
            }
            // D5 (macos.md §3): każda akcja z paska widoku spotkania jest też tutaj; aktywne tylko przy otwartym spotkaniu.
            CommandMenu("Meeting") {
                Button("Back to Meetings") { model.selectedSessionID = nil }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.openItem == nil)
                Button("Copy Notes") { if let i = model.openItem { model.copyNotes(i) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.openItem?.notes.summary == nil)
                // Bez skrótu: Cmd-Shift-R i Cmd-Opt-R zajmuje nagrywanie.
                Button("Show in Finder") { if let i = model.openItem { model.showInFinder(i) } }
                    .disabled(model.openItem == nil)
                // Uwaga 7 pkt 5: odtwarzanie przeniesione z paska; bez skrótu Spacja (koliduje z pisaniem w My notes).
                PlayRecordingButton()
                Divider()
                // Bez skrótu: ⌘⌫ w edytorze My notes kasuje do początku linii, menu by go przechwyciło.
                Button("Delete Meeting…") { model.pendingDelete = model.openItem?.id }
                    .disabled(model.openItem.map { !model.canDelete($0) } ?? true)
            }
        }
        // Aplikacja żyje po zamknięciu okna (SwiftUI nie kończy jej po ostatnim oknie); ikona w Docku zostaje.
        MenuBarExtra("Yascribe", systemImage: "waveform") {
            MenuBarMenu().environment(model)
        }
    }
}

/// Delegat aplikacji: druga bariera przed zakończeniem w trakcie nagrania (⌘Q, wylogowanie, restart Sparkle bez odroczenia).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, !model.confirmTermination() else { return .terminateNow }
        return .terminateCancel
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
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
            case .dictionary: DictionaryView()
            }
        }
        .tint(.mnAccent) // 🔀 odstępstwo 5 (macos.md §10): stały akcent w treści
        // Uwaga 1 z odbioru 2026-10-16 (§11.5): pasek bez własnego tła i tytułu; ciepłe tło do górnej krawędzi.
        // `navigationTitle` zostaje w widokach — nazwa okna w menu Window i dla VoiceOver.
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

/// Sidebar (D7, macos.md §11.5): Meetings na górze; Presets / Templates / Dictionary / Settings na dole, bez nagłówka sekcji.
/// Dolna grupa to druga lista z tym samym wyborem, przypięta `safeAreaInset` (lista nie umie dosunąć wierszy do dołu).
struct SidebarList: View {
    @Binding var selection: Section

    var body: some View {
        List(selection: $selection) {
            Label(Section.meetings.rawValue, systemImage: Section.meetings.symbol).tag(Section.meetings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            List(selection: $selection) {
                ForEach([Section.presets, .templates, .dictionary, .settings]) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s)
                }
            }
            .scrollDisabled(true)
            .frame(height: 4 * 28 + 16)
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
