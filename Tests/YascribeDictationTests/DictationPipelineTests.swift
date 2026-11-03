import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeDictation

private actor Calls {
    var count = 0
    var shape: ASRShape?
    func note(_ s: ASRShape) { count += 1; shape = s }
}

private struct Stub: TranscriptionClient {
    let provider = Provider(name: "Stub", baseURL: URL(string: "http://localhost:1")!)
    let reply: Result<String, Error>
    let calls = Calls()
    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        await calls.note(shape)
        return TranscriptionResult(text: try reply.get(), words: nil)
    }
}

private struct Boom: Error {}
private let pcm = [Int16](repeating: 100, count: 16_000)   // 1 s

@Suite struct DictationPipelineTests {
    private func input(_ stub: Stub, pcm: [Int16] = pcm, shape: ASRShape = .audioTranscriptions, chat: ChatFunction? = nil,
                       fillers: [String]? = nil, replacement: ReplacementRules = ReplacementRules(UserDictionary())) -> DictationPipelineInput {
        DictationPipelineInput(pcm: pcm, language: nil, asrModel: "m", transcriber: stub, shape: shape, chat: chat,
                               vocabulary: PromptVocabulary(), removeFillers: fillers, replacement: replacement)
    }
    private func stub(_ s: String) -> Stub { Stub(reply: .success(s)) }

    @Test func tooShortAudioSkipsModel() async throws {
        let s = stub("hej")
        let out = try await DictationPipeline.run(input(s, pcm: [Int16](repeating: 1, count: 4000)))
        #expect(out == nil)
        #expect(await s.calls.count == 0)
    }

    @Test func emptyTranscriptIsNil() async throws {
        #expect(try await DictationPipeline.run(input(stub("  \n"))) == nil)
    }

    @Test func correctionOffNeverCallsChat() async throws {
        let out = try await DictationPipeline.run(input(stub("cześć"), chat: nil))
        #expect(out == DictationOutput(raw: "cześć", text: "cześć", correctionFailed: false))
    }

    @Test func correctionAppliedWhenOk() async throws {
        let out = try await DictationPipeline.run(input(stub("ok dzięki"), chat: { _, _ in "Ok, dzięki." }))
        #expect(out == DictationOutput(raw: "ok dzięki", text: "Ok, dzięki.", correctionFailed: false))
    }

    @Test func correctionFailureFallsBackToRaw() async throws {
        let d = UserDictionary(terms: [DictionaryTerm("Kopt Max", aliases: [DictionaryAlias("kopt max")])])
        let out = try await DictationPipeline.run(input(stub("kopt max działa"), chat: { _, _ in throw Boom() },
                                                        replacement: ReplacementRules(d)))
        #expect(out == DictationOutput(raw: "kopt max działa", text: "Kopt Max działa", correctionFailed: true))
    }

    @Test func fillersAndReplacementApplied() async throws {
        let d = UserDictionary(terms: [DictionaryTerm("Kopt Max", aliases: [DictionaryAlias("kopt max")])])
        let out = try await DictationPipeline.run(input(stub("yyy kopt max"), fillers: FillerWords.defaults, replacement: ReplacementRules(d)))
        #expect(out?.text == "Kopt Max")
        #expect(out?.raw == "yyy kopt max")
    }

    @Test func asrErrorPropagates() async {
        await #expect(throws: Boom.self) { _ = try await DictationPipeline.run(input(Stub(reply: .failure(Boom())))) }
    }

    @Test func allFillerUtteranceIsNil() async throws {
        #expect(try await DictationPipeline.run(input(stub("yyy mhm"), fillers: FillerWords.defaults)) == nil)
        #expect(try await DictationPipeline.run(input(stub("Yyy, mhm."), fillers: FillerWords.defaults)) == nil)
        #expect(try await DictationPipeline.run(input(stub("yyy mhm"), fillers: nil))?.text == "yyy mhm")
    }

    @Test func shapeIsPassedToTranscriber() async throws {
        let s = stub("hej")
        _ = try await DictationPipeline.run(input(s, shape: .chatAudio))
        #expect(await s.calls.shape == .chatAudio)
    }
}
