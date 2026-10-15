import Foundation
import Testing
@testable import MeetNotesProviders

@Test func providerTilesComeWithReadyAddresses() {
    #expect(ProviderPreset.all.map(\.name) == ["OpenRouter", "Ollama", "Custom"])
    #expect(ProviderPreset.openRouter.baseURL == "https://openrouter.ai/api/v1" && ProviderPreset.openRouter.needsKey)
    #expect(ProviderPreset.ollama.baseURL == "http://localhost:11434/v1" && !ProviderPreset.ollama.needsKey)
    #expect(ProviderPreset.ollama.note?.contains("can't transcribe") == true) // Ollama bez ASR — użytkownik ma to wiedzieć
    #expect(ProviderPreset.custom.baseURL.isEmpty && ProviderPreset.custom.needsKey)
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
