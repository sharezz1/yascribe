import Foundation
import Testing
@testable import YascribeProviders

@Test func mistralRequestAndPreset() throws {
    let p = Provider(name: "Mistral", baseURL: MistralDiarizationClient.baseURL, kind: .mistral)
    #expect(p.requiresKey && !p.isLocal)
    for role in [Role.asr, .correction, .summary, .embedding] { #expect(!p.supports(role)) }
    #expect(ProviderPreset.ready.contains(.mistral) && ProviderPreset.all.contains(.mistral))
    #expect(ProviderPreset.matching(p) == .mistral)
    let r = try MistralDiarizationClient.request(baseURL: p.baseURL, key: "fake", wav: Data([1, 2]), model: "model", language: .polish, references: ["x": Data([1, 2])], boundary: "B")
    let body = String(decoding: try #require(r.httpBody), as: UTF8.self)
    #expect(r.url?.path == "/v1/audio/transcriptions" && r.value(forHTTPHeaderField: "Authorization") == "Bearer fake")
    for field in ["model", "diarize", "timestamp_granularities", "language", "speaker_references", "AQI="] { #expect(body.contains(field)) }
    let empty = try MistralDiarizationClient.request(baseURL: p.baseURL, key: nil, wav: Data(), model: "m", language: nil, references: [:])
    #expect(!String(decoding: try #require(empty.httpBody), as: UTF8.self).contains("speaker_references"))
}

@Test func mistralParseAndErrors() async throws {
    let fixture = Data(#"{"segments":[{"start":0.1,"end":1.4,"text":"Neutral text.","speaker_id":"speaker_1"}],"usage":{"total_tokens":20,"prompt_audio_seconds":2}}"#.utf8)
    let parsed = try MistralDiarizationClient.parse(fixture)
    #expect(parsed.segments.first?.speakerID == "speaker_1" && parsed.totalTokens == 20 && parsed.promptAudioSeconds == 2)
    for (status, expected) in [(401, MistralDiarizationError.rejectedKey), (429, .rateLimit)] {
        let c = MistralDiarizationClient(key: "fake", http: StubHTTP { _, _ in (status, "error") })
        await #expect(throws: expected) { try await c.diarize(wav: Data(), model: "m", language: nil, references: [:]) }
    }
    let key = "secret-fake-key"
    let c = MistralDiarizationClient(key: key, http: StubHTTP { _, _ in (400, String(repeating: "x", count: 295) + key) })
    do { _ = try await c.diarize(wav: Data(), model: "m", language: nil, references: [:]); Issue.record("expected error") }
    catch { #expect(!error.localizedDescription.contains("secret")) }
    let http = StubHTTP { _, _ in (200, "[]") }
    #expect(await MistralDiarizationClient(key: key, http: http).verify() == .verified(models: 0))
    #expect(http.calls.first?.path == "/v1/models" && http.calls.first?.headers["Authorization"] == "Bearer \(key)")
}
