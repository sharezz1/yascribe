import Foundation
import Testing
@testable import MeetNotesProviders

@Test func presetsComeWithReadyAddressesAndRoles() {
    #expect(ProviderPreset.all.map(\.name) == ["OpenRouter", "ElevenLabs", "Ollama", "llama.cpp", "oMLX", "Custom endpoint"])
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
    #expect(ProviderPreset.matching(prov("http://localhost:9090/v1")) == nil) // inny port
    #expect(ProviderPreset.matching(prov("https://api.elevenlabs.io", kind: .elevenLabs)) == .elevenLabs)
    #expect(ProviderPreset.matching(prov("https://example.com/v1")) == nil)
    #expect(ProviderPreset.matching(URL(string: "http://localhost:11434/v1")!) == .ollama)
    #expect(ProviderPreset.displayAddress(URL(string: "https://openrouter.ai/api/v1/")!) == "openrouter.ai/api/v1")
}

@Test func listShowsEveryPresetThenCustomProvidersThenAddCustom() {
    let empty = ProviderListRow.rows(for: [])
    // Model Yascribe (Parakeet) nie jest dostawcą: nie ma wiersza (F20 P3).
    #expect(empty.map(\.id) == ["preset-openrouter", "preset-elevenlabs", "preset-ollama", "preset-llamacpp", "preset-omlx", "add-custom"])
    #expect(empty.allSatisfy { if case .preset(_, let p) = $0 { p == nil } else { true } })

    let or = prov("https://openrouter.ai/api/v1", "OpenRouter")
    let or2 = prov("https://openrouter.ai/api/v1", "OpenRouter 2") // dostawca to instancja: drugi trafia do własnych
    let own = prov("https://llm.example.com/v1", "Work")
    let rows = ProviderListRow.rows(for: [own, or, or2])
    #expect(rows.map(\.id) == ["preset-openrouter", "preset-elevenlabs", "preset-ollama", "preset-llamacpp", "preset-omlx",
                               "custom-\(own.id.uuidString)", "custom-\(or2.id.uuidString)", "add-custom"])
    #expect(rows.first == .preset(.openRouter, or))
}

@Test func fluidAudioProviderIsMatchedByKindNotAddress() {
    let local = prov(Provider.fluidAudioBaseURL.absoluteString, "Parakeet", kind: .fluidAudio)
    #expect(ProviderPreset.matching(local) == .onThisMac)
    #expect(ProviderPreset.matching(prov("local://fluidaudio")) == nil) // ten sam adres bez rodzaju nie jest „On this Mac”
    let p = ProviderPreset.onThisMac
    #expect(p.id == "on-this-mac" && p.name == "On this Mac · Parakeet" && !p.needsKey && p.kind == .fluidAudio)
    #expect(p.baseURL == "local://fluidaudio" && p.role == "Speech-to-text on this Mac · no network")
    // Preset zostaje (dopasowanie, logo), ale nie jest na liście gotowych dostawców.
    #expect(ProviderPreset.ready == [.openRouter, .elevenLabs, .ollama, .llamaCpp, .omlx])
}

@Test func savedFluidAudioProviderIsNotShownInTheProviderList() {
    let local = prov(Provider.fluidAudioBaseURL.absoluteString, "Parakeet", kind: .fluidAudio)
    let rows = ProviderListRow.rows(for: [local])
    #expect(rows == ProviderListRow.rows(for: []))
    #expect(!rows.contains { if case .custom = $0 { true } else { false } })
    #expect(!rows.contains { if case .preset(_, let p) = $0 { p == local } else { false } })
}

@Test func onDeviceProviderRecordIsAddedOnceByKindNotByName() {
    var file = ProvidersFile(providers: [prov("https://openrouter.ai/api/v1", "OpenRouter")])
    let first = file.ensureOnDeviceProvider()
    let added = file.providers.last
    #expect(first && file.providers.count == 2 && added?.api == .fluidAudio && added?.baseURL == Provider.fluidAudioBaseURL)
    let second = file.ensureOnDeviceProvider() // idempotentne
    #expect(!second && file.providers.count == 2)
    // Rekord o innej nazwie, ale tego samego rodzaju, też wystarcza (preset trzyma `providerID`, nie nazwę).
    var renamed = ProvidersFile(providers: [prov(Provider.fluidAudioBaseURL.absoluteString, "Mine", kind: .fluidAudio)])
    let kept = renamed.ensureOnDeviceProvider()
    #expect(!kept && renamed.providers.count == 1)
    // Ten sam adres bez rodzaju to nie jest model w procesie.
    var plain = ProvidersFile(providers: [prov("local://fluidaudio")])
    let added2 = plain.ensureOnDeviceProvider()
    #expect(added2 && plain.providers.count == 2)
}

// MARK: dostawcy w rolach presetu (F20 P4)

