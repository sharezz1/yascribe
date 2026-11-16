import Foundation
import Testing
@testable import YascribeProviders

private func prov(_ url: String, kind: ProviderKind? = nil) -> Provider {
    Provider(name: "x", baseURL: URL(string: url)!, kind: kind)
}

@Test func loopbackHostsAreLocal() {
    for url in ["http://localhost:11434/v1", "http://127.0.0.1:8080/v1", "http://[::1]:8000/v1", "http://llm.localhost/v1",
                "http://127.0.0.2:8000/v1", "http://127.255.255.254/v1", "http://0.0.0.0:8080/v1", "http://localhost.:11434/v1",
                "http://llm.localhost./v1"] {
        #expect(prov(url).isLocal, "\(url)")
    }
}

@Test func lanTunnelAndRemoteHostsAreNotLocal() {
    for url in ["http://192.168.1.5:11434/v1", "http://my-mac.local:8000/v1", "https://openrouter.ai/api/v1",
                "http://127.evil.com/v1", "http://0.0.0.1/v1", "http://128.0.0.1/v1", "http://notlocalhost/v1"] {
        #expect(!prov(url).isLocal, "\(url)")
    }
}

@Test func fluidAudioIsLocalWithoutAnAddress() {
    #expect(Provider.fluidAudioBaseURL.absoluteString == "local://fluidaudio")
    #expect(Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio).isLocal)
}

@Test func elevenLabsOnLoopbackIsStillNotLocal() {
    #expect(!prov("http://localhost:9000/v1", kind: .elevenLabs).isLocal)
}

@Test func oldProvidersJSONWithoutKindStillLoads() throws {
    let json = #"[{"id":"\#(UUID().uuidString)","name":"Old","baseURL":"https://openrouter.ai/api/v1"}]"#
    let list = try JSONDecoder().decode([Provider].self, from: Data(json.utf8))
    #expect(list.first?.api == .openAICompatible && list.first?.kind == nil)
}

@Test func keylessGateAcceptsOnlyLocalProviders() {
    #expect(!prov("http://localhost:11434/v1").requiresKey) // Ollama
    #expect(prov("https://openrouter.ai/api/v1").requiresKey)
    #expect(prov("https://api.elevenlabs.io/v1", kind: .elevenLabs).requiresKey)
    #expect(!Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio).requiresKey)
}

@Test func unlinkedLocalClientAlwaysRefusesAndVerifyDefersToTheApp() async {
    let p = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    let client = p.transcriptionClient(key: nil)
    #expect(client is UnlinkedLocalClient)
    await #expect(throws: ProviderError.badResponse("On-device transcription isn't linked in this build.")) {
        _ = try await client.transcribe(wav: Data(), model: "m", language: nil, shape: .chatAudio)
    }
    #expect(await p.verify(key: nil) == .failed("Checked inside the app."))
}

// MARK: agenci CLI (TASK-86)

private let codexAgent = Provider(name: "Codex", baseURL: URL(fileURLWithPath: "/opt/homebrew/bin/codex"), kind: .codexCLI)
private let claudeAgent = Provider(name: "Claude Code", baseURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"), kind: .claudeCLI)

@Test func agentCLIsAreRemoteKeylessAndOnlyForCorrectionAndSummary() {
    for p in [codexAgent, claudeAgent] {
        #expect(!p.isLocal && !p.requiresKey)
        #expect(p.supports(.correction) && p.supports(.summary))
        #expect(!p.supports(.asr) && !p.supports(.embedding))
    }
    #expect(codexAgent.api.agentVendor == "OpenAI" && claudeAgent.api.agentVendor == "Anthropic")
    let all = [codexAgent, claudeAgent]
    #expect(RoleProviders.choices(all, role: .summary, current: nil).count == 2)
    #expect(RoleProviders.choices(all, role: .asr, current: nil).isEmpty)
}

@Test func agentKindDecodesAndOlderRecordsKeepTheirIDs() throws {
    let cli = UUID(), kept = UUID()
    let json = #"[{"id":"\#(cli)","name":"Codex","baseURL":"file:///opt/homebrew/bin/codex","kind":"codexCLI"},"#
        + #"{"id":"\#(kept)","name":"Old","baseURL":"https://openrouter.ai/api/v1"}]"#
    let list = try JSONDecoder().decode([Provider].self, from: Data(json.utf8))
    #expect(list.map(\.api) == [.codexCLI, .openAICompatible])
    // R12: po ręcznym usunięciu rekordu CLI (procedura downgrade) reszta dekoduje się z tymi samymi UUID.
    let pruned = try JSONDecoder().decode([Provider].self, from: JSONEncoder().encode(list.filter { !$0.api.isAgentCLI }))
    #expect(pruned.map(\.id) == [kept])
}

@Test func dictationNeverOffersAnAgentAndRefusesASavedOne() {
    let cloud = prov("https://openrouter.ai/api/v1")
    let all = [cloud, codexAgent, claudeAgent]
    #expect(DictationChoices.correction(all, current: nil).map(\.id) == [cloud.id])
    #expect(DictationChoices.correction(all, current: claudeAgent.id).map(\.id) == [cloud.id, claudeAgent.id])
    #expect(DictationChoices.refusal(cloud) == nil && DictationChoices.refusal(nil) == nil)
    #expect(DictationChoices.refusal(codexAgent) == .agentFailed("Codex can't correct dictation. Pick another model in Dictation settings."))
}
