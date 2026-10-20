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

// MARK: chat — limity, finish_reason, reasoning_effort (F20 T10)

private let ollamaLocal = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
private let lanBox = Provider(name: "Box", baseURL: URL(string: "http://192.168.1.5:11434/v1")!)

private func chat(_ provider: Provider, _ http: StubHTTP, timeout: Double = 120, maxTokens: Int? = nil,
                  temperature: Double? = nil) async throws -> String {
    try await OpenAICompatibleClient(provider: provider, key: nil, http: http)
        .chat(model: "m", system: "s", user: "u", timeout: timeout, maxTokens: maxTokens, temperature: temperature)
}

@Test func chatUsesTheGivenTransportTimeout() async throws {
    let http = StubHTTP { _, _ in chatReply("OK") }
    _ = try await chat(ollamaLocal, http, timeout: 600)
    #expect(http.calls[0].timeout == 600)
    _ = try await chat(openRouter, http)
    #expect(http.calls[1].timeout == 120)
}

@Test func chatSendsMaxTokensAndTemperatureOnlyWhenGiven() async throws {
    let http = StubHTTP { _, _ in chatReply("OK") }
    _ = try await chat(openRouter, http)
    #expect(http.calls[0].body["max_tokens"] == nil && http.calls[0].body["temperature"] == nil)
    _ = try await chat(openRouter, http, maxTokens: 64, temperature: 0.2)
    #expect(http.calls[1].body["max_tokens"] as? Int == 64)
    #expect(http.calls[1].body["temperature"] as? Double == 0.2)
}

@Test func chatSendsReasoningEffortNoneOnlyToLocalProviders() async throws {
    let http = StubHTTP { _, _ in chatReply("OK") }
    _ = try await chat(ollamaLocal, http)
    _ = try await chat(openRouter, http)
    _ = try await chat(lanBox, http)
    #expect(http.calls[0].body["reasoning_effort"] as? String == "none")
    #expect(http.calls[1].body["reasoning_effort"] == nil)
    #expect(http.calls[2].body["reasoning_effort"] == nil)
}

@Test func localServerRejectingReasoningEffortIsRetriedOnceWithoutIt() async throws {
    let http = StubHTTP { _, body in
        body["reasoning_effort"] != nil ? fail(400, "{\"error\":\"unknown field: reasoning_effort\"}") : chatReply("OK")
    }
    let reply = try await chat(ollamaLocal, http, maxTokens: 64, temperature: 0.2)
    #expect(reply == "OK")
    #expect(http.calls.count == 2)
    #expect(http.calls[0].body["reasoning_effort"] as? String == "none")
    #expect(http.calls[1].body["reasoning_effort"] == nil)
    #expect(http.calls[1].body["max_tokens"] as? Int == 64 && http.calls[1].body["temperature"] as? Double == 0.2)
    // 422 też; a gdy odrzuca także drugie żądanie, błąd wychodzi (bez trzeciej próby).
    let always = StubHTTP { _, _ in fail(422, "Reasoning is not supported") }
    await #expect(throws: ProviderError.http(422, "Reasoning is not supported")) { _ = try await chat(ollamaLocal, always) }
    #expect(always.calls.count == 2)
}

@Test func rejectionMentioningThinkingIsRetriedToo() async throws {
    let http = StubHTTP { _, body in
        body["reasoning_effort"] != nil ? fail(400, "{\"error\":\"this model does not support thinking control\"}") : chatReply("OK")
    }
    #expect(try await chat(ollamaLocal, http) == "OK")
    #expect(http.calls.count == 2 && http.calls[1].body["reasoning_effort"] == nil)
}

// MARK: chat bez myślenia na API (F20 P1)

private func chatThinking(_ provider: Provider, _ http: StubHTTP, thinking: Bool) async throws -> String {
    try await OpenAICompatibleClient(provider: provider, key: nil, http: http).chat(model: "m", system: "s", user: "u", thinking: thinking)
}

