import Foundation
import YascribeNotes

/// Trwały zakres rozmowy: identyfikator (wszystko / bez folderu / folder / spotkanie), nie etykieta ani bieżąca selekcja listy.
/// Członkostwo jest rozwiązywane na nowo przy każdym pytaniu; zniknięty folder albo spotkanie = brak zakresu (nigdy „All meetings").
struct ArchiveScopeRef: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case all, unfiled, folder, meeting }
    var kind: Kind
    var id: String?

    static let all = ArchiveScopeRef(kind: .all, id: nil)
    static let unfiled = ArchiveScopeRef(kind: .unfiled, id: nil)
    static func folder(_ id: String) -> ArchiveScopeRef { ArchiveScopeRef(kind: .folder, id: id) }
    static func meeting(_ id: String) -> ArchiveScopeRef { ArchiveScopeRef(kind: .meeting, id: id) }

    var isValid: Bool {
        switch kind {
        case .all, .unfiled: id == nil
        case .folder, .meeting: id.map { !$0.isEmpty && $0.count <= 200 } ?? false
        }
    }

    /// `folderName(id)`: nazwa istniejącego folderu, `nil` = nie ma takiego folderu (`id == nil` też).
    func resolve(sessions: [SessionItem], folderID: (SessionItem) -> String?,
                 folderName: (String?) -> String?) -> (ids: Set<String>, label: String)? {
        switch kind {
        case .all:
            return (Set(sessions.map(\.id)), "All meetings")
        case .unfiled:
            return (Set(sessions.filter { folderName(folderID($0)) == nil }.map(\.id)), "No folder")
        case .folder:
            guard let id, let name = folderName(id) else { return nil }
            return (Set(sessions.filter { folderID($0) == id }.map(\.id)), name)
        case .meeting:
            guard let id, let item = sessions.first(where: { $0.id == id }) else { return nil }
            return ([id], "This meeting: \(item.title)")
        }
    }
}

