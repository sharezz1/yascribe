import Foundation
import Testing
@testable import MeetNotesProviders

private let elevenLabs = Provider(name: "ElevenLabs", baseURL: ElevenLabsClient.baseURL, kind: .elevenLabs)
private let fakeKey = "test-fake-elevenlabs"

/// Fixture zbudowana ze schematu w dokumentacji (speech-to-text/convert: słowa typu word / spacing / audio_event,
/// `start`/`end` mogą być null) — nie nagrana z żywego API.
private func sttFixture() throws -> String {
    try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/elevenlabs-stt.json"), encoding: .utf8)
}

private func part(_ name: String, _ value: String, _ b: String) -> Data {
    Data("--\(b)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
}

@Test func elevenLabsRequestIsMultipartWithKeyHeaderModelLanguageAndFile() throws {
    let wav = ProbeClips.polish.wav
    let r = ElevenLabsClient.transcriptionRequest(baseURL: ElevenLabsClient.baseURL, key: fakeKey, wav: wav,
                                                  model: "scribe_v2", language: .polish, boundary: "BND")
    #expect(r.url?.absoluteString == "https://api.elevenlabs.io/v1/speech-to-text")
    #expect(r.httpMethod == "POST")
    #expect(r.value(forHTTPHeaderField: "xi-api-key") == fakeKey)
    #expect(r.value(forHTTPHeaderField: "Authorization") == nil) // nie Bearer jak w OpenAI-compatible
    #expect(r.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=BND")
    let body = try #require(r.httpBody)
    for (name, value) in [("model_id", "scribe_v2"), ("language_code", "pl"), ("timestamps_granularity", "word"),
                          ("tag_audio_events", "false")] {
        #expect(body.range(of: part(name, value, "BND")) != nil, "brak pola \(name)=\(value)")
    }
    let fileHead = Data("--BND\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
    #expect(body.range(of: fileHead + wav + Data("\r\n--BND--\r\n".utf8)) != nil) // WAV nietknięty, granica zamyka ciało
    #expect(body.suffix(9) == Data("--BND--\r\n".utf8))
}

@Test func elevenLabsAutoLanguageOmitsLanguageCode() throws {
    // Preset „Auto" (W§2): bez pola = autodetekcja po stronie ElevenLabs. Język jawny idzie zawsze.
    let r = ElevenLabsClient.transcriptionRequest(baseURL: ElevenLabsClient.baseURL, key: fakeKey, wav: Data([1, 2]),
                                                  model: "scribe_v2", language: nil, boundary: "BND")
    #expect(try #require(r.httpBody).range(of: Data("language_code".utf8)) == nil)
}

@Test func elevenLabsResponseKeepsOnlyTimedWords() throws {
    let r = try ElevenLabsClient.parse(Data(try sttFixture().utf8))
    #expect(r.text == "Raz, dwa (śmiech) trzy.")
    #expect(r.words == [TranscribedWord(word: "Raz,", start: 0.12, end: 0.48), TranscribedWord(word: "dwa", start: 0.6, end: 0.95),
                        TranscribedWord(word: "trzy.", start: 1.45, end: 1.9)])
    #expect(try ElevenLabsClient.parse(Data(#"{"text":"","words":[]}"#.utf8)).words == nil) // cisza → Merger bez słów
    #expect(throws: ProviderError.badResponse("no text")) { try ElevenLabsClient.parse(Data(#"{"detail":"x"}"#.utf8)) }
}

