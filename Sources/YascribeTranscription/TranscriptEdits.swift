import Foundation
import YascribeProviders

/// Ręczne poprawki segmentów (TASK-109): nakładka `runs/<runID>/edits.json`, jak `speakers.json`.
/// `transcript.json` i `corrected.json` zostają nietknięte. Klucz: pozycja w `utterances` + mówca + `start` —
/// korekta podmienia tylko tekst pod tym samym indeksem, więc ta sama poprawka trafia w Original i Corrected.
/// shortcut: gdy indeksy się przesuną (Retry Failed Parts w tym samym przebiegu), poprawka jest pomijana, a plik zostaje.
public struct TranscriptEdits: Codable, Equatable, Sendable {
    public struct Edit: Codable, Equatable, Sendable {
        public var index: Int
        public var speaker: Speaker
        public var start: Double
        public var text: String
        public init(index: Int, speaker: Speaker, start: Double, text: String) {
            self.index = index
            self.speaker = speaker
            self.start = start
            self.text = text
        }
    }

    public var edits: [Edit]
    public init(edits: [Edit] = []) { self.edits = edits }

    /// Do wyświetlania: brak albo uszkodzony plik = brak poprawek (nie blokuje otwarcia spotkania).
    public static func load(run: RunDirectory) -> TranscriptEdits? { (try? loadForEditing(run: run)) ?? nil }

    /// Do zapisu: brak pliku = `nil`, uszkodzony plik rzuca — nie nadpisujemy go pustą listą.
    public static func loadForEditing(run: RunDirectory) throws -> TranscriptEdits? {
        try JSONFile.load(TranscriptEdits?.self, from: run.edits, default: nil)
    }

    public func save(run: RunDirectory) throws { try JSONFile.save(self, to: run.edits, createParents: false) }

    /// Poprawka trafia tylko w wypowiedź o tym samym indeksie, mówcy i początku; reszta zostaje bez zmian.
    public func apply(to t: Transcript) -> Transcript {
        var result = t
        for e in edits where Self.matches(e, in: t) { result.utterances[e.index].text = e.text }
        return result
    }

    /// Pusty tekst nic nie zmienia; tekst równy oryginałowi usuwa poprawkę.
    public func setting(_ text: String, at index: Int, of u: Utterance, original: String) -> TranscriptEdits {
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return self }
        var result = self
        result.edits.removeAll { $0.index == index }
        if new != original.trimmingCharacters(in: .whitespacesAndNewlines) {
            result.edits.append(Edit(index: index, speaker: u.speaker, start: u.start, text: new))
        }
        return result
    }

    public func isEdited(index: Int, in t: Transcript) -> Bool { edits.contains { $0.index == index && Self.matches($0, in: t) } }

    /// 1 ms: `start` przechodzi przez JSON jako Double.
    static func matches(_ e: Edit, in t: Transcript) -> Bool {
        guard t.utterances.indices.contains(e.index) else { return false }
        let u = t.utterances[e.index]
        return u.speaker == e.speaker && abs(u.start - e.start) < 0.001
    }
}

public extension RunDirectory {
    var edits: URL { url.appendingPathComponent("edits.json") }
}
