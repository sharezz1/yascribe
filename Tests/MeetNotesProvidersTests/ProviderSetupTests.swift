import Foundation
import Testing
@testable import MeetNotesProviders

@Test func presetsComeWithReadyAddressesAndRoles() {
    #expect(ProviderPreset.all.map(\.name) == ["OpenRouter", "ElevenLabs", "Ollama", "Custom endpoint"])
    #expect(ProviderPreset.openRouter.baseURL == "https://openrouter.ai/api/v1" && ProviderPreset.openRouter.needsKey)
    #expect(ProviderPreset.elevenLabs.baseURL == "https://api.elevenlabs.io/v1" && ProviderPreset.elevenLabs.kind == .elevenLabs)
    #expect(ProviderPreset.elevenLabs.role == "Scribe v2 transcription · direct API")
    #expect(ProviderPreset.ollama.baseURL == "http://localhost:11434/v1" && !ProviderPreset.ollama.needsKey)
    #expect(ProviderPreset.ollama.role.contains("no transcription")) // Ollama bez ASR — użytkownik ma to wiedzieć
    #expect(ProviderPreset.custom.baseURL.isEmpty && ProviderPreset.custom.needsKey)
    #expect(ProviderPreset.openRouter.keyPage?.host() == "openrouter.ai" && ProviderPreset.elevenLabs.keyPage?.host() == "elevenlabs.io")
    #expect(ProviderPreset.ollama.keyPage == nil && ProviderPreset.custom.keyPage == nil)
}

private func prov(_ url: String, _ name: String = "x", kind: ProviderKind? = nil) -> Provider {
    Provider(name: name, baseURL: URL(string: url)!, kind: kind)
}

@Test func providerMatchesPresetByKindOrAddress() {
    #expect(ProviderPreset.matching(prov("https://OpenRouter.ai/api/v1/", "Mine")) == .openRouter) // wielkość liter hosta i końcowy „/”
    #expect(ProviderPreset.matching(prov("https://openrouter.ai/api/v2")) == nil)
    #expect(ProviderPreset.matching(prov("http://localhost:11434/v1")) == .ollama)
    #expect(ProviderPreset.matching(prov("http://localhost:8080/v1")) == nil) // inny port
    #expect(ProviderPreset.matching(prov("https://api.elevenlabs.io", kind: .elevenLabs)) == .elevenLabs)
    #expect(ProviderPreset.matching(prov("https://example.com/v1")) == nil)
    #expect(ProviderPreset.matching(URL(string: "http://localhost:11434/v1")!) == .ollama)
    #expect(ProviderPreset.displayAddress(URL(string: "https://openrouter.ai/api/v1/")!) == "openrouter.ai/api/v1")
}

@Test func listShowsEveryPresetThenCustomProvidersThenAddCustom() {
    let empty = ProviderListRow.rows(for: [])
    #expect(empty.map(\.id) == ["preset-openrouter", "preset-elevenlabs", "preset-ollama", "add-custom"])
    #expect(empty.allSatisfy { if case .preset(_, let p) = $0 { p == nil } else { true } })

    let or = prov("https://openrouter.ai/api/v1", "OpenRouter")
    let or2 = prov("https://openrouter.ai/api/v1", "OpenRouter 2") // dostawca to instancja: drugi trafia do własnych
    let own = prov("https://llm.example.com/v1", "Work")
    let rows = ProviderListRow.rows(for: [own, or, or2])
    #expect(rows.map(\.id) == ["preset-openrouter", "preset-elevenlabs", "preset-ollama",
                               "custom-\(own.id.uuidString)", "custom-\(or2.id.uuidString)", "add-custom"])
    #expect(rows.first == .preset(.openRouter, or))
}

@Test func archiveSearchOffersOnlyOpenAICompatibleProvidersAndClearsModelOnSwitch() {
    let or = prov("https://openrouter.ai/api/v1", "OpenRouter")
    let ollama = prov("http://localhost:11434/v1", "Ollama")
    let el = prov("https://api.elevenlabs.io", "ElevenLabs", kind: .elevenLabs)
    #expect(EmbeddingChoice.providers([or, el, ollama]).map(\.name) == ["OpenRouter", "Ollama"])
    #expect(EmbeddingChoice.showsProviderRow(candidates: [or, ollama]))
    #expect(!EmbeddingChoice.showsProviderRow(candidates: [or])) // jeden pasuje: bez wiersza „Provider”
    #expect(!EmbeddingChoice.showsProviderRow(candidates: []))

    let cur = RoleAssignment(providerID: or.id, model: "openai/text-embedding-3-small")
    #expect(EmbeddingChoice.select(provider: or.id, current: cur) == cur)
    #expect(EmbeddingChoice.select(provider: ollama.id, current: cur) == RoleAssignment(providerID: ollama.id, model: ""))
    #expect(EmbeddingChoice.select(provider: nil, current: cur) == nil)
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