@Test func elevenLabsTranscribeSendsToSpeechToTextAndHidesKeyInErrors() async throws {
    let body = try sttFixture()
    let http = StubHTTP { _, _ in (200, body) }
    let c = ElevenLabsClient(provider: elevenLabs, key: fakeKey, http: http)
    let r = try await c.transcribe(wav: ProbeClips.polish.wav, model: "scribe_v2", language: .polish, shape: .audioTranscriptions)
    #expect(r.words?.count == 3)
    #expect(http.calls.map(\.path) == ["/v1/speech-to-text"])
    #expect(http.calls[0].headers["xi-api-key"] == fakeKey)
    // Kształt czatowy nie istnieje — błąd bez żądania (sonda nie płaci drugi raz).
    await #expect(throws: ProviderError.self) {
        try await c.transcribe(wav: Data(), model: "scribe_v2", language: .polish, shape: .chatAudio)
    }
    #expect(http.calls.count == 1)
    let bad = ElevenLabsClient(provider: elevenLabs, key: fakeKey, http: StubHTTP { _, _ in
        fail(401, "{\"detail\":{\"code\":\"invalid_api_key\",\"message\":\"key \(fakeKey) is invalid\"}}")
    })
    do {
        _ = try await bad.transcribe(wav: Data(), model: "scribe_v2", language: .polish, shape: .audioTranscriptions)
        Issue.record("401 musi rzucić")
    } catch ProviderError.http(let status, let text) {
        #expect(status == 401)
        #expect(!text.contains(fakeKey))
    }
}

@Test func elevenLabsVerificationChecksTheKeyAndCountsScribe() async {
    func check(key: String? = fakeKey, _ respond: @escaping @Sendable (String, [String: Any]) -> (Int, Any)) async -> (ProviderCheck, StubHTTP) {
        let http = StubHTTP(respond)
        return (await ElevenLabsClient(provider: elevenLabs, key: key, http: http).verify(), http)
    }
    let (ok, http) = await check { _, _ in (200, "[]") }
    #expect(ok == .verified(models: 1))
    #expect(http.calls.map(\.path) == ["/v1/models"])
    #expect(http.calls[0].headers["xi-api-key"] == fakeKey)
    #expect(await check { _, _ in fail(401) }.0 == .failed("Invalid API key."))
    #expect(await check { _, _ in fail(404) }.0 == .failed("Wrong address: use https://api.elevenlabs.io/v1."))
    let (noKey, quiet) = await check(key: nil) { _, _ in (200, "[]") }
    #expect(noKey == .failed("No API key."))
    #expect(quiet.calls.isEmpty)
}

@Test func elevenLabsOffersScribeForTranscriptionOnly() {
    #expect(ElevenLabsClient.models(for: .asr).map(\.id) == ["scribe_v2"])
    #expect(ModelCatalog.visible(ElevenLabsClient.models(for: .asr), role: .asr, query: "").count == 1)
    for role in [Role.correction, .summary, .embedding] { #expect(ElevenLabsClient.models(for: role).isEmpty) }
}

@Test func probeRunsASROnElevenLabsAndRefusesTextRolesWithoutARequest() async {
    let http = StubHTTP { _, _ in (200, #"{"text":"Raz, dwa, trzy.","words":[]}"#) }
    let runner = ProbeRunner(client: ElevenLabsClient(provider: elevenLabs, key: fakeKey, http: http))
    let asr = await runner.probe(model: "scribe_v2", role: .asr, language: .polish)
    #expect(asr.works && asr.shape == .audioTranscriptions)
    let before = http.calls.count
    for role in [Role.summary, .embedding] {
        let r = await runner.probe(model: "scribe_v2", role: role, language: nil)
        #expect(!r.works && r.failure == "ElevenLabs does only speech-to-text.")
    }
    #expect(http.calls.count == before)
}

@Test func providerKindRoundTripsAndOldFilesStayOpenAICompatible() throws {
    let old = try JSONDecoder().decode(Provider.self, from: Data(#"{"id":"D424E7FA-BB22-4B32-9F9F-EDB81FCBAE98","name":"OpenRouter","baseURL":"https://openrouter.ai/api/v1"}"#.utf8))
    #expect(old.kind == nil && old.api == .openAICompatible)
    let json = String(decoding: try JSONEncoder().encode(elevenLabs), as: UTF8.self)
    #expect(json.contains(#""kind":"elevenLabs""#))
    #expect(try JSONDecoder().decode(Provider.self, from: Data(json.utf8)).api == .elevenLabs)
}
