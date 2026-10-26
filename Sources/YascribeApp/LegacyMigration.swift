import AppKit
import YascribeProviders

/// Przejęcie danych i kluczy po starej aplikacji (MeetNotes → Yascribe). Literały starych nazw żyją tylko tutaj.
/// Pomijane przy `YASCRIBE_DATA_DIR` (`.devdata` nie jest importowane, spec poprawka 2), w trybie migawek i sond:
/// uruchomienie deweloperskie nie ruszy prawdziwych danych ani pęku użytkownika.
@MainActor
enum LegacyMigration {
    private nonisolated static let oldBundleID = "io.github.sharezz1.meetnotes"
    private nonisolated static let oldKeychainService = "meetnotes.provider"

    /// Uruchomienie deweloperskie, migawki albo sonda: nie ruszamy prawdziwych danych ani pęku, nie startujemy Sparkle.
    static var isDevRun: Bool {
        let env = ProcessInfo.processInfo.environment
        return YascribePaths.isOverridden(env) || Snapshots.directory != nil || !(env["YASCRIBE_PROBE"] ?? "").isEmpty
    }

    /// Przed `AppModel()`: model czyta `providers.json` i zapisuje domyślne pliki, więc musi zobaczyć już przeniesiony katalog.
    static func moveDataIfNeeded() {
        guard !isDevRun else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let outcome = DataDirectoryMigration(
            oldRoot: base.appendingPathComponent("MeetNotes"), newRoot: base.appendingPathComponent("Yascribe"),
            isOldAppRunning: {
                // Po identyfikatorze paczki albo nazwie pliku wykonywalnego (uruchomienie bez paczki).
                NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == oldBundleID || $0.executableURL?.lastPathComponent == "MeetNotesApp"
                }
            }).run()
        switch outcome {
        case .notNeeded, .moved:
            return
        case .bothHaveData:
            if !alert("Two data folders found",
                      "Yascribe found data from the old MeetNotes app, but its own data folder isn't empty either. Nothing was moved or merged. "
                      + "Use Yascribe's data, or quit and sort out the two folders yourself.",
                      primary: "Use Yascribe data", secondary: "Quit") { exit(0) }
        case .oldAppRunning:
            _ = alert("Quit MeetNotes first", "Quit the old MeetNotes first, then open Yascribe again.", primary: "Quit")
            exit(0)
        case .failed(let message):
            _ = alert("Couldn't move your data", "Yascribe couldn't take over the data from MeetNotes, so it won't start on an empty folder. "
                      + "The old data wasn't changed.\n\n\(message)", primary: "Quit")
            exit(0)
        }
    }

    /// Po `AppModel()`: UUID dostawców są już wczytane. Stara pozycja pęku zostaje; usuwa ją użytkownik.
    static func migrateKeys(model: AppModel) {
        guard !isDevRun else { return }
        let ids = model.providers.providers.map(\.id)
        guard !ids.isEmpty else { return }
        let root = model.paths.root
        let outcomes = KeyMigration(old: KeychainSecretStore(service: oldKeychainService), new: KeychainSecretStore())
            .run(providerIDs: ids, resolved: KeyMigrationLedger.resolved(root: root))
        KeyMigrationLedger.record(outcomes, root: root)
        var notes: [String] = []
        for id in ids {
            let name = model.provider(id)?.name ?? "a provider"
            switch outcomes[id] {
            case .unreadable: notes.append("Couldn't read the old key for \(name) (access denied). Enter it again in Settings.")
            case .newStoreFailed: notes.append("Couldn't save the key for \(name) in Yascribe's keychain service. Enter it again in Settings.")
            default: break
            }
        }
        if !notes.isEmpty { model.lastError = ([model.lastError].compactMap { $0 } + notes).joined(separator: "\n") }
    }

    /// Modalny alert przed pierwszym oknem; aktywacja, żeby nie wylądował za innymi oknami. `true` = przycisk główny.
    private static func alert(_ title: String, _ text: String, primary: String, secondary: String? = nil) -> Bool {
        NSApplication.shared.activate()
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: primary)
        if let secondary { a.addButton(withTitle: secondary) }
        return a.runModal() == .alertFirstButtonReturn
    }
}
