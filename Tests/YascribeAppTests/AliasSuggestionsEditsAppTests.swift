import Foundation
import Testing
import YascribeNotes
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-116 etap 2: `AppModel` zamienia ręczne poprawki (`edits.json`) na `EditPair`. Nazwy zmyślone.

private func u(_ text: String) -> Utterance {
    Utterance(speaker: .them, start: 0, end: 2, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

@Suite(.serialized) @MainActor struct AliasSuggestionsEditsAppTests {
    private let nimbu = DictionaryTerm("Nimbu")

    private func makeModel(_ root: URL) -> AppModel {
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.path, 1)
        let model = AppModel()
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        return model
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func session(in root: URL, _ utterances: [String]) -> SessionItem {
        var item = SessionItem(url: root.appendingPathComponent("s1"), summary: nil, startedAt: Date(),
                               transcript: Transcript(utterances: utterances.map(u), failedChunks: []), progress: nil)
        item.runID = "run"
        return item
    }

    private func correction(_ utterances: [String]) -> CorrectedTranscript {
        CorrectedTranscript(transcript: Transcript(utterances: utterances.map(u), failedChunks: []),
                            model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    }

    private func edit(_ text: String, at index: Int = 0) -> TranscriptEdits.Edit {
        .init(index: index, speaker: .them, start: 0, text: text)
    }

    /// Sesja bez korekty: sama poprawka wystarcza, także przy pustym słowniku (nowy Term).
    @Test func editWithoutCorrectedProducesSuggestionFromEdits() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie")])
        #expect(AppModel.editPairs(for: item) == [
            AliasSuggestions.EditPair(sessionID: item.id, editKey: "\(item.id)#0", before: "w Rokmie", after: "w Nimbuie"),
        ])

        let model = makeModel(root)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [nimbu])
        model.refreshSuggestions()
        await model.suggestionsPublish?.value
        let s = try #require(model.aliasSuggestions.first)
        #expect(s.fromEdits)
        #expect(!s.isNewTerm)
        #expect((s.alias, s.term) == ("Rokm", "Nimbu"))
    }

    /// Korekta po „Retry Failed Parts" ma inną liczbę wypowiedzi: poprawka liczy się tylko z Original.
    @Test func mismatchedCorrectedTeachesFromOriginalOnly() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie", "Rokma tu"])
        item.corrected = correction(["w Nimbuie", "Nimbua tu", "jeszcze jedno"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie")])
        #expect(AppModel.editPairs(for: item) == [
            AliasSuggestions.EditPair(sessionID: item.id, editKey: "\(item.id)#0", before: "w Rokmie", after: "w Nimbuie"),
        ])

        let model = makeModel(root)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [nimbu])
        model.refreshSuggestions()
        await model.suggestionsPublish?.value
        let s = try #require(model.aliasSuggestions.first)
        #expect(s.fromEdits)
        #expect(s.count == 1)
    }

    /// Edycja wypowiedzi ukrytej (TASK-119) nie uczy: ani pary, ani sugestii.
    @Test func hiddenEditedUtteranceIsSkipped() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie")], hidden: [.init(speaker: .them, start: 0)])
        #expect(AppModel.editPairs(for: item).isEmpty)

        let model = makeModel(root)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [nimbu])
        model.refreshSuggestions()
        await model.suggestionsPublish?.value
        #expect(model.aliasSuggestions.isEmpty)
    }

    /// Odcisk obejmuje indeks i tekst poprawki: zmiana samego tekstu przelicza sugestie.
    @Test func changingEditTextRecounts() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie")])
        let model = makeModel(root)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [nimbu])
        model.refreshSuggestions()
        await model.suggestionsPublish?.value
        let before = model.suggestionsPublish

        item.edits = TranscriptEdits(edits: [edit("w Nimbu")])
        model.sessions = [item]
        model.refreshSuggestions()
        #expect(model.suggestionsPublish != before)
    }

    /// Edycja w Corrected: para musi użyć Corrected, bo Original zawiera też podmiany korektora (LLM).
    @Test func editInCorrectedUsesCorrectedAsBase() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie wczoraj"])
        item.corrected = correction(["w Nimbuie wczoraj"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie dzisiaj")])
        #expect(AppModel.editPairs(for: item) == [
            AliasSuggestions.EditPair(sessionID: item.id, editKey: "\(item.id)#0",
                                      before: "w Nimbuie wczoraj", after: "w Nimbuie dzisiaj"),
        ])
    }

    /// Edycja w Original, która wpisała dokładnie tekst korekty: bazą zostaje Original, bo Corrected nie różni się od poprawki.
    @Test func editInOriginalUsesOriginalAsBase() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie wczoraj"])
        item.corrected = correction(["w Nimbuie wczoraj"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie wczoraj")])
        #expect(AppModel.editPairs(for: item) == [
            AliasSuggestions.EditPair(sessionID: item.id, editKey: "\(item.id)#0",
                                      before: "w Rokmie wczoraj", after: "w Nimbuie wczoraj"),
        ])
    }

    /// Pusty słownik: sama poprawka tworzy sugestię nowego Terma.
    @Test func editWithEmptyDictionaryProposesNewTerm() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = session(in: root, ["w Rokmie"])
        item.edits = TranscriptEdits(edits: [edit("w Nimbuie")])
        let model = makeModel(root)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [])
        model.refreshSuggestions()
        await model.suggestionsPublish?.value
        let s = try #require(model.aliasSuggestions.first)
        #expect(s.fromEdits && s.isNewTerm)
        #expect((s.alias, s.term) == ("Rokmie", "Nimbuie"))
    }
}