@Test func chatWithoutThinkingSendsReasoningDisabledToApiProvidersOnly() async throws {
    let http = StubHTTP { _, _ in chatReply("OK") }
    _ = try await chatThinking(openRouter, http, thinking: false)
    _ = try await chatThinking(openRouter, http, thinking: true)
    _ = try await chatThinking(ollamaLocal, http, thinking: false)
    #expect((http.calls[0].body["reasoning"] as? [String: Any])?["enabled"] as? Bool == false)
    #expect(http.calls[1].body["reasoning"] == nil) // domyślnie nic nie wysyłamy: zachowanie sprzed poprawki
    #expect(http.calls[2].body["reasoning"] == nil && http.calls[2].body["reasoning_effort"] as? String == "none") // lokalnie: jak dotąd
}

@Test func apiProviderRejectingReasoningIsRetriedOnceWithoutItOnlyWhenThinkingIsOff() async throws {
    let http = StubHTTP { _, body in
        body["reasoning"] != nil ? fail(400, "{\"error\":\"Unrecognized request argument: reasoning\"}") : chatReply("OK")
    }
    #expect(try await chatThinking(openRouter, http, thinking: false) == "OK")
    #expect(http.calls.count == 2 && http.calls[0].body["reasoning"] != nil && http.calls[1].body["reasoning"] == nil)
    // Drugie żądanie też odrzucone: błąd wychodzi, bez trzeciej próby. Inny 400 (bez „reasoning"/„think") nie jest ponawiany.
    let always = StubHTTP { _, _ in fail(422, "reasoning not allowed") }
    await #expect(throws: ProviderError.http(422, "reasoning not allowed")) { _ = try await chatThinking(openRouter, always, thinking: false) }
    #expect(always.calls.count == 2)
    let other = StubHTTP { _, _ in fail(400, "{\"error\":\"bad model\"}") }
    await #expect(throws: ProviderError.http(400, "{\"error\":\"bad model\"}")) { _ = try await chatThinking(openRouter, other, thinking: false) }
    #expect(other.calls.count == 1)
}

@Test func chatStripsThinkBlocksOnApiProvidersToo() async throws {
    let http = StubHTTP { _, _ in chatReply("<think>hm</think>\n[1] Tak.") }
    #expect(try await chat(openRouter, http) == "[1] Tak.")
    let mid = StubHTTP { _, _ in chatReply("# T\n- tag <think> w treści\n- koniec") }
    #expect(try await chat(openRouter, mid) == "# T\n- tag <think> w treści\n- koniec")
}

@Test func emptyApiReplyThrowsEmptyReplyToo() async {
    for text in ["<think>x</think>", "  "] {
        let http = StubHTTP { _, _ in chatReply(text) }
        await #expect(throws: ProviderError.badResponse("empty reply")) { _ = try await chat(openRouter, http) }
    }
}

@Test func nonLocalProviderRejectingReasoningIsNotRetried() async {
    let http = StubHTTP { _, _ in fail(400, "{\"error\":\"reasoning\"}") }
    await #expect(throws: ProviderError.http(400, "{\"error\":\"reasoning\"}")) { _ = try await chat(openRouter, http) }
    #expect(http.calls.count == 1)
}

@Test func contextOverflowIsNotRetried() async {
    let body = "{\"error\":{\"message\":\"request (6057 tokens) exceeds the available context size (4096 tokens), try increasing it\"}}"
    let http = StubHTTP { _, _ in fail(400, body) }
    await #expect(throws: ProviderError.http(400, body)) { _ = try await chat(ollamaLocal, http) }
    #expect(http.calls.count == 1)
}

@Test func lengthFinishReasonIsAnError() async {
    for p in [ollamaLocal, openRouter] {
        let http = StubHTTP { _, _ in chatReply("Notatka urwana w pół", finish: "length") }
        await #expect(throws: ProviderError.replyCutOff) { _ = try await chat(p, http) }
    }
}

@Test func lengthWithEmptyContentIsCutOffNotEmptyReply() async {
    let http = StubHTTP { _, _ in chatReply("", finish: "length", extra: ["reasoning": "myślę i myślę"]) }
    await #expect(throws: ProviderError.replyCutOff) { _ = try await chat(ollamaLocal, http) }
}

