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

@Test func errorBodyEchoingTheKeyIsSanitized() async throws {
    // ChatGPT #11: serwer odsyła nagłówek w treści błędu — klucz nie może trafić do cache ani komunikatu.
    let http = StubHTTP { _, _ in fail(400, "{\"error\":\"bad header Authorization: Bearer test-fake-SECRET123\"}") }
    do {
        _ = try await OpenAICompatibleClient(provider: openRouter, key: "test-fake-SECRET123", http: http).listModels()
        Issue.record("oczekiwano błędu")
    } catch {
        #expect(!"\(error)".contains("SECRET123"))
    }
}

@Test func autoLanguageOmitsTheLanguageField() async throws {
    let http = StubHTTP { _, _ in ok(["text": "x"]) }
    _ = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "m", language: nil, shape: .audioTranscriptions)
    #expect(http.calls[0].body["language"] == nil)
}

@Test func listModelsCanAskForAnOutputModality() async throws {
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "microsoft/mai-transcribe-2", "architecture": ["output_modalities": ["transcription"]]],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    #expect(models.map(\.id) == ["microsoft/mai-transcribe-2"])
    #expect(http.calls[0].path == "/api/v1/models?output_modalities=transcription")
}

@Test func providerRejectingTheModalityParameterIsAskedAgainWithoutIt() async throws {
    let http = StubHTTP { path, _ in
        path.contains("output_modalities") ? fail(400, "{\"error\":\"unknown parameter\"}")
            : ok(["data": [["id": "llama3"], ["id": "nomic-embed"]]])
    }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "embeddings")
    #expect(models.map(\.id) == ["llama3", "nomic-embed"]) // brak modalności w odpowiedzi → nic nie odfiltrowane
    #expect(http.calls.map(\.path) == ["/api/v1/models?output_modalities=embeddings", "/api/v1/models"])
}

@Test func providerIgnoringTheModalityFilterIsFilteredLocally() async throws {
    // Review Focus #2: 200 z pełną listą — ponowienie się nie wyzwoli, filtr lokalny musi zadziałać.
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "microsoft/mai-transcribe-2", "architecture": ["output_modalities": ["transcription"]]],
        ["id": "openai/gpt-x", "architecture": ["output_modalities": ["text"]]],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    #expect(models.map(\.id) == ["microsoft/mai-transcribe-2"])
}

@Test func modalityRetryHappensOnlyOnce() async throws {
    let http = StubHTTP { _, _ in fail(400, "{}") }
    await #expect(throws: ProviderError.http(400, "{}")) {
        _ = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    }
    #expect(http.calls.count == 2)
}
