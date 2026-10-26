import Foundation

/// Nazwy plików w katalogu sesji (spec rdzenia §5) i odtwarzanie podsumowania.
public struct SessionDirectory: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var journalURL: URL { url.appendingPathComponent("journal.jsonl") }
    public var summaryURL: URL { url.appendingPathComponent("session.json") }
    public func trackURL(_ trackID: String) -> URL { url.appendingPathComponent("\(trackID).caf") }

    /// Czyta dziennik i odtwarza podsumowanie. Dla ścieżek bez `track.closed`
    /// (awaria) liczbę ramek wylicza z rozmiaru pliku CAF.
    public func summarize() throws -> SessionSummary {
        var summary = try SessionSummary.rebuild(from: SessionJournal.read(url: journalURL))
        for i in summary.tracks.indices where summary.tracks[i].frames == nil && summary.tracks[i].channels > 0 {
            let path = trackURL(summary.tracks[i].id).path
            if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int {
                summary.tracks[i].frames = CAFLayout.frames(fileSize: size, channels: summary.tracks[i].channels)
            }
        }
        return summary
    }

    /// Jak `summarize()`, a wynik zapisuje do `session.json`.
    @discardableResult
    public func rebuildSummaryFile() throws -> SessionSummary {
        let s = try summarize()
        try s.write(to: summaryURL)
        return s
    }
}