enum ArchivePresentation {
    static func format(_ key: String, _ arguments: CVarArg..., bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: key, value: nil, table: nil), arguments: arguments)
    }

    static func scope(_ label: String, ref: ArchiveScopeRef?, bundle: Bundle = .main) -> String {
        guard let ref else { return label }
        switch ref.kind {
        case .all: return bundle.localizedString(forKey: "All meetings", value: nil, table: nil)
        case .unfiled: return bundle.localizedString(forKey: "No folder", value: nil, table: nil)
        case .folder: return label
        case .meeting:
            let prefix = "This meeting: "
            guard label.hasPrefix(prefix) else { return label }
            return format("This meeting: %@", String(label.dropFirst(prefix.count)), bundle: bundle)
        }
    }

    static func message(_ text: String, scopeLabel: String? = nil, scope: ArchiveScopeRef? = nil, bundle: Bundle = .main) -> String {
        if let scopeLabel, let scope {
            let displayedScope = self.scope(scopeLabel, ref: scope, bundle: bundle)
            if text == "No meetings with transcripts or notes in \(scopeLabel)." {
                return format("No meetings with transcripts or notes in %@.", displayedScope, bundle: bundle)
            }
            if text == "I couldn't find a supported answer in \(scopeLabel)." {
                return format("I couldn't find a supported answer in %@.", displayedScope, bundle: bundle)
            }
        }
        let known = [
            "Choose an embedding model in Settings → Archive search to ask about your meetings.",
            "Choose an Ask model in Settings → Archive search to ask about your meetings.",
            "A meeting or the Ask model changed while answering. Ask again.",
            "The embedding model changed. Ask again.", "The Ask model changed. Ask again.",
            "This chat's folder or meeting no longer exists. Start a new chat.",
            "This chat is full. Start a new chat.", "This answer was interrupted when Yascribe closed. Ask again.",
            "Meetings are being moved to a new folder. Ask again when that finishes.",
            "Open a meeting first, or choose All meetings.", "No provider is available.",
            "This provider is no longer available.", "This provider no longer exists.", "Checking your settings…", "Preparing the index…",
            "Searching your meetings…", "Answering…",
            "The embedding model returned vectors of a different size than the archive index uses.",
            "The embedding model returned an unusable vector.",
            "The model's Context window is too small to answer from your meetings.",
            "the chats folder is a symbolic link", "the chat file is a symbolic link", "invalid chat content",
            "the chat is too large", "unexpected file name", "symbolic link", "file too large",
            "id does not match the file name", "invalid content"
        ]
        if known.contains(text) { return bundle.localizedString(forKey: text, value: nil, table: nil) }
        for (prefix, key) in [("Couldn't search with ", "Couldn't search with %@: %@"),
                              ("Couldn't get an answer from ", "Couldn't get an answer from %@: %@"),
                              ("Couldn't index your meetings with ", "Couldn't index your meetings with %@: %@")] {
            if text.hasPrefix(prefix), let range = text.range(of: ": ", range: text.index(text.startIndex, offsetBy: prefix.count)..<text.endIndex) {
                let provider = String(text[text.index(text.startIndex, offsetBy: prefix.count)..<range.lowerBound])
                let reason = String(text[range.upperBound...])
                return format(key, provider, message(reason, bundle: bundle), bundle: bundle)
            }
        }
        let keyPrefix = "Couldn't read the API key for "
        let keySeparator = " from Keychain: "
        if text.hasPrefix(keyPrefix), let range = text.range(of: keySeparator) {
            let provider = String(text[text.index(text.startIndex, offsetBy: keyPrefix.count)..<range.lowerBound])
            return format("Couldn't read the API key for %@ from Keychain: %@", provider, String(text[range.upperBound...]), bundle: bundle)
        }
        let missingPrefix = "No API key for "
        let missingSuffix = ". Remove the provider and add it again with a key."
        if text.hasPrefix(missingPrefix), text.hasSuffix(missingSuffix) {
            return format("No API key for %@. Remove the provider and add it again with a key.",
                          String(text.dropFirst(missingPrefix.count).dropLast(missingSuffix.count)), bundle: bundle)
        }
        let speechSuffix = " does only speech-to-text."
        if text.hasSuffix(speechSuffix) {
            return format("%@ does only speech-to-text.", String(text.dropLast(speechSuffix.count)), bundle: bundle)
        }
        return text
    }
}

/// Jedna zapisana rozmowa (`chats/<UUID>.json`). Bez wektorów, kluczy i ustawień dostawcy: tylko pytania, odpowiedzi,
/// źródła (puste wektory) i odciski spotkań z przypisów, które pilnują świeżości kontekstu po restarcie.
struct ArchiveConversation: Codable, Equatable {
    struct Turn: Codable, Equatable {
        enum Kind: String, Codable { case working, answered, noAnswer, failed, cancelled }
        var id: UUID
        var question: String
        var scopeLabel: String
        var scopeIDs: [String]
        var kind: Kind
        var text: String?
        var sources: [ArchiveIndex.Chunk]?
        var opensSettings: Bool?
        var fingerprints: [String: String]?
    }

    static let currentVersion = 1
    static let maxTurns = 200
    static let maxTitleChars = 60

    var version: Int?
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var scope: ArchiveScopeRef?
    var turns: [Turn]

    static func title(from question: String) -> String {
        let line = question.split(whereSeparator: \.isNewline).first.map(String.init) ?? question
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= maxTitleChars ? trimmed : String(trimmed.prefix(maxTitleChars - 1)) + "…"
    }

    /// Zdekodowane dane to dane nieufne: ograniczenia rozmiaru i spójność, zanim cokolwiek trafi do modelu.
    var isValid: Bool {
        guard (version ?? 1) <= Self.currentVersion, title.count <= Self.maxTitleChars + 1, turns.count <= Self.maxTurns,
              scope?.isValid ?? true, Set(turns.map(\.id)).count == turns.count else { return false }
        return turns.allSatisfy { turn in
            turn.question.count <= ArchiveAsk.maxQuestionChars && turn.scopeLabel.count <= 300
                && turn.scopeIDs.count <= 100_000 && (turn.text?.count ?? 0) <= 200_000 && (turn.sources?.count ?? 0) <= 50
                && (turn.sources?.allSatisfy { source in
                    source.start.map { $0 >= 0 && $0 <= Double(Int32.max) } ?? true
                } ?? true)
        }
    }
}

