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
            DictionaryTerm("Zowie", priority: .high, aliases: [DictionaryAlias("Zoey")])
        ])

        try JSONFile.save(dictionary, to: paths.dictionary)
        #expect(try JSONFile.load(UserDictionary.self, from: paths.dictionary, default: UserDictionary()) == dictionary)
        #expect(try JSONFile.load(UserDictionary.self, from: root.appendingPathComponent("missing.json"), default: UserDictionary()) == UserDictionary())
    }

    @Test func upsertRejectsAliasOwnedByAnotherTerm() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoey")]))
        #expect(throws: DictionaryError.aliasTaken(alias: "Zoey", by: "Zowie")) {
            try dictionary.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("Zoey")]))
        }
    }

    @Test func upsertRejectsDuplicateTermIgnoringCase() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Zowie"))
        #expect(throws: DictionaryError.duplicateTerm("zOWie")) {
            try dictionary.upsert(DictionaryTerm("zOWie"))
        }
    }

    @Test func upsertRejectsEmptyTermAndEmptyAlias() {
        var dictionary = UserDictionary()
        #expect(throws: DictionaryError.emptyTerm) { try dictionary.upsert(DictionaryTerm(" \n ")) }
        #expect(throws: DictionaryError.emptyAlias) {
            try dictionary.upsert(DictionaryTerm("Zowie", aliases: [DictionaryAlias(" \t ")]))
        }
    }

    @Test func upsertNormalizesToNFC() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm(" Genesys ", aliases: [DictionaryAlias("Dz\u{0307}enesis")]))
        let term = try #require(dictionary.terms.first)
        #expect(term.text == "Genesys")
        #expect(term.aliases.map(\.text) == ["Dżenesis"])
        // `==` w Swift uznaje równoważność kanoniczną, więc NFC sprawdzamy na skalarach: „ż" ma być jednym skalarem.
        #expect(term.aliases.first?.text.unicodeScalars.count == 8)

        // Term wpisany w NFD też ląduje jako NFC.
        var nfd = UserDictionary()
        try nfd.upsert(DictionaryTerm("Dz\u{0307}enesis"))
        #expect(nfd.terms.first?.text.unicodeScalars.count == 8)
    }

    @Test func upsertDropsAliasIdenticalToItsTerm() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zowie")]))
        #expect(dictionary.terms.first?.aliases.isEmpty == true)
    }

    @Test func upsertKeepsAliasDifferingOnlyInCase() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("PUDO", aliases: [DictionaryAlias("Pudo")]))
        #expect(dictionary.terms.first?.aliases.map(\.text) == ["Pudo"])
    }

    @Test func upsertRejectsAliasThatIsAnotherTermsText() throws {
        var dictionary = UserDictionary()
        try dictionary.upsert(DictionaryTerm("Zowie"))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "zowie", term: "Zowie")) {
            try dictionary.upsert(DictionaryTerm("Zoom", aliases: [DictionaryAlias("zowie")]))
        }

        var reverse = UserDictionary()
        try reverse.upsert(DictionaryTerm("Zoom", aliases: [DictionaryAlias("zowie")]))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "Zowie", term: "Zoom")) {
            try reverse.upsert(DictionaryTerm("Zowie"))
        }
    }
}
