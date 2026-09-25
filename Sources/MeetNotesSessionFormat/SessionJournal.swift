import Foundation

public enum JournalError: Error, Equatable {
    case alreadyExists(String)
    case corruptLine(Int)
}

/// Dziennik `journal.jsonl`: jedno zdarzenie na linię, każda linia
/// synchronizowana z dyskiem. Źródło prawdy o sesji (spec rdzenia §5).
public final class SessionJournal: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw JournalError.alreadyExists(url.path)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
    }

    public func append(_ event: JournalEvent) throws {
        var line = try encoder.encode(event)
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try handle.close()
    }

    /// Czyta dziennik. Ostatnia linia może być urwana przez `kill -9` w trakcie
    /// zapisu — jest wtedy pomijana. Uszkodzona linia w środku to błąd.
    public static func read(url: URL) throws -> [JournalEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        // Tylko ostatni fragment BEZ kończącego LF może być urwanym zapisem: append pisze
        // linię razem z LF jednym wywołaniem. Zakończona, a niepoprawna linia to uszkodzenie.
        let unterminatedLast = data.last != 0x0A ? lines.count - 1 : -1
        var events: [JournalEvent] = []
        for (index, line) in lines.enumerated() where !line.isEmpty {
            do {
                events.append(try decoder.decode(JournalEvent.self, from: Data(line)))
            } catch {
                if index == unterminatedLast { break }
                throw JournalError.corruptLine(index + 1)
            }
        }
        return events
    }
}
