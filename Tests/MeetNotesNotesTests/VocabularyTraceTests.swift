import Foundation
import Testing
import MeetNotesNotes

@Suite struct VocabularyTraceTests {
    private func dir() throws -> URL {
        let d = tempDir()
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func savedWithLinesWritesTrace() throws {
        let url = try dir().appendingPathComponent("vocabulary.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        #expect(VocabularyTrace.update(promptLines: "Known names: Zowie.", at: url, correctionSaved: true) == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Known names: Zowie.")
    }

    @Test func savedWithoutLinesRemovesTraceAndMissingFileIsFine() throws {
        let url = try dir().appendingPathComponent("vocabulary.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        #expect(VocabularyTrace.update(promptLines: nil, at: url, correctionSaved: true) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(VocabularyTrace.update(promptLines: nil, at: url, correctionSaved: true) == nil)
    }

    @Test func notSavedLeavesTraceUntouched() throws {
        let url = try dir().appendingPathComponent("vocabulary.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        #expect(VocabularyTrace.update(promptLines: "new", at: url, correctionSaved: false) == nil)
        #expect(VocabularyTrace.update(promptLines: nil, at: url, correctionSaved: false) == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "old")
    }

    @Test func unwritableLocationReturnsError() throws {
        // Katalog przebiegu nie istnieje: zapis musi zwrócić błąd, nie przemilczeć go.
        let url = tempDir().appendingPathComponent("missing").appendingPathComponent("vocabulary.txt")
        #expect(VocabularyTrace.update(promptLines: "x", at: url, correctionSaved: true) != nil)
    }
}
