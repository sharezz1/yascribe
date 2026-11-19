import Foundation
import Testing
import YascribeNotes
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-112: Ignore i Add klikane, gdy w tle trwa przeliczanie sugestii (zmiana słownika). Nazwy zmyślone.

private func u(_ text: String) -> Utterance {
    Utterance(speaker: .them, start: 0, end: 2, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

@Suite @MainActor struct AliasSuggestionsAppTests {
    private let nimbu = DictionaryTerm("Nimbu")

    /// AppModel na pustym katalogu danych, jedno spotkanie z dwiema poprawkami „Rokm…” → „Nimbu…” i pierwsze przeliczenie zakończone.
    private func ready() async throws -> (AppModel, AliasSuggestion, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.path, 1)
        let model = AppModel()
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        var item = SessionItem(url: root.appendingPathComponent("s1"), summary: nil, startedAt: Date(),
                               transcript: Transcript(utterances: [u("w Rokmie"), u("Rokma tu")], failedChunks: []), progress: nil)
        item.runID = "run"
        item.corrected = CorrectedTranscript(transcript: Transcript(utterances: [u("w Nimbuie"), u("Nimbua tu")], failedChunks: []),
                                             model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
        model.sessions = [item]
        model.dictionary = UserDictionary(terms: [nimbu])
        await model.suggestionsPublish?.value
        let s = try #require(model.aliasSuggestions.first)
        #expect((s.alias, s.inflects, s.term) == ("Rokm", true, "Nimbu"))
        return (model, s, root)
    }

    /// Zmiana słownika, która nie dotyczy sugestii, ale uruchamia przeliczenie w tle.
    private func startRecount(_ model: AppModel) {
        model.dictionary = UserDictionary(terms: model.dictionary.terms + [DictionaryTerm("Orbit")])
    }

    @Test func ignoreDuringRecountDoesNotComeBack() async throws {
        let (model, s, root) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        startRecount(model)
        #expect(model.dismissSuggestion(s) == nil)
        #expect(model.aliasSuggestions.isEmpty)
        await model.suggestionsPublish?.value
        #expect(model.aliasSuggestions.isEmpty)
    }

    @Test func addDuringRecountRemovesTheRowAtOnceAndAddsTheAliasOnce() async throws {
        let (model, s, root) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        startRecount(model)
        #expect(model.acceptSuggestion(s) == nil)
        #expect(model.aliasSuggestions.isEmpty)
        await model.suggestionsPublish?.value
        #expect(model.aliasSuggestions.isEmpty)
        let aliases = model.dictionary.terms.first { $0.id == nimbu.id }?.aliases ?? []
        #expect(aliases.map(\.text) == ["Rokm"])
    }

    @Test func deletingTheTermDropsItsSuggestionAtOnce() async throws {
        let (model, _, root) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        model.dictionary = UserDictionary(terms: [DictionaryTerm("Orbit")])
        #expect(model.aliasSuggestions.isEmpty)
        await model.suggestionsPublish?.value
        #expect(model.aliasSuggestions.isEmpty)
    }

    @Test func sameInputDoesNotRecount() async throws {
        let (model, _, root) = try await ready()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = model.suggestionsPublish
        model.refreshSuggestions()
        #expect(model.suggestionsPublish == before)
    }
}
