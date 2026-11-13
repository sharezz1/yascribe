import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

@Suite struct CohereRunnerTests {
    @Test func sourceSpanLimitsSparseSpeechAndLongRegionsWithoutChangingLegacyPacking() {
        let samples = [Float](repeating: 0.1, count: 160_000)
        var packer = ChunkPacker(maxSeconds: 59, maxSourceSpan: 30)
        packer.rate = 1_000
        let sparse = [0..<1_000, 40_000..<41_000, 80_000..<81_000]
        let bounded = packer.pack(sparse, samples: samples)
        #expect(bounded.count == 3)
        var legacy = packer; legacy.maxSourceSpan = nil
        #expect(legacy.pack(sparse, samples: samples).count == 1)
        #expect(bounded.allSatisfy { $0.segments.last!.sourceEnd - $0.segments.first!.sourceStart <= 30_000 })
        let long = packer.pack([0..<100_000], samples: samples)
        #expect(long.allSatisfy { $0.length <= 30_000 })
        #expect(long.flatMap(\.segments).reduce(0) { $0 + $1.length } == 100_000)
    }

    @Test func coherePackingCapsAudioAt12AndSourceAt30Seconds() {
        let samples = [Float](repeating: 0.1, count: 160_000 * 16)
        let regions = [0..<32_000, 25*16_000..<27*16_000, 60*16_000..<90*16_000]
        let chunks = ChunkPacker(maxSeconds: 12, maxSourceSpan: 30).pack(regions, samples: samples)
        #expect(chunks.count >= 4)
        #expect(chunks.allSatisfy { $0.length <= 12*16_000 && $0.sourceEndSeconds - $0.sourceStartSeconds <= 30 })
        #expect(chunks.flatMap(\.segments).reduce(0) { $0 + $1.length } == regions.reduce(0) { $0 + $1.count })
    }

    @Test func old59SecondInputWithoutSourceSpanResumesFromSavedSettings() async throws {
        let (samples, _) = burstTrack(seconds: 180, rate: 16_000)
        let dir = try makeSession(system: samples)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = try snapshot(), run = RunDirectory(session: dir, runID: "old")
        let first = try await TranscriptionRunner(session: dir, runID: "old", snapshot: snap, client: client(ListeningASR()), offlineAEC: nil).run()
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: run.input)) as? [String: Any])
        json.removeValue(forKey: "maxSourceSpan"); json.removeValue(forKey: "offlineAECFingerprint")
        try JSONSerialization.data(withJSONObject: json).write(to: run.input)
        let saved = try JSONDecoder().decode(RunInput.self, from: Data(contentsOf: run.input))
        #expect(saved.maxChunkSeconds == 59 && saved.maxSourceSpan == nil)
        let again = ListeningASR()
        let result = try await TranscriptionRunner(session: dir, runID: "old", snapshot: snap, client: client(again), maxChunkSeconds: 12, maxSourceSpan: 30).run()
        #expect(again.requests == 0)
        #expect(result == first)
    }

    @Test func resumeRestoresPackingGateCrosstalkAndAECEvenForMissingWindow() async throws {
        let (samples, _) = burstTrack(seconds: 90, rate: 16_000)
        let dir = try makeSession(system: samples, mic: samples)
        defer { try? FileManager.default.removeItem(at: dir) }
        var crosstalk = CrosstalkFilter(); crosstalk.correlationThreshold = 2
        let snap = try snapshot(), run = RunDirectory(session: dir, runID: "cohere")
        let first = try await TranscriptionRunner(session: dir, runID: "cohere", snapshot: snap, client: client(ListeningASR()), maxChunkSeconds: 12, maxSourceSpan: 30, crosstalk: crosstalk, offlineAEC: nil).run()
        let original = try Data(contentsOf: run.input)
        let saved = try JSONDecoder().decode(RunInput.self, from: original)
        #expect(saved.maxChunkSeconds == 12 && saved.maxSourceSpan == 30)
        var gate = EnergyGate.Config(); gate.thresholdDBFS = 0
        let again = ListeningASR()
        func runner() -> TranscriptionRunner {
            TranscriptionRunner(session: dir, runID: "cohere", snapshot: snap, client: client(again), maxChunkSeconds: 2, maxSourceSpan: 3, gate: EnergyGate(gate))
        }
        #expect(try await runner().run() == first)
        #expect(again.requests == 0)
        try FileManager.default.removeItem(at: run.chunk("mic_raw", 1))
        #expect(try await runner().run() == first)
        #expect(again.requests == 1)
        #expect(try Data(contentsOf: run.input) == original)
    }

    @Test func resumeRestoresNonNilAECInsteadOfCurrentConfiguration() async throws {
        let dir = try makeSession(system: tone(seconds: 3, rate: 16_000))
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = try snapshot()
        let first = try await TranscriptionRunner(session: dir, runID: "aec", snapshot: snap, client: client(ListeningASR())).run()
        let again = ListeningASR()
        #expect(try await TranscriptionRunner(session: dir, runID: "aec", snapshot: snap, client: client(again), offlineAEC: nil).run() == first)
        #expect(again.requests == 0)
        let input = try JSONDecoder().decode(RunInput.self, from: Data(contentsOf: RunDirectory(session: dir, runID: "aec").input))
        #expect(input.offlineAEC == .init())
    }

    @Test func changedModelFingerprintAndAudioStillRefuseResumeWithoutAEC() async throws {
        let dir = try makeSession(system: tone(seconds: 3, rate: 16_000))
        defer { try? FileManager.default.removeItem(at: dir) }
        var snap = try snapshot(); snap.modelFingerprint = "first"
        _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(ListeningASR()), offlineAEC: nil).run()
        var changed = snap; changed.modelFingerprint = "second"
        let again = ListeningASR()
        await #expect(throws: RunError.inputMismatch) {
            _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: changed, client: client(again)).run()
        }
        let audio = dir.appendingPathComponent("system.caf")
        var data = try Data(contentsOf: audio); data[68 + 6_000] ^= 1; try data.write(to: audio)
        await #expect(throws: RunError.inputMismatch) {
            _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(again)).run()
        }
        #expect(again.requests == 0)
    }
}
