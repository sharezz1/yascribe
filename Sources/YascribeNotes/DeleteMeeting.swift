import Foundation

/// Bramka usuwania spotkania (TASK-25). Jeden punkt decyzji dla przycisku, menu i potwierdzenia:
/// `nil` = wolno, tekst = powód odmowy pokazywany użytkownikowi.
public enum DeleteMeeting {
    public static func blocker(recording: Bool, busy: Bool, moving: Bool) -> String? {
        if moving { return "Meetings are being moved to a new folder. Delete this one when that finishes." }
        if recording { return "This meeting is being recorded. Stop the recording before deleting it." }
        if busy { return "This meeting is still being processed. Delete it when that finishes." }
        return nil
    }
}

/// Dokąd idzie usunięte spotkanie (TASK-25): produkcja — systemowy Kosz. Kopia do odbioru GUI (build DEBUG)
/// może wskazać testowy katalog, żeby nie ruszać Kosza użytkownika. Nieprawidłowy katalog to błąd,
/// nigdy cichy powrót do Kosza użytkownika.
public enum MeetingTrash {
    /// Zmienna czytana tylko w buildzie DEBUG (`AppModel`); produkcja jej nie widzi.
    public static let testDirectoryVariable = "YASCRIBE_TEST_TRASH_DIR"

    public enum Destination: Equatable, Sendable {
        case systemTrash
        case directory(URL)
    }

    public enum TrashError: Error, Equatable, LocalizedError {
        case invalidTestDirectory(String)

        public var errorDescription: String? {
            switch self {
            case .invalidTestDirectory(let path):
                "The test Trash folder “\(path)” must be an existing folder inside the app's data folder."
            }
        }
    }

    /// Pusta/`nil` wartość = Kosz systemowy. Testowy katalog musi istnieć i leżeć wewnątrz `dataRoot`
    /// (po rozwiązaniu dowiązań); `dataRoot` równy katalogowi też nie wystarcza — to nie jest „podkatalog”.
    public static func destination(requested: String?, dataRoot: URL?) throws -> Destination {
        guard let requested, !requested.trimmingCharacters(in: .whitespaces).isEmpty else { return .systemTrash }
        guard let dataRoot else { throw TrashError.invalidTestDirectory(requested) }
        let fm = FileManager.default
        let target = URL(fileURLWithPath: requested).standardizedFileURL.resolvingSymlinksInPath()
        let root = dataRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TrashError.invalidTestDirectory(requested)
        }
        // Granica ścieżki: `/data-evil` nie jest wnętrzem `/data`, a sam `/data` nie jest „podkatalogiem”.
        guard target.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") else {
            throw TrashError.invalidTestDirectory(requested)
        }
        return .directory(target)
    }
}
