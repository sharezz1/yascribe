import Foundation

public enum DataMigrationOutcome: Equatable, Sendable {
    case notNeeded
    case moved
    /// Oba katalogi mają dane: nic nie scalamy ani nie wybieramy za użytkownika.
    case bothHaveData
    case oldAppRunning
    case failed(String)
}

/// Jednorazowe przeniesienie katalogu danych starej aplikacji (`…/MeetNotes`) do nowego (`…/Yascribe`).
/// `moveItem` nie kopiuje ani nie kasuje; każdy błąd zostawia stary katalog nietknięty. Literały starych nazw
/// podaje wywołujący (`YascribeApp`), nie biblioteka.
public struct DataDirectoryMigration: Sendable {
    /// „Znane pliki": katalog ma dane, gdy istnieje którykolwiek z nich.
    static let knownEntries = ["providers.json", "presets.json", "settings.json", "templates.json", "dictionary.json", "sessions"]

    public let oldRoot: URL
    public let newRoot: URL
    public let isOldAppRunning: @Sendable () -> Bool

    public init(oldRoot: URL, newRoot: URL, isOldAppRunning: @escaping @Sendable () -> Bool) {
        self.oldRoot = oldRoot
        self.newRoot = newRoot
        self.isOldAppRunning = isOldAppRunning
    }

    private func hasData(_ root: URL) -> Bool {
        Self.knownEntries.contains { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    /// Wpisy katalogu bez `.DS_Store` (Finder dokłada go po samym otwarciu pustego folderu); `nil` = katalog nie istnieje.
    private func entries(_ root: URL) throws -> [String]? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != ".DS_Store" }
    }

    public func run() -> DataMigrationOutcome {
        guard hasData(oldRoot) else { return .notNeeded }
        do {
            if let existing = try entries(newRoot) {
                if hasData(newRoot) { return .bothHaveData }
                if !existing.isEmpty { return .failed("unexpected files in \(newRoot.path)") }
            }
            if isOldAppRunning() { return .oldAppRunning }
            // Pusty katalog nowej aplikacji = nieistniejący: `moveItem` nie nadpisuje. `rmdir` nie jest rekurencyjne:
            // gdyby druga instancja zdążyła w międzyczasie przenieść dane, odmówi zamiast je skasować.
            if (try entries(newRoot)) != nil {
                try? FileManager.default.removeItem(at: newRoot.appendingPathComponent(".DS_Store"))
                guard rmdir(newRoot.path) == 0 else { return .failed("couldn't remove empty \(newRoot.path) (errno \(errno))") }
            }
            try FileManager.default.moveItem(at: oldRoot, to: newRoot)
            return .moved
        } catch {
            return .failed("\(error)")
        }
    }
}
