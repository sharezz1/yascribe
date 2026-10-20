import Foundation
import Testing
@testable import MeetNotesProviders

private func runner(_ http: StubHTTP, provider: Provider = openRouter) -> ProbeRunner {
    ProbeRunner(client: OpenAICompatibleClient(provider: provider, key: "k", http: http))
}

@Test func transcriptionModelTypedByHandPassesTheProbe() async {
    // P2: mai-transcribe-2 nie jest na liście modeli, a sonda go przyjmuje.
    let http = StubHTTP { path, body in
        guard path.hasSuffix("audio/transcriptions") else { return fail(404) }
        if isPolishClip(body) { return transcript("Raz, dwa, trzy.") }
        return transcript(body["language"] == nil ? "One, two, three." : "Łan tu trii.")
    }
    let r = await runner(http).probe(model: "microsoft/mai-transcribe-2", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.shape == ASRShape.audioTranscriptions)
    #expect(r.languageHandling == LanguageHandling.enforced)
    #expect(r.language == LanguageCode.polish)
}

@Test func chatOnlyModelIsRecognizedWithUnknownLanguageHandling() async {
    // P3: model działający wyłącznie przez czat.
    let http = StubHTTP { path, _ in
        path.hasSuffix("chat/completions") ? chatReply("raz, dwa, trzy") : fail(404)
    }
    let r = await runner(http).probe(model: "google/gemini-3.8-flash", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.shape == ASRShape.chatAudio)
    #expect(r.languageHandling == LanguageHandling.unknown)
}

@Test func textOnlyRuntimeFailsTheASRProbeButPassesChat() async {
    // P1 na poziomie jednostkowym: tak odpowiada Ollama — brak endpointu audio,
    // a czat grzecznie odmawia. Na żywym endpoincie: krok ręczny w planie.
    let http = StubHTTP { path, _ in
        path.hasSuffix("audio/transcriptions") ? fail(404, "404 page not found") : chatReply("I can't listen to audio, but OK.")
    }
    let ollama = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    let asr = await runner(http, provider: ollama).probe(model: "qwen3:8b", role: .asr, language: .polish)
    #expect(!asr.works)
    #expect(asr.failure?.contains("audioTranscriptions") == true)
    let chat = await runner(http, provider: ollama).probe(model: "qwen3:8b", role: .correction, language: nil)
    #expect(chat.works)
}

@Test func correctionProbeRunsWithoutThinkingLikeTheCorrectionItself() async {
    // F20 P1: sonda korekty ma ten sam profil co korekta, inaczej „Test" wisi na modelu, który w korekcie działa. Podsumowanie: bez zmian.
    let http = StubHTTP { _, _ in chatReply("OK") }
    _ = await runner(http).probe(model: "m", role: .correction, language: nil)
    _ = await runner(http).probe(model: "m", role: .summary, language: nil)
    #expect((http.calls[0].body["reasoning"] as? [String: Any])?["enabled"] as? Bool == false)
    #expect(http.calls[1].body["reasoning"] == nil)
}

@Test func modelThatIgnoresLanguageIsAutomatic() async {
    // P10: ta sama odpowiedź z językiem i bez — parametr nic nie robi (profil Parakeeta przez API).
    let http = StubHTTP { _, body in transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three") }
    let r = await runner(http).probe(model: "nvidia/parakeet-tdt-0.6b-v3", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.languageHandling == LanguageHandling.automatic)
}

@Test func rejectedLanguageParameterMeansAutomatic() async {
    let http = StubHTTP { _, body in
        if body["language"] != nil && !isPolishClip(body) { return fail(400, "{\"error\":\"language not supported\"}") }
        return transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.automatic)
}

@Test func nondeterministicModelIsNotClassified() async {
    let counter = Counter()
    let http = StubHTTP { _, _ in transcript("one two three \(counter.next())") }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown) // lepiej „nie wiem" niż fałszywe „wymuszony"
}

@Test func embeddingProbeRecordsDimension() async {
    let http = StubHTTP { _, _ in ok(["data": [["embedding": [0.1, 0.2, 0.3, 0.4]]]]) }
    let r = await runner(http).probe(model: "text-embedding", role: .embedding, language: nil)
    #expect(r.works)
    #expect(r.embeddingDimension == 4)
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

@Test func rateLimitDuringLanguageProbeIsUnknownNotAutomatic() async {
    // ChatGPT #5: 429 to nie odrzucony parametr języka.
    let http = StubHTTP { _, body in
        if body["language"] != nil && !isPolishClip(body) { return fail(429, "{\"error\":\"rate limited\"}") }
        return transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown)
}

@Test func unstableAnswerWithLanguageIsNotEnforced() async {
    // ChatGPT #5: jedna różna odpowiedź to jeszcze nie dowód wymuszania.
    let counter = Counter()
    let http = StubHTTP { _, body in
        body["language"] != nil ? transcript("jeden dwa \(counter.next())") : transcript("one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown)
}

/// Atrapa lokalnego klienta: liczy wywołania (`classifyLanguage` dołożyłaby ich co najmniej trzy).
private final class LocalStub: TranscriptionClient, @unchecked Sendable {
    let provider = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    private let lock = NSLock()
    private var _total = 0
    var total: Int { lock.withLock { _total } }
    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        lock.withLock { _total += 1 }
        return TranscriptionResult(text: "Raz, dwa, trzy.", words: [])
    }
}

@Test func fluidAudioProbeReportsFilteredLanguageHandling() async {
    let stub = LocalStub()
    let r = await ProbeRunner(client: stub).probe(model: LocalASRModels.parakeetV3, role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.shape == ASRShape.audioTranscriptions)
    #expect(r.languageHandling == LanguageHandling.filtered)
    #expect(stub.total == 1) // tylko wywołanie sondy; klasyfikacja woła dodatkowo `language: nil` dwa razy i więcej
}

@Test func fluidAudioProbeForCorrectionRoleSaysSpeechToTextOnly() async {
    let r = await ProbeRunner(client: LocalStub()).probe(model: "x", role: .correction, language: nil)
    #expect(!r.works)
    #expect(r.failure == "On this Mac does only speech-to-text.")
}
