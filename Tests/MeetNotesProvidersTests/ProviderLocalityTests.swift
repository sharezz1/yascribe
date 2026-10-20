import Foundation
import Testing
@testable import MeetNotesProviders

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
