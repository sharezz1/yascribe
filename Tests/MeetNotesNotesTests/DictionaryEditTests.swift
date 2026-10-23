import Foundation
import Testing
@testable import MeetNotesNotes

@Suite struct DictionaryEditTests {
    @Test func failedDictionarySavePreservesDraftAndAllowsRetry() {
        let before = UserDictionary(terms: [DictionaryTerm("Zowie")])
        let edited = UserDictionary(terms: [DictionaryTerm("Zowie"), DictionaryTerm("Genesys")])
        var memory = before
        var saves = 0
        var failing = true
        let failure = DictionaryEdit.commit(edited, replacing: before, set: { memory = $0 }, save: {
            saves += 1
            return failing ? "Couldn’t save the dictionary: disk full" : nil
        })
        // Nieudany zapis: pamięć wraca do poprzedniego stanu, komunikat dociera do arkusza, szkic (`edited`) pozostaje u wołającego.
        #expect(failure == "Couldn’t save the dictionary: disk full")
        #expect(memory == before)
        // Ponowna próba z tym samym szkicem po naprawie dysku.
        failing = false
        #expect(DictionaryEdit.commit(edited, replacing: before, set: { memory = $0 }, save: { saves += 1; return nil }) == nil)
        #expect(memory == edited)
        #expect(saves == 2)
    }

    @Test func termNameMatchingAnotherAliasShowsTermError() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Zoom", aliases: [DictionaryAlias("Zoomem")]))
        // (b) nazwa edytowanego Terma = cudzy Alias.
        var thrown: DictionaryError?
        do { try d.upsert(DictionaryTerm("zoomem")) } catch { thrown = error }
        let b = try #require(thrown)
        let pb = DictionaryEdit.presentation(of: b, draftTerm: "zoomem")
        #expect(pb.field == .term)
        #expect(pb.message == "“zoomem” is already an alias of “Zoom”.")
        // (a) Alias edytowanego Terma = cudzy Term.
        thrown = nil
        do { try d.upsert(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoom")])) } catch { thrown = error }
        let a = try #require(thrown)
        let pa = DictionaryEdit.presentation(of: a, draftTerm: "Zowie")
        #expect(pa.field == .alias)
    }

    @Test func otherErrorsLandOnTheirFields() {
        #expect(DictionaryEdit.presentation(of: .emptyTerm, draftTerm: "").field == .term)
        #expect(DictionaryEdit.presentation(of: .duplicateTerm("X"), draftTerm: "X").field == .term)
        #expect(DictionaryEdit.presentation(of: .aliasTaken(alias: "Zoey", by: "Zowie"), draftTerm: "Other").message == "“Zoey” already belongs to “Zowie”.")
        #expect(DictionaryEdit.presentation(of: .invalidCharacters("#x"), draftTerm: " #x ").field == .term)
        #expect(DictionaryEdit.presentation(of: .invalidCharacters("#y"), draftTerm: "X").field == .alias)
    }
}
