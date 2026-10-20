import Foundation
import Testing
@testable import MeetNotesProviders

private func ollama(contextTokens: Int? = nil) -> Provider {
    Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!, contextTokens: contextTokens)
}
private let llamaCpp = Provider(name: "llama.cpp", baseURL: URL(string: "http://localhost:8080/v1")!)

@Test func detectionCanOnlyLowerTheBudget() {
    #expect(ContextBudget.resolve(provider: ollama(contextTokens: 4_096), detected: 45_824)?.tokens == 4_096)
    #expect(ContextBudget.resolve(provider: ollama(contextTokens: 4_096), detected: 2_048)?.tokens == 2_048)
    #expect(ContextBudget.resolve(provider: ollama(contextTokens: nil), detected: 45_824)?.tokens == 4_096)
    #expect(ContextBudget.resolve(provider: ollama(contextTokens: 16_384), detected: nil)?.tokens == 16_384)
}

@Test func userValueOverridesTheDefault() {
    #expect(ContextBudget.resolve(provider: ollama(), detected: nil)?.tokens == 4_096)
    #expect(ContextBudget.resolve(provider: ollama(contextTokens: 32_768), detected: nil)?.tokens == 32_768)
}

@Test func remoteLanAndFluidAudioHaveNoBudget() {
    let lan = Provider(name: "Server", baseURL: URL(string: "http://192.168.1.20:11434/v1")!, contextTokens: 8_192)
    let fluid = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    #expect(ContextBudget.resolve(provider: openRouter, detected: 4_096) == nil)
    #expect(ContextBudget.resolve(provider: lan, detected: 4_096) == nil)
    #expect(ContextBudget.resolve(provider: fluid, detected: nil) == nil)
}

@Test func formulasMatchTheSpecExamples() {
    let small = ContextBudget(tokens: 4_096), big = ContextBudget(tokens: 16_384)
    #expect(small.promptChars(replyTokens: 2_048) == 4_300)
    #expect(small.pairedInputChars(fixedChars: 380, replyFactor: 1.3) == 3_841)
    #expect(big.promptChars(replyTokens: 2_048) == 33_792)
    #expect(ContextBudget.maxTokens(inputChars: 4_800, replyFactor: 0.5) == 1_000)
    #expect(ContextBudget.maxTokens(inputChars: 3_000, replyFactor: 1.3) == 1_625)
}

@Test func tooSmallContextGivesNonPositiveInput() {
    #expect(ContextBudget(tokens: 2_048).promptChars(replyTokens: 2_048) <= 0)
    #expect(ContextBudget(tokens: 256).pairedInputChars(fixedChars: 380, replyFactor: 1.3) <= 0)
}

@Test func oldProvidersFileWithoutContextTokensStillLoads() throws {
    let old = #"{"providers":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Ollama","baseURL":"http://localhost:11434/v1"}]}"#
    let file = try JSONDecoder().decode(ProvidersFile.self, from: Data(old.utf8))
    #expect(file.providers.count == 1 && file.providers[0].contextTokens == nil)
    let back = try JSONDecoder().decode(ProvidersFile.self, from: JSONEncoder().encode(
        ProvidersFile(providers: [ollama(contextTokens: 8_192)])))
    #expect(back.providers[0].contextTokens == 8_192)
}

@Test func probeUsesPropsThenApiPsOutsideV1() async {
    let props = StubHTTP { path, _ in path == "/props" ? ok(["default_generation_settings": ["n_ctx": 8_192]]) : fail(404) }
    let llama = OpenAICompatibleClient(provider: llamaCpp, key: nil, http: props)
    #expect(await ContextProbe.detect(client: llama, model: "anything") == 8_192)
    #expect(props.calls.map(\.path) == ["/props"])

    let ps = StubHTTP { path, _ in
        path == "/api/ps" ? ok(["models": [["name": "bonsai-2:latest", "context_length": 4_096]]]) : fail(404)
    }
    let ol = OpenAICompatibleClient(provider: ollama(), key: nil, http: ps)
    #expect(await ContextProbe.detect(client: ol, model: "bonsai-2") == 4_096)
    #expect(ps.calls.map(\.path) == ["/props", "/api/ps"]) // najpierw /props (404 na Ollamie), potem /api/ps
    #expect(ps.calls.allSatisfy { !$0.path.hasPrefix("/v1") && $0.path != "/api/show" && $0.timeout == 5 })
}

@Test func apiPsMatchesTheModelIgnoringLatest() async {
    let ps = StubHTTP { path, _ in
        path == "/api/ps" ? ok(["models": [["name": "bonsai-2:latest", "context_length": 4_096], ["name": "qwen3:8b", "context_length": 8_192]]]) : fail(404)
    }
    let c = OpenAICompatibleClient(provider: ollama(), key: nil, http: ps)
    #expect(await ContextProbe.detect(client: c, model: "bonsai-2:latest") == 4_096)
    #expect(await ContextProbe.detect(client: c, model: "bonsai-2") == 4_096)
    #expect(await ContextProbe.detect(client: c, model: "qwen3:8b") == 8_192)
    #expect(await ContextProbe.detect(client: c, model: "other") == nil)
}

@Test func unloadedModelOrUnknownServerYieldsNil() async {
    let empty = StubHTTP { path, _ in path == "/api/ps" ? ok(["models": []]) : fail(404) }
    #expect(await ContextProbe.detect(client: OpenAICompatibleClient(provider: ollama(), key: nil, http: empty), model: "m") == nil)
    let notFound = StubHTTP { _, _ in fail(404) }
    #expect(await ContextProbe.detect(client: OpenAICompatibleClient(provider: ollama(), key: nil, http: notFound), model: "m") == nil)
    let junk = StubHTTP { _, _ in (200, "<html>not json</html>") }
    #expect(await ContextProbe.detect(client: OpenAICompatibleClient(provider: ollama(), key: nil, http: junk), model: "m") == nil)
    let notObject = StubHTTP { _, _ in (200, [1, 2]) } // JSON, ale nie słownik
    #expect(await ContextProbe.effectiveContexts(client: OpenAICompatibleClient(provider: ollama(), key: nil, http: notObject)).isEmpty)
}

@Test func addressWithoutV1IsNotProbed() async {
    let stub = StubHTTP { _, _ in ok(["default_generation_settings": ["n_ctx": 8_192]]) }
    let p = Provider(name: "Custom", baseURL: URL(string: "http://localhost:8080/openai")!)
    #expect(await ContextProbe.detect(client: OpenAICompatibleClient(provider: p, key: nil, http: stub), model: "m") == nil)
    #expect(stub.calls.isEmpty)
}

@Test func probeSendsTheKeyWhenTheProviderHasOne() async {
    let stub = StubHTTP { _, _ in ok(["default_generation_settings": ["n_ctx": 4_096]]) }
    _ = await ContextProbe.effectiveContexts(client: OpenAICompatibleClient(provider: llamaCpp, key: "test-fake-key", http: stub))
    #expect(stub.calls.first?.headers["Authorization"] == "Bearer test-fake-key")
}

@Test func detectedContextIsDescribedForCheck() {
    #expect(ContextProbe.describe(["*": 8_192]) == "Detected context: 8192 tokens")
    #expect(ContextProbe.describe(["bonsai-2": 4_096]) == "bonsai-2: 4096 tokens")
    #expect(ContextProbe.describe(["b": 8_192, "a": 4_096]) == "a: 4096 tokens · b: 8192 tokens")
    #expect(ContextProbe.describe([:]) == nil)
}
