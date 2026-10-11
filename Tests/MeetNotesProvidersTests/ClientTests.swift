import Foundation
import Testing
@testable import MeetNotesProviders

@Test func listsModelsWithModalities() async throws {
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "google/gemini-3.8-flash", "architecture": ["input_modalities": ["text", "audio"], "output_modalities": ["text"]]],
        ["id": "deepseek/deepseek-v4.1-flash"],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "sk-or-secret", http: http).listModels()
    #expect(models.map(\.id) == ["google/gemini-3.8-flash", "deepseek/deepseek-v4.1-flash"])
    #expect(models[0].inputModalities == ["text", "audio"])
    #expect(http.calls[0].path == "/api/v1/models")
    #expect(http.calls[0].headers["Authorization"] == "Bearer sk-or-secret")
}

@Test func transcriptionSendsLanguageAndAsksForWordTimestamps() async throws {
    let http = StubHTTP { _, _ in ok(["text": "raz dwa trzy", "words": [
        ["word": "raz", "start": 0.1, "end": 0.4], ["word": "dwa", "start": 0.6, "end": 0.9],
    ]]) }
    let c = OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
    let r = try await c.transcribe(wav: ProbeClips.polish.wav, model: "microsoft/mai-transcribe-2", language: .polish,
                                   shape: .audioTranscriptions)
    let body = http.calls[0].body
    #expect(http.calls[0].path == "/api/v1/audio/transcriptions")
    #expect(body["language"] as? String == "pl")
    #expect(body["timestamp_granularities"] as? [String] == ["word"])
    #expect((body["input_audio"] as? [String: Any])?["format"] as? String == "wav")
    #expect(r.words?.count == 2)
    #expect(r.words?[1] == TranscribedWord(word: "dwa", start: 0.6, end: 0.9))
}

@Test func chatShapeReturnsTextWithoutTimestamps() async throws {
    let http = StubHTTP { _, _ in chatReply("raz, dwa, trzy") }
    let r = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "google/gemini-3.8-flash", language: .polish, shape: .chatAudio)
    #expect(r.text == "raz, dwa, trzy")
    #expect(r.words == nil)
    #expect(http.calls[0].path == "/api/v1/chat/completions")
}

@Test func httpErrorCarriesStatusButNeverTheKey() async throws {
    // P8: klucz nie może wyciec przez komunikat błędu.
    let http = StubHTTP { _, _ in fail(401, "{\"error\":\"invalid api key\"}") }
    let c = OpenAICompatibleClient(provider: openRouter, key: "sk-or-v1-SECRET123", http: http)
    do {
        _ = try await c.listModels()
        Issue.record("oczekiwano błędu")
    } catch {
        #expect(error as? ProviderError == .http(401, "{\"error\":\"invalid api key\"}"))
        #expect(!"\(error)".contains("SECRET123"))
    }
}