/// Wiersz listy „Past chats".
struct ArchiveChatSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let turns: Int
    let scope: ArchiveScopeRef?
}

/// Magazyn rozmów: jeden plik na rozmowę, zapis atomowy i synchroniczny (po powrocie z `save` plik już jest na dysku,
/// więc szybkie zamknięcie aplikacji nie gubi ukończonej odpowiedzi). Własny koder/dekoder — `JSONFile` ma wspólne statyczne
/// instancje, których nie wolno używać równolegle z zapisem indeksu w tle. Dowiązania symboliczne są odrzucane.
struct ArchiveConversationStore {
    static let maxFileBytes = 8_000_000
    let directory: URL

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    struct StoreError: Error, LocalizedError {
        var errorDescription: String?
    }

    func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    func save(_ conversation: ArchiveConversation) throws {
        guard !isSymlink(directory) else { throw StoreError(errorDescription: "the chats folder is a symbolic link") }
        let target = url(for: conversation.id)
        guard !isSymlink(target) else { throw StoreError(errorDescription: "the chat file is a symbolic link") }
        var stored = conversation
        stored.version = ArchiveConversation.currentVersion
        for i in stored.turns.indices {
            stored.turns[i].sources = stored.turns[i].sources?.map { var chunk = $0; chunk.vector = Data(); return chunk }
        }
        guard stored.isValid else { throw StoreError(errorDescription: "invalid chat content") }
        let data = try Self.encoder.encode(stored)
        guard data.count <= Self.maxFileBytes else { throw StoreError(errorDescription: "the chat is too large") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    /// Plik musi mieć nazwę `<UUID>.json`, tożsamy `id` w środku, rozsądny rozmiar i nie być dowiązaniem.
    func load(fileURL file: URL) throws -> ArchiveConversation {
        let name = file.deletingPathExtension().lastPathComponent
        guard file.pathExtension == "json", let fileID = UUID(uuidString: name) else { throw StoreError(errorDescription: "unexpected file name") }
        guard !isSymlink(file) else { throw StoreError(errorDescription: "symbolic link") }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maxFileBytes else { throw StoreError(errorDescription: "file too large") }
        var conversation = try Self.decoder.decode(ArchiveConversation.self, from: Data(contentsOf: file))
        guard conversation.id == fileID else { throw StoreError(errorDescription: "id does not match the file name") }
        guard conversation.isValid else { throw StoreError(errorDescription: "invalid content") }
        for i in conversation.turns.indices {
            conversation.turns[i].sources = conversation.turns[i].sources?.map { var chunk = $0; chunk.vector = Data(); return chunk }
        }
        return conversation
    }

    func load(_ id: UUID) throws -> ArchiveConversation {
        guard !isSymlink(directory) else { throw StoreError(errorDescription: "the chats folder is a symbolic link") }
        return try load(fileURL: url(for: id))
    }

    /// Poprawne rozmowy (najnowsza aktywność pierwsza) i liczba plików, których nie dało się wczytać.
    func list() -> (chats: [ArchiveChatSummary], problems: Int) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0) }
        guard !isSymlink(directory) else { return ([], 1) }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return ([], 1) }
        var chats: [ArchiveChatSummary] = []
        var problems = 0
        for file in files where file.pathExtension == "json" {
            guard let c = try? load(fileURL: file) else { problems += 1; continue }
            chats.append(ArchiveChatSummary(id: c.id, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt,
                                            turns: c.turns.count, scope: c.scope))
        }
        chats.sort { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
        return (chats, problems)
    }
}
