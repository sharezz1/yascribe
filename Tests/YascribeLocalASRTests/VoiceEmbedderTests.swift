import Foundation
import Synchronization
import Testing
@testable import YascribeLocalASR

private func tempRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true) }
private struct Boom: Error {}

@Test func campPlusManifestPinnedAndComplete() {
    #expect(CampPlusManifest.offline.totalBytes == 29_418_955)
    #expect(CampPlusManifest.offline.files.keys.allSatisfy { $0.hasPrefix("CamPlusPlus_v2.mlmodelc/") || $0.hasPrefix("CamPlusPreprocessor_v2.mlmodelc/") })
    #expect(CampPlusManifest.url(for: "a/b.bin").absoluteString
            == "https://huggingface.co/FluidInference/campplus-coreml/resolve/f316edbc70d9023a94aaf8965538aba4330dc28e/a/b.bin")
    let root = tempRoot()
    #expect(CampPlusManifest.store(root: root).directory == root.appendingPathComponent("Models/campplus", isDirectory: true))
    #expect(VoiceModel.diarizer.id == "diarizer/" + DiarizerManifest.pin && VoiceModel.campPlus.id != VoiceModel.diarizer.id)
}

@Test func campPlusStoreDownloadsFromItsOwnRepo() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let asked = Mutex<[String]>([])
    let base = CampPlusManifest.store(root: root)
    let store = DiarizerModelStore(directory: base.directory, manifest: CampPlusManifest.offline, remote: CampPlusManifest.url(for:)) { url in
        asked.withLock { $0.append(url.absoluteString) }
        throw Boom()
    }
    await #expect(throws: Boom.self) { try await store.download { _, _ in } }
    #expect(asked.withLock { $0 }.first?.hasPrefix("https://huggingface.co/FluidInference/campplus-coreml/resolve/f316edbc") == true)
}

@Test func combineWeightsByLength() throws {
    let v = try #require(VoiceEmbedder.combine([[2, 0], [0, 5]], weights: [3, 1]))
    #expect(abs(Double(v[0]) - 3 / 10.0.squareRoot()) < 0.0001 && abs(Double(v[1]) - 1 / 10.0.squareRoot()) < 0.0001)
    #expect(VoiceEmbedder.combine([[1, 0], [1]], weights: [1, 1]) == nil)
    #expect(VoiceEmbedder.combine([], weights: []) == nil)
}

@Test func embedderSharesTheDiarizationQueue() async throws {
    let counter = Mutex((active: 0, peak: 0, runs: 0))
    @Sendable func step() async throws {
        counter.withLock { $0.active += 1; $0.peak = max($0.peak, $0.active); $0.runs += 1 }
        try await Task.sleep(for: .milliseconds(100))
        counter.withLock { $0.active -= 1 }
    }
    let root = tempRoot()
    let store = DiarizerModelStore(directory: root, fetch: { _ in throw CancellationError() })
    let diarizer = SpeakerDiarizer(store: store, work: { _ in try await step(); return [] })
    let embedder = VoiceEmbedder(diarizerStore: store, campPlusStore: store, work: { _, _, _ in try await step(); return [:] })
    let track = root.appendingPathComponent("system.caf")
    async let x: Void = { _ = try? await diarizer.run(systemTrack: track, sensitivity: .medium, progress: nil) }()
    async let y: Void = { _ = try? await embedder.embed(systemTrack: track, speakers: [:], model: .diarizer) }()
    async let z: Void = { _ = try? await embedder.embed(systemTrack: track, speakers: [:], model: .campPlus) }()
    _ = await (x, y, z)
    #expect(counter.withLock { $0.runs } == 3 && counter.withLock { $0.peak } == 1)
}

@Test func embedderWithoutModelFailsBeforeTouchingDisk() async {
    let root = tempRoot()
    let store = DiarizerModelStore(directory: root, fetch: { _ in throw CancellationError() })
    let embedder = VoiceEmbedder(diarizerStore: store, campPlusStore: store)
    await #expect(throws: DiarizerModelStoreError.self) {
        _ = try await embedder.embed(systemTrack: root.appendingPathComponent("system.caf"), speakers: ["S1": [0...30]], model: .campPlus)
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func voiceModelCLINames() {
    #expect(VoiceModel(cliName: "diarizer") == .diarizer && VoiceModel(cliName: "campplus") == .campPlus && VoiceModel(cliName: "cam") == nil)
}
