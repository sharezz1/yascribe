import Foundation
import Testing
@testable import YascribeProviders

private func local(_ preset: ProviderPreset) -> Provider {
    Provider(name: preset.name, baseURL: URL(string: preset.baseURL)!)
}

@Test func unreachableLocalServerNamesTheServer() throws {
    let msg = try #require(LocalServerHint.message(for: local(.ollama), error: URLError(.cannotConnectToHost)))
    #expect(msg.contains("Ollama") && msg.contains("localhost:11434") && msg.contains("Start it") && msg.contains("ollama serve"))
    let llama = try #require(LocalServerHint.message(for: local(.llamaCpp), error: URLError(.cannotFindHost)))
    #expect(llama.contains("llama.cpp") && llama.contains("localhost:8080") && llama.contains("llama-server"))
    let omlx = try #require(LocalServerHint.message(for: local(.omlx), error: URLError(.cannotConnectToHost)))
    #expect(omlx.contains("oMLX") && omlx.contains("localhost:8000") && omlx.contains("press Start"))
}

@Test func timeoutIsNotReportedAsServerDown() throws {
    let msg = try #require(LocalServerHint.message(for: local(.ollama), error: URLError(.timedOut), timeout: 330))
    #expect(msg.contains("Ollama") && msg.contains("330 s") && msg.contains("smaller model") && msg.contains("Context window"))
    #expect(!msg.contains("Start it") && !msg.contains("Can't reach"))
    let noLimit = try #require(LocalServerHint.message(for: local(.ollama), error: URLError(.timedOut)))
    #expect(!noLimit.contains("Start it") && noLimit.contains("smaller model"))
}

@Test func connectionLostSaysDropped() throws {
    let msg = try #require(LocalServerHint.message(for: local(.llamaCpp), error: URLError(.networkConnectionLost)))
    #expect(msg == "llama.cpp dropped the connection.")
}

@Test func localUnauthorizedAsksForTheServerKey() throws {
    let msg = try #require(LocalServerHint.message(for: local(.omlx), error: ProviderError.http(401, "{\"detail\":\"API key required\"}")))
    #expect(msg.contains("oMLX") && msg.contains("API key") && msg.contains("Edit key…"))
}

@Test func localOutOfMemoryIsNotServerDown() throws {
    let msg = try #require(LocalServerHint.message(for: local(.omlx), error: ProviderError.http(507, "does not fit under the dynamic memory ceiling")))
    #expect(msg.contains("memory") && msg.contains("oMLX") && !msg.contains("Start it"))
}

@Test func remoteProviderErrorsAreNotRewritten() {
    let cloud = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    #expect(LocalServerHint.message(for: cloud, error: ProviderError.http(401, "no")) == nil)
    #expect(LocalServerHint.message(for: cloud, error: ProviderError.http(507, "no")) == nil)
    #expect(LocalServerHint.message(for: cloud, error: URLError(.cannotConnectToHost)) == nil)
    #expect(LocalServerHint.message(for: cloud, error: URLError(.timedOut)) == nil)
    // Inne błędy lokalnego serwera zostają po staremu (np. 500 albo przepełnienie kontekstu).
    #expect(LocalServerHint.message(for: local(.ollama), error: ProviderError.http(500, "boom")) == nil)
    #expect(LocalServerHint.message(for: local(.ollama), error: ProviderError.http(400, "exceeds the available context size")) == nil)
}

@Test func lanHostDoesNotGetThisMacWording() {
    let lan = Provider(name: "Ollama", baseURL: URL(string: "http://192.168.1.5:11434/v1")!)
    #expect(LocalServerHint.message(for: lan, error: URLError(.cannotConnectToHost)) == nil)
    #expect(LocalServerHint.message(for: lan, error: ProviderError.http(507, "x")) == nil)
}

@Test func customLoopbackServerGetsAGenericStartHint() throws {
    let p = Provider(name: "LM Studio", baseURL: URL(string: "http://localhost:1234/v1")!)
    let msg = try #require(LocalServerHint.message(for: p, error: URLError(.cannotConnectToHost)))
    #expect(msg == "Can't reach LM Studio at localhost:1234/v1. Start it and try again.")
}

private struct DownHTTP: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.cannotConnectToHost) }
}

@Test func verifyUsesTheLocalHintForLocalServers() async {
    let down = OpenAICompatibleClient(provider: local(.ollama), key: nil, http: DownHTTP())
    guard case .failed(let why) = await down.verify() else { Issue.record("expected a failure"); return }
    #expect(why.contains("Ollama") && why.contains("Start it"))
    let cloud = OpenAICompatibleClient(provider: openRouter, key: "test-fake-key", http: DownHTTP())
    guard case .failed(let cloudWhy) = await cloud.verify() else { Issue.record("expected a failure"); return }
    #expect(cloudWhy == "Can't connect. Is the server running and the address correct?")
}
