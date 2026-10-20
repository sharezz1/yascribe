import FluidAudio
import Foundation
import Testing
import MeetNotesProviders
import MeetNotesTranscription
@testable import MeetNotesLocalASR

private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources", isDirectory: true)

private func swiftSources(excludingLocalASR: Bool = false) throws -> [(url: URL, text: String)] {
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var out: [(URL, String)] = []
    for case let url as URL in files where url.pathExtension == "swift" {
        if excludingLocalASR, url.path.contains("/MeetNotesLocalASR/") { continue }
        out.append((url, try String(contentsOf: url, encoding: .utf8)))
    }
    return out
}

private func matches(_ pattern: String, in text: String) -> [String] {
    let re = try! NSRegularExpression(pattern: pattern)
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 0), in: text).map { String(text[$0]) } }
}

/// Decyzja Opusa 7a / anty-cel „pobieranie bez zgody": warianty ładowania FluidAudio przez centrum pobierań mogą dociągać pliki z HF.
/// Z `AsrModels` wolno tylko: `loadLocal` (ładowanie bez sieci), `modelsExist` (lokalna obecność plików), `defaultCacheDirectory`
/// oraz `download` — to ostatnie wyłącznie w `ModelStore.swift` (po akcji użytkownika). Reszta powierzchni sieciowej jest zakazana w całych Sources.
@Test func sourcesNeverUseNetworkingModelLoaders() throws {
    let all = try swiftSources()
    #expect(all.count > 20)
    for (url, text) in all {
        let name = url.lastPathComponent
        for call in matches(#"AsrModels\s*\.\s*(\w+)"#, in: text) {
            let member = call.split(separator: ".").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            switch member {
            case "loadLocal", "modelsExist", "defaultCacheDirectory": break
            case "download": #expect(name == "ModelStore.swift", "\(name) calls AsrModels.download")
            default: Issue.record("\(name) uses AsrModels.\(member)")
            }
        }
        for word in ["downloadAndLoad", "isModelValid", "ModelHub.", "DownloadUtils", "AssetDownloader", "HFClient", "ModelRegistry"] {
            #expect(!text.contains(word), "\(name) uses \(word)")
        }
    }
}

@Test func onlyLocalASRImportsFluidAudio() throws {
    for (url, text) in try swiftSources(excludingLocalASR: true) {
        #expect(matches(#"import\s+(\w+\s+)?FluidAudio"#, in: text).isEmpty, "\(url.lastPathComponent) imports FluidAudio")
        #expect(!text.contains("@_exported"), "\(url.lastPathComponent) re-exports a module")
    }
}

@Test func theGuardRegexesCatchTheBypassVariants() {
    let pattern = #"import\s+(\w+\s+)?FluidAudio"#
    for variant in ["import FluidAudio", "import   FluidAudio", "@preconcurrency import FluidAudio", "import\tFluidAudio", "internal import FluidAudio"] {
        #expect(!matches(pattern, in: variant).isEmpty, "\(variant)")
    }
    #expect(matches(pattern, in: "import FluidAudioX").count == 1) // prefiks też łapany (lepiej fałszywy alarm)
    #expect(matches(#"AsrModels\s*\.\s*(\w+)"#, in: "AsrModels\n  .load(from: x)").count == 1)
}

@Test func engineWithMissingModelFailsLocallyWithoutTouchingTheNetwork() async throws {
    // Pusty magazyn: `loadLocal` rzuca lokalny `modelNotFound` (żaden wariant z siecią nie jest wołany, więc nic nie jest pobierane).
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let engine = FluidAudioEngine(store: ModelStore(directory: root, download: { _, _, _ in }))
    // Pas bezpieczeństwa: przy regresji (ładowanie przez centrum pobierań) FluidAudio rzuci `networkDisabled` zamiast pobrać 483 MB.
    let wasOffline = ModelHub.offlineMode
    ModelHub.offlineMode = true
    defer { ModelHub.offlineMode = wasOffline }
    do {
        try await engine.load()
        Issue.record("expected modelNotFound")
    } catch let error as AsrModelsError {
        guard case .modelNotFound = error else { Issue.record("unexpected \(error)"); return }
    }
    #expect(!FileManager.default.fileExists(atPath: root.path), "a failed load must not create or download anything")
}

/// Opt-in: prawdziwy silnik na kopii modelu. Ręcznie (ok. 20 s na zimno, debug dłużej):
///   MEETNOTES_MODEL_STORE=$PWD/.devdata/model-store scripts/test.sh --filter realEngineOnModelCopy
/// (stara nazwa `MEETNOTES_LOCAL_ASR_STORE` też działa). Bez zmiennej kończy się od razu; ze zmienną i bez gotowego modelu — błąd.
@Test func realEngineOnModelCopy() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let root = env["MEETNOTES_MODEL_STORE"] ?? env["MEETNOTES_LOCAL_ASR_STORE"], !root.isEmpty else { return }
    let store = ModelStore(directory: URL(fileURLWithPath: root, isDirectory: true), download: { _, _, _ in })
    guard store.status() == .ready else {
        Issue.record("the model store at \(root) is not ready: \(store.status())")
        return
    }
    let wasOffline = ModelHub.offlineMode
    ModelHub.offlineMode = true // ten test nigdy nie pobiera
    defer { ModelHub.offlineMode = wasOffline }
    let client = LocalASRClient(provider: Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio),
                                engine: FluidAudioEngine(store: store), store: store)
    // Klip sondy (polski, „raz dwa trzy") przesunięty o 16 s w 20 s ciszy: słowa muszą trafić na oś czasu okna, nie na jego początek.
    let clip = try WAVDecoder.samples(ProbeClips.polish.wav)
    var samples = [Float](repeating: 0, count: 20 * 16_000)
    let offset = 16 * 16_000
    for (i, v) in clip.prefix(samples.count - offset).enumerated() { samples[offset + i] = v }
    let pcm = samples.map { Int16(max(-1, min(1, $0)) * 32_767) }
    let r = try await client.transcribe(wav: WAVEncoder.wav(pcm, rate: 16_000), model: "parakeet-tdt-0.6b-v3", language: .polish, shape: .audioTranscriptions)
    await client.release()
    let words = r.words ?? []
    #expect(!words.isEmpty, "expected words from the Polish probe clip, got text: \(r.text)")
    #expect(words.allSatisfy { $0.start >= 15.5 && $0.end <= 20 && $0.end >= $0.start })
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
}