@Test func missingOrNullFinishReasonPasses() async throws {
    let none = StubHTTP { _, _ in chatReply("OK") }
    #expect(try await chat(openRouter, none) == "OK")
    let null = StubHTTP { _, _ in chatReply("OK", finish: nil) }
    #expect(try await chat(openRouter, null) == "OK")
    let stop = StubHTTP { _, _ in chatReply("OK", finish: "stop") }
    #expect(try await chat(ollamaLocal, stop) == "OK")
}

@Test func chatIgnoresReasoningContentField() async throws {
    let http = StubHTTP { _, _ in chatReply("OK", finish: "stop", extra: ["reasoning": "rozumowanie", "reasoning_content": "też rozumowanie"]) }
    #expect(try await chat(ollamaLocal, http) == "OK")
}

@Test func chatStripsThinkBlocksFromTheReply() async throws {
    let http = StubHTTP { _, _ in chatReply("<think>hm</think>\n[1] Tak.") }
    #expect(try await chat(ollamaLocal, http) == "[1] Tak.")
}

@Test func apiNoteQuotingAClosingThinkTagStaysIntact() async throws {
    // Przegląd T13: reguła „zamknięcie bez otwarcia" (szablon czatu lokalnego modelu) nie może kasować notatki z API.
    let note = "# Notatka\n- Dodać tag </think> do filtra odpowiedzi\n- Reszta"
    #expect(try await chat(openRouter, StubHTTP { _, _ in chatReply(note) }) == note)
    #expect(try await chat(ollamaLocal, StubHTTP { _, _ in chatReply("rozumuję\n</think>\n# T\nTreść") }) == "# T\nTreść")
}

@Test func chatReplyWithOnlyAThinkBlockThrowsEmptyReply() async {
    for text in ["<think>zaczynam", "<think>x</think>", "   "] {
        let http = StubHTTP { _, _ in chatReply(text) }
        await #expect(throws: ProviderError.badResponse("empty reply")) { _ = try await chat(ollamaLocal, http) }
    }
}

@Test func chatAudioTranscriptionIgnoresFinishReason() async throws {
    // `chatContent` jest wspólny z ASR przez czat — ścieżka z API zostaje bez zmian.
    let http = StubHTTP { _, _ in chatReply("raz, dwa, trzy", finish: "length") }
    let r = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "google/gemini-3.8-flash", language: .polish, shape: .chatAudio)
    #expect(r.text == "raz, dwa, trzy")
    #expect(http.calls[0].body["reasoning_effort"] == nil)
}

// MARK: ciche obcięcie wejścia przez lokalny serwer (odbiór 2.0b, pkt 2c)

private let longSystem = String(repeating: "s", count: 1_500)
private let longUser = String(repeating: "u", count: 6_000) // 7500 znaków razem

private func chatWithUsage(_ provider: Provider, _ promptTokens: Double?, system: String = longSystem, user: String = longUser,
                           finish: String = "stop") async throws -> String {
    let http = StubHTTP { _, _ in
        var obj: [String: Any] = ["choices": [["message": ["content": "# T\nbody"], "finish_reason": finish]]]
        if let promptTokens { obj["usage"] = ["prompt_tokens": promptTokens, "completion_tokens": 5] }
        return ok(obj)
    }
    return try await OpenAICompatibleClient(provider: provider, key: nil, http: http).chat(model: "m", system: system, user: user)
}

@Test func truncatedInputOnALocalServerIsAnError() async {
    // Ollama + bonsai-2: 7500 znaków, serwer przeczytał 1000 tokenów (7,5 znaku/token), HTTP 200, finish_reason "stop".
    await #expect(throws: ProviderError.inputTruncated(sentChars: 7_500, readTokens: 1_000)) {
        _ = try await chatWithUsage(ollamaLocal, 1_000)
    }
    // Jeszcze mniej tokenów (15 znaków/token) — to samo.
    await #expect(throws: ProviderError.inputTruncated(sentChars: 7_500, readTokens: 500)) { _ = try await chatWithUsage(ollamaLocal, 500) }
    // `usage` jako liczba zmiennoprzecinkowa (JSON 1000.0) też działa.
    await #expect(throws: ProviderError.inputTruncated(sentChars: 7_500, readTokens: 1_000)) { _ = try await chatWithUsage(ollamaLocal, 1_000.0) }
}

