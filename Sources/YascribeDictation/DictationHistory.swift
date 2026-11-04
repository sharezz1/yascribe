import Foundation

/// Jeden wpis historii dyktowania. Tylko tekst, bez audio. Nowe pola są opcjonalne (stare pliki się czytają).
public struct DictationEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var raw: String
    public var text: String
    public var correctionFailed: Bool?
    public var app: String?
    public var seconds: Double?
    public var asrModel: String?
    public var correctionModel: String?
    /// `false` = tekst trafił tylko do schowka (brak uprawnienia Accessibility albo secure input).
    public var inserted: Bool?

    public init(id: UUID = UUID(), date: Date = Date(), raw: String = "", text: String = "", correctionFailed: Bool? = nil,
                app: String? = nil, seconds: Double? = nil, asrModel: String? = nil, correctionModel: String? = nil,
                inserted: Bool? = nil) {
        self.id = id; self.date = date; self.raw = raw; self.text = text; self.correctionFailed = correctionFailed
        self.app = app; self.seconds = seconds; self.asrModel = asrModel; self.correctionModel = correctionModel
        self.inserted = inserted
    }
}

/// Zawartość `dictation-history.json` (`YascribePaths.dictationHistory`), najnowsze na początku.
public struct DictationHistoryFile: Codable, Equatable, Sendable {
    public static let limit = 1000

    public var entries: [DictationEntry]

    public init(entries: [DictationEntry] = []) { self.entries = entries }

    public mutating func add(_ e: DictationEntry) {
        entries.insert(e, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func clear() {
        entries.removeAll()
    }

    /// Dni malejąco; w dniu wpisy malejąco po czasie.
    public func days(calendar: Calendar) -> [(day: Date, entries: [DictationEntry])] {
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, entries: groups[day, default: []].sorted { $0.date > $1.date })
        }
    }
}
