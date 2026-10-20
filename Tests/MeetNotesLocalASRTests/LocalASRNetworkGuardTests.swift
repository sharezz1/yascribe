import FluidAudio
import Foundation
import Testing
import MeetNotesProviders
import MeetNotesTranscription
@testable import MeetNotesLocalASR

private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources", isDirectory: true)

/// Decyzja Opusa 7a / anty-cel „pobieranie bez zgody": warianty ładowania FluidAudio przez ModelHub mogą dociągać pliki z HF.
/// Jedyne dozwolone ładowanie to `loadLocal`; pobranie to `AsrModels.download(to:)` z `ModelStore`, po akcji użytkownika.
@Test func sourcesNeverUseNetworkingModelLoaders() throws {
    let forbidden = ["AsrModels.load(", "downloadAndLoad", "isModelValid"]
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var scanned = 0
    for case let url as URL in files where url.pathExtension == "swift" {
        scanned += 1
        let text = try String(contentsOf: url, encoding: .utf8)
        for word in forbidden { #expect(!text.contains(word), "\(url.lastPathComponent) uses \(word)") }
    }
    #expect(scanned > 20)
}

@Test func onlyLocalASRImportsFluidAudio() throws {
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let url as URL in files where url.pathExtension == "swift" && !url.path.contains("/MeetNotesLocalASR/") {
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("import FluidAudio"), "\(url.lastPathComponent) imports FluidAudio")
    }
}

@Test func engineWithMissingModelFailsLocallyWithoutTouchingTheNetwork() async throws {
    // Pusty magazyn: `loadLocal` rzuca lokalny `modelNotFound` (żaden wariant z siecią nie jest wołany, więc nic nie jest pobierane).
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let engine = FluidAudioEngine(store: ModelStore(directory: root, download: { _, _, _ in }))
    do {
        try await engine.load()
        Issue.record("expected modelNotFound")
    } catch let error as AsrModelsError {
        guard case .modelNotFound = error else { Issue.record("unexpected \(error)"); return }
    }
    #expect(!FileManager.default.fileExists(atPath: root.path), "a failed load must not create or download anything")
}

/// Opt-in: prawdziwy silnik na kopii modelu. Ręcznie (ok. 20 s na zimno, debug dłużej):
///   MEETNOTES_LOCAL_ASR_STORE=$PWD/.devdata/model-store scripts/test.sh --filter realEngineOnModelCopy
/// Bez zmiennej (albo bez gotowego modelu) kończy się od razu — zwykłe `scripts/test.sh` nie ładuje modelu.
@Test func realEngineOnModelCopy() async throws {
    guard let root = ProcessInfo.processInfo.environment["MEETNOTES_LOCAL_ASR_STORE"] else { return }
    let store = ModelStore(directory: URL(fileURLWithPath: root, isDirectory: true), download: { _, _, _ in })
    guard store.status() == .ready else { return }
    let client = LocalASRClient(provider: Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio),
                                engine: FluidAudioEngine(store: store), store: store)
    // 3 s ciszy: silnik działa end to end (bez treści nagrań w repo); wynik nie ma słów, ale nie rzuca.
    let silence = WAVEncoder.wav([Int16](repeating: 0, count: 48_000), rate: 16_000)
    let r = try await client.transcribe(wav: silence, model: "parakeet-tdt-0.6b-v3", language: .polish, shape: .audioTranscriptions)
    #expect((r.words ?? []).allSatisfy { $0.end >= $0.start })
    await client.release()
}
