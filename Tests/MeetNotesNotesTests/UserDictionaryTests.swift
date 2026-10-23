import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes

@Suite struct UserDictionaryTests {
    @Test func dictionaryRoundTripsThroughJSONFile() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MeetNotesPaths(root: root)
        let dictionary = UserDictionary(terms: [
            DictionaryTerm("Nimbu", priority: .high, aliases: [DictionaryAlias("Roky")])
        ])

        try JSONFile.save(dictionary, to: paths.dictionary)
        #expect(try JSONFile.load(UserDictionary.self, from: paths.dictionary, default: UserDictionary()) == dictionary)
        #expect(try JSONFile.load(UserDictionary.self, from: root.appendingPathComponent("missing.json"), default: UserDictionary()) == UserDictionary())
    }

    @Test func upsertRejectsAliasOwnedByAnotherTerm() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Roky")]))
        #expect(throws: DictionaryError.aliasTaken(alias: "Roky", by: "Nimbu")) {
            try dictionary.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("Roky")]))
        }
    }

    @Test func upsertRejectsDuplicateTermIgnoringCase() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Nimbu"))
        #expect(throws: DictionaryError.duplicateTerm("nIMbu")) {
            try dictionary.upsert(DictionaryTerm("nIMbu"))
        }
    }

    @Test func upsertRejectsEmptyTermAndEmptyAlias() {
        var dictionary = UserDictionary()
        #expect(throws: DictionaryError.emptyTerm) { try dictionary.upsert(DictionaryTerm(" \n ")) }
        #expect(throws: DictionaryError.emptyAlias) {
            try dictionary.upsert(DictionaryTerm("Nimbu", aliases: [DictionaryAlias(" \t ")]))
        }
    }

    @Test func upsertNormalizesToNFC() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm(" Orbit ", aliases: [DictionaryAlias("Z\u{0307}orbit")]))
        let term = try #require(dictionary.terms.first)
        #expect(term.text == "Orbit")
        #expect(term.aliases.map(\.text) == ["Żorbit"])
        // `==` w Swift uznaje równoważność kanoniczną, więc NFC sprawdzamy na skalarach: „ż" ma być jednym skalarem.
        #expect(term.aliases.first?.text.unicodeScalars.count == 8)
    }

    @Test func upsertDropsAliasIdenticalToItsTerm() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Nimbu")]))
        #expect(dictionary.terms.first?.aliases.isEmpty == true)
    }

    @Test func upsertKeepsAliasDifferingOnlyInCase() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("KOPT", aliases: [DictionaryAlias("Kopt")]))
        #expect(dictionary.terms.first?.aliases.map(\.text) == ["Kopt"])
    }

    @Test func upsertRejectsAliasThatIsAnotherTermsText() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Nimbu"))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "nimbu", term: "Nimbu")) {
            try dictionary.upsert(DictionaryTerm("Zoom", aliases: [DictionaryAlias("nimbu")]))
        }

        var reverse = UserDictionary()
        try reverse.upsert(DictionaryTerm("Zoom", aliases: [DictionaryAlias("nimbu")]))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "Nimbu", term: "Zoom")) {
            try reverse.upsert(DictionaryTerm("Nimbu"))
        }
    }
}