@Test func normalLocalReplyPassesTheRatioCheck() async throws {
    // 7500 znaków / 2500 tokenów = 3,0 (zmierzone normalnie 2,8–3,3) i granica: dokładnie 5,0 nie jest błędem.
    #expect(try await chatWithUsage(ollamaLocal, 2_500) == "# T\nbody")
    #expect(try await chatWithUsage(ollamaLocal, 1_500) == "# T\nbody")
}

@Test func missingUsageIsNotAnError() async throws {
    #expect(try await chatWithUsage(ollamaLocal, nil) == "# T\nbody")
    #expect(try await chatWithUsage(ollamaLocal, 0) == "# T\nbody")
    let text = StubHTTP { _, _ in ok(["choices": [["message": ["content": "OK"], "finish_reason": "stop"]], "usage": ["prompt_tokens": "dużo"]]) }
    #expect(try await OpenAICompatibleClient(provider: ollamaLocal, key: nil, http: text).chat(model: "m", system: longSystem, user: longUser) == "OK")
    // `usage` bez `prompt_tokens` (np. tylko completion_tokens).
    let http = StubHTTP { _, _ in ok(["choices": [["message": ["content": "OK"], "finish_reason": "stop"]], "usage": ["completion_tokens": 3]]) }
    #expect(try await chat(ollamaLocal, http) == "OK")
}

@Test func shortPromptsAreNotChecked() async throws {
    // 3999 znaków, 1 token → iloraz ogromny, ale poniżej `truncationMinChars`: nie sprawdzamy (np. sonda „ping").
    let user = String(repeating: "u", count: 3_999 - 1)
    #expect(try await chatWithUsage(ollamaLocal, 1, system: "s", user: user) == "# T\nbody")
    // Równo 4000 znaków już podlega sprawdzeniu.
    await #expect(throws: ProviderError.inputTruncated(sentChars: 4_000, readTokens: 1)) {
        _ = try await chatWithUsage(ollamaLocal, 1, system: "s", user: user + "u")
    }
}

@Test func remoteProviderIsNeverChecked() async throws {
    #expect(try await chatWithUsage(openRouter, 10) == "# T\nbody")
}

@Test func lengthFinishReasonStaysAnOutputErrorWhenUsageIsNormal() async {
    // finish_reason "length" zostaje błędem wyjścia (nie wejścia), gdy `usage` jest normalne.
    await #expect(throws: ProviderError.replyCutOff) { _ = try await chatWithUsage(ollamaLocal, 2_500, finish: "length") }
}

@Test func truncatedInputIsNotRetriedAndDescribed() async {
    let http = StubHTTP { _, _ in ok(["choices": [["message": ["content": "x"], "finish_reason": "stop"]], "usage": ["prompt_tokens": 100]]) }
    await #expect(throws: ProviderError.inputTruncated(sentChars: 7_500, readTokens: 100)) {
        _ = try await OpenAICompatibleClient(provider: ollamaLocal, key: nil, http: http).chat(model: "m", system: longSystem, user: longUser)
    }
    #expect(http.calls.count == 1)
    #expect(ProviderCheck.describe(ProviderError.inputTruncated(sentChars: 7_500, readTokens: 100)).contains("cut off the start of the input"))
}

@Test func chatAudioTranscriptionIsNotCheckedForTruncation() async throws {
    // `transcribe(.chatAudio)` idzie przez `chatContent`, nie przez `chat`: audio w base64 ma inny iloraz znaków do tokenów.
    let http = StubHTTP { _, _ in ok(["choices": [["message": ["content": "raz dwa trzy"], "finish_reason": "stop"]], "usage": ["prompt_tokens": 1]]) }
    let r = try await OpenAICompatibleClient(provider: ollamaLocal, key: nil, http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "m", language: .polish, shape: .chatAudio)
    #expect(r.text == "raz dwa trzy")
}
