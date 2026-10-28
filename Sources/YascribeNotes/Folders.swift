import Foundation

/// Folder spotkania (TASK-26): grupa logiczna, nie katalog nagrań. `id` stabilne (UUID), więc zmiana nazwy
/// nie rusza ani sesji, ani jej `folderID`. Przypisanie nie przenosi plików audio.
public struct MeetingFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

public enum FolderError: Error, Equatable, LocalizedError {
    case emptyName
    case tooLong(Int)
    case duplicate(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Give the folder a name."
        case .tooLong(let max): "A folder name can have at most \(max) characters."
        case .duplicate(let name): "A folder named “\(name)” already exists."
        case .notFound: "That folder no longer exists."
        }
    }
}

/// `folders.json` w katalogu danych. Brak pliku = brak folderów; stare dane bez `folderID` czytają się bez zmian.
public struct FoldersFile: Codable, Equatable, Sendable {
    public var folders: [MeetingFolder] = []
    public static let maxNameLength = 60

    public init(folders: [MeetingFolder] = []) { self.folders = folders }

    /// Białe znaki zwinięte do jednej spacji, końce przycięte.
    public static func normalize(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Folder o tym `id`; `nil` także dla nieznanego id (sesja po usuniętym folderze jest „No folder").
    public func folder(_ id: String?) -> MeetingFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public func nameError(_ name: String, excluding: String? = nil) -> FolderError? {
        let n = Self.normalize(name)
        if n.isEmpty { return .emptyName }
        if n.count > Self.maxNameLength { return .tooLong(Self.maxNameLength) }
        let clash = folders.contains {
            $0.id != excluding && $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return clash ? .duplicate(n) : nil
    }

    @discardableResult
    public mutating func create(_ name: String) throws -> MeetingFolder {
        if let error = nameError(name) { throw error }
        let folder = MeetingFolder(name: Self.normalize(name))
        folders.append(folder)
        return folder
    }

    public mutating func rename(_ id: String, to name: String) throws {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { throw FolderError.notFound }
        if let error = nameError(name, excluding: id) { throw error }
        folders[i].name = Self.normalize(name)
    }

    /// Usuwa sam folder: spotkania zostają, tylko tracą przypisanie (`folderID` wskazuje wtedy na nic).
    @discardableResult
    public mutating func delete(_ id: String) -> Bool {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders.remove(at: i)
        return true
    }
}