@Test func correctionAndSummaryAreOfferedOnlyToTextProviders() {
    let or = prov("https://openrouter.ai/api/v1", "OpenRouter")
    let ollama = prov("http://localhost:11434/v1", "Ollama")
    let el = prov("https://api.elevenlabs.io", "ElevenLabs", kind: .elevenLabs)
    let local = prov(Provider.fluidAudioBaseURL.absoluteString, "On this Mac · Parakeet", kind: .fluidAudio)
    let all = [or, el, local, ollama]
    for role in [Role.correction, .summary] {
        #expect(RoleProviders.choices(all, role: role, current: nil).map(\.name) == ["OpenRouter", "Ollama"], "\(role)")
    }
    // ASR: wszyscy (Ollama bez ASR rozstrzyga sonda, nie lista).
    #expect(RoleProviders.choices(all, role: .asr, current: nil).count == 4)
}

@Test func presetAlreadyPointingAtAnUnsupportedProviderKeepsItInTheMenu() {
    // Zapisany preset z Parakeetem w korekcie: menu nie może pokazać „None" przy istniejącym przypisaniu i niczego nie kasujemy.
    let or = prov("https://openrouter.ai/api/v1", "OpenRouter")
    let local = prov(Provider.fluidAudioBaseURL.absoluteString, "On this Mac · Parakeet", kind: .fluidAudio)
    #expect(RoleProviders.choices([or, local], role: .correction, current: local.id).map(\.id) == [or.id, local.id])
    #expect(RoleProviders.choices([or, local], role: .correction, current: or.id).map(\.id) == [or.id])
}

@Test func onDeviceModelIsLabelledYascribeInRoleMenusWithoutRenamingTheRecord() {
    let local = prov(Provider.fluidAudioBaseURL.absoluteString, "On this Mac · Parakeet", kind: .fluidAudio)
    #expect(local.roleLabel == "Yascribe" && local.name == "On this Mac · Parakeet")
    #expect(prov("https://openrouter.ai/api/v1", "OpenRouter").roleLabel == "OpenRouter")
    #expect(prov("https://openrouter.ai/api/v1", "OpenRouter").supports(.embedding) && !local.supports(.embedding))
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
    // 403 u OpenAI-compatible zostaje błędem (guardrail dostawcy); ostrzeżeniem jest tylko 403 u ElevenLabs.
    #expect(await check { _, _ in fail(403) } == .failed(ProviderCheck.describe(ProviderError.http(403, ""))))
    #expect(await check { _, _ in fail(403) }.failureText.contains("guardrails"))
    #expect(await check { _, _ in fail(404) }.failureText.contains("Wrong address"))
    #expect(await check { _, _ in ok(["not": "a list"]) }.failureText.contains("OpenAI-compatible"))
    #expect(ProviderCheck.describe(URLError(.cannotConnectToHost)).contains("Can't connect"))
}

private extension ProviderCheck {
    var failureText: String { if case .failed(let t) = self { t } else { "" } }
}

@Test func llamaCppAndOmlxAreReadyProvidersWithoutKeys() {
    let l = ProviderPreset.llamaCpp, o = ProviderPreset.omlx
    #expect(l.id == "llamacpp" && l.name == "llama.cpp" && l.baseURL == "http://localhost:8080/v1" && !l.needsKey && l.kind == nil)
    #expect(o.id == "omlx" && o.name == "oMLX" && o.baseURL == "http://localhost:8000/v1" && !o.needsKey && o.kind == nil)
    #expect(l.role == "Runs on this Mac · correction and summary" && o.role == l.role)
    #expect(ProviderPreset.ready.contains(l) && ProviderPreset.ready.contains(o))
}

@Test func matchingFindsThemByAddress() {
    #expect(ProviderPreset.matching(prov("http://localhost:8080/v1")) == .llamaCpp)
    #expect(ProviderPreset.matching(prov("http://LocalHost:8000/v1/")) == .omlx)
    #expect(ProviderPreset.matching(URL(string: "http://localhost:8000/v1")!) == .omlx)
    #expect(ProviderPreset.matching(prov("http://192.168.1.5:8000/v1")) == nil) // LAN to nie oMLX „na tym Macu”
}

@Test func omlxKeyIsOptionalNotRequired() {
    #expect(!ProviderPreset.omlx.needsKey && ProviderPreset.omlx.keyOptional)
    for p in ProviderPreset.all + [.onThisMac] where p != .omlx { #expect(!p.keyOptional, "\(p.name)") }
}

@Test func storedProvidersAreUnaffectedByKeyOptional() throws {
    // E6: `keyOptional` żyje tylko w presecie (kodzie), nie w `providers.json`; stary plik dalej się wczytuje i pasuje do presetu.
    let json = String(decoding: try JSONEncoder().encode(prov("http://localhost:8000/v1", "oMLX")), as: UTF8.self)
    #expect(!json.lowercased().contains("optional"))
    let old = #"[{"id":"\#(UUID().uuidString)","name":"Old","baseURL":"http://localhost:8000/v1"}]"#
    let loaded = try JSONDecoder().decode([Provider].self, from: Data(old.utf8))
    #expect(loaded.first.flatMap(ProviderPreset.matching) == .omlx)
}
