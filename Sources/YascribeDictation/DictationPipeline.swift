import Foundation
import YascribeNotes
import YascribeProviders
import YascribeTranscription

public struct DictationPipelineInput: Sendable {
    public var pcm: [Int16]
    public var language: LanguageCode?
    public var asrModel: String
    public var transcriber: any TranscriptionClient
    public var shape: ASRShape
    /// `nil` = korekta wyłączona.
    public var chat: ChatFunction?
    public var vocabulary: PromptVocabulary
    /// `nil` = filtr przerywników wyłączony.
    public var removeFillers: [String]?
    public var replacement: ReplacementRules

    public init(pcm: [Int16], language: LanguageCode?, asrModel: String, transcriber: any TranscriptionClient, shape: ASRShape,
                chat: ChatFunction?, vocabulary: PromptVocabulary, removeFillers: [String]?, replacement: ReplacementRules) {
        self.pcm = pcm; self.language = language; self.asrModel = asrModel; self.transcriber = transcriber; self.shape = shape
        self.chat = chat; self.vocabulary = vocabulary; self.removeFillers = removeFillers; self.replacement = replacement
    }
}

public struct DictationOutput: Equatable, Sendable {
    public var raw: String
    public var text: String
    public var correctionFailed: Bool
    public init(raw: String, text: String, correctionFailed: Bool) {
        self.raw = raw; self.text = text; self.correctionFailed = correctionFailed
    }
}

public enum DictationPipeline {
    public static let sampleRate = 16_000.0
    public static let minSeconds = 0.3
    /// Limit nagrania egzekwuje wołający (silnik); potok go nie przycina.
    public static let maxSeconds = 300.0

    public static func run(_ input: DictationPipelineInput) async throws -> DictationOutput? {
        guard Double(input.pcm.count) / sampleRate >= minSeconds else { return nil }
        let wav = WAVEncoder.wav(input.pcm, rate: sampleRate)
        let asr = try await input.transcriber.transcribe(wav: wav, model: input.asrModel, language: input.language, shape: input.shape)
        let raw = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        var text = raw
        var failed = false
        if let chat = input.chat {
            switch await DictationCorrector.correct(raw, language: input.language, vocabulary: input.vocabulary, chat: chat) {
            case .success(let corrected): text = corrected
            case .failure: failed = true
            }
        }
        if let words = input.removeFillers {
            // `remove` zwraca oryginał, gdy wszystko jest przerywnikiem; sentinel pokazuje, że tak było.
            let sentinel = "Q9ZX"
            let probe = FillerWords.remove(sentinel + " " + text, words: words)
            if probe.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) == sentinel { return nil }
            text = FillerWords.remove(text, words: words)
        }
        text = input.replacement.apply(to: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return DictationOutput(raw: raw, text: text, correctionFailed: failed)
    }
}
