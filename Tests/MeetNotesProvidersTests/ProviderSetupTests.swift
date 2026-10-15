import Foundation
import Testing
@testable import MeetNotesProviders

@Test func providerTilesComeWithReadyAddresses() {
    #expect(ProviderPreset.all.map(\.name) == ["OpenRouter", "Ollama", "Custom"])
    #expect(ProviderPreset.openRouter.baseURL == "https://openrouter.ai/api/v1" && ProviderPreset.openRouter.needsKey)
    #expect(ProviderPreset.ollama.baseURL == "http://localhost:11434/v1" && !ProviderPreset.ollama.needsKey)
    #expect(ProviderPreset.ollama.note?.contains("no transcription") == true) // Ollama bez ASR — użytkownik ma to wiedzieć
    #expect(ProviderPreset.custom.baseURL.isEmpty && ProviderPreset.custom.needsKey)
}

@Test func presetCountsAsAddedByAddressNotName() {
    func p(_ url: String, _ name: String = "x") -> Provider { Provider(name: name, baseURL: URL(string: url)!) }
    #expect(!ProviderPreset.openRouter.isAdded(in: []))
    #expect(ProviderPreset.openRouter.isAdded(in: [p("https://OpenRouter.ai/api/v1/", "Mine")])) // wielkość liter hosta i końcowy „/”
    #expect(!ProviderPreset.openRouter.isAdded(in: [p("https://openrouter.ai/api/v2"), p("http://localhost:11434/v1")]))
    #expect(ProviderPreset.ollama.isAdded(in: [p("http://localhost:11434/v1")]))
    #expect(!ProviderPreset.ollama.isAdded(in: [p("http://localhost:8080/v1")])) // inny port
    #expect(!ProviderPreset.custom.isAdded(in: [p("https://openrouter.ai/api/v1")])) // Custom zawsze dostępny
    #expect(ProviderPreset.displayAddress(URL(string: "https://openrouter.ai/api/v1/")!) == "openrouter.ai/api/v1")
    #expect(ProviderPreset.matching(URL(string: "http://localhost:11434/v1")!) == .ollama)
}

@Test func verificationReportsTheModelCountOrAReadableReason() async {
    func check(_ respond: @escaping @Sendable (String, [String: Any]) -> (Int, Any)) async -> ProviderCheck {
        await OpenAICompatibleClient(provider: openRouter, key: "k", http: StubHTTP(respond)).verify()
    }
    #expect(await check { _, _ in ok(["data": [["id": "a"], ["id": "b"]]]) } == .verified(models: 2))
    #expect(await check { _, _ in fail(401) } == .failed("Invalid API key."))
    #expect(await check { _, _ in fail(403) }.failureText.contains("guardrails"))
    #expect(await check { _, _ in fail(404) }.failureText.contains("Wrong address"))
    #expect(await check { _, _ in ok(["not": "a list"]) }.failureText.contains("OpenAI-compatible"))
    #expect(ProviderCheck.describe(URLError(.cannotConnectToHost)).contains("Can't connect"))
}

private extension ProviderCheck {
    var failureText: String { if case .failed(let t) = self { t } else { "" } }
}
