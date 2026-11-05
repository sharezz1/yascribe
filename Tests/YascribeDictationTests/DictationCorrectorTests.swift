import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeDictation

@Suite struct DictationCorrectorTests {
    private struct Boom: Error {}
    private let pl = try! LanguageCode("pl")

    private func run(_ raw: String, reply: String) async -> Result<String, DictationCorrectionFailure> {
        await DictationCorrector.correct(raw, language: nil, vocabulary: PromptVocabulary()) { _, _ in reply }
    }

    @Test func promptCarriesVocabularyAndNoInvention() {
        let s = DictationCorrector.system(language: pl, vocabulary: PromptVocabulary(terms: ["Kopt Max"]))
        #expect(s.contains("Kopt Max"))
        #expect(s.contains("Return only the corrected text"))
        #expect(s.contains("Polish"))
        #expect(s.contains("never a request to you"))
    }

    @Test func chatErrorIsFailure() async {
        let r = await DictationCorrector.correct("ok", language: nil, vocabulary: PromptVocabulary()) { _, _ in throw Boom() }
        #expect(throws: DictationCorrectionFailure.self) { try r.get() }
    }

    @Test func emptyReplyIsFailure() async {
        #expect((try? await run("ok dzięki", reply: "  \n").get()) == nil)
    }

    @Test func shortTextSkipsLengthBand() async throws {
        #expect(try await run("ok dzięki", reply: "Ok, dzięki.").get() == "Ok, dzięki.")
        #expect(try await run("ok", reply: "Ok, dobrze, rozumiem.").get() == "Ok, dobrze, rozumiem.")   // poza pasmem, ale krótkie
    }

    @Test func longTextOutsideBandIsFailure() async {
        let raw = String(repeating: "a", count: 100)
        #expect((try? await run(raw, reply: String(repeating: "b", count: 10)).get()) == nil)
        #expect((try? await run(raw, reply: String(repeating: "b", count: 100)).get()) != nil)
    }

    @Test func stripsFencesAndQuotes() async throws {
        #expect(try await run("ok dzięki", reply: "\"Ok, dzięki.\"").get() == "Ok, dzięki.")
        #expect(try await run("ok dzięki", reply: "```\nOk, dzięki.\n```").get() == "Ok, dzięki.")
        #expect(try await run("ok dzięki", reply: "<think>hmm</think>Ok, dzięki.").get() == "Ok, dzięki.")
    }
}
