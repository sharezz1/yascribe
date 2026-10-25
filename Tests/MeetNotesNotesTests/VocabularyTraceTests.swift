import Foundation
import Testing
@testable import MeetNotesNotes

@Suite struct VocabularyTraceTests {
    private func dir() throws -> URL {
        let d = tempDir()
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func savedWithLinesWritesTrace() throws {
        let url = try dir().appendingPathComponent("vocabulary.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        #expect(VocabularyTrace.update(promptLines: "Known names: Nimbu.", at: url, correctionSaved: true) == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Known names: Nimbu.")
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

    @Test func missingFileIsRecognizedInBothErrorDomains() {
        #expect(VocabularyTrace.isMissingFile(CocoaError(.fileNoSuchFile)))
        #expect(VocabularyTrace.isMissingFile(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
        #expect(!VocabularyTrace.isMissingFile(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!VocabularyTrace.isMissingFile(CocoaError(.fileWriteNoPermission)))
    }

    @Test(.enabled(if: getuid() != 0, "root ignoruje bity uprawnień katalogu"))
    func permissionDeniedReturnsErrorAndKeepsPreviousTrace() throws {
        let d = try dir()
        let url = d.appendingPathComponent("vocabulary.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: d.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path) }
        #expect(VocabularyTrace.update(promptLines: "new", at: url, correctionSaved: true) != nil)
        #expect(VocabularyTrace.update(promptLines: nil, at: url, correctionSaved: true) != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        #expect(try String(contentsOf: url, encoding: .utf8) == "old")
    }
}
