import FluidAudio
import Foundation
import Synchronization
import Testing
import YascribeProviders
@testable import YascribeLocalASR

@Test func diarizerConfigMapsSensitivityToFaFbFromTableD2() {
    let expected: [(SpeakerSensitivity, Double, Double)] = [(.low, 0.07, 0.8), (.medium, 0.15, 0.4), (.high, 0.30, 0.8)]
    for (sensitivity, fa, fb) in expected {
        let config = SpeakerDiarizer.config(for: sensitivity)
        #expect(config.clustering.warmStartFa == fa, "\(sensitivity)")
        #expect(config.clustering.warmStartFb == fb, "\(sensitivity)")
        #expect(config.clustering.threshold == 0.6)
    }
}

@Test func diarizerSpaceGateNeedsTwicePCMSize() {
    let needed: Int64 = 2 * 16_000 * 4 * 10 // 10 s toru
    #expect(SpeakerDiarizer.hasRoomForPCM(trackSeconds: 10, freeBytes: needed))
    #expect(!SpeakerDiarizer.hasRoomForPCM(trackSeconds: 10, freeBytes: needed - 1))
}

@Test func diarizerSweepRemovesOnlyStalePrefixedRawFiles() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let now = Date()
    let files: [(String, TimeInterval, Bool)] = [ // nazwa, wiek, czy zostaje
        ("fluidaudio-streaming-OLD.raw", 3601, false),
        ("fluidaudio-streaming-NEW.raw", 3599, true),
        ("other-OLD.raw", 7200, true),
        ("fluidaudio-streaming-OLD.wav", 7200, true),
    ]
    for (name, age, _) in files {
        let url = dir.appendingPathComponent(name)
        try Data([1]).write(to: url)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }
    SpeakerDiarizer.sweepStaleTemporaryFiles(in: dir, now: now)
    for (name, _, kept) in files { #expect(fm.fileExists(atPath: dir.appendingPathComponent(name).path) == kept, "\(name)") }
}

@Test func diarizerRunWithoutModelFailsBeforeTouchingAudioOrDisk() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let diarizer = SpeakerDiarizer(store: DiarizerModelStore(directory: root, fetch: { _ in throw CancellationError() }))
    await #expect(throws: DiarizerModelStoreError.self) {
        _ = try await diarizer.run(systemTrack: root.appendingPathComponent("system.caf"), sensitivity: .medium, progress: nil)
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

private struct FactoryFailed: Error {}

@Test func diarizerRemovesThePCMFileWhenTheSourceFactoryFailsAfterCreatingIt() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let old = dir.appendingPathComponent("fluidaudio-streaming-OLD.raw") // cudzy (np. przebieg sprzed awarii) — nie nasz
    try Data([1]).write(to: old)
    let partial = dir.appendingPathComponent("fluidaudio-streaming-\(UUID().uuidString).raw")
    #expect(throws: FactoryFailed.self) {
        _ = try SpeakerDiarizer.makeSource(from: dir.appendingPathComponent("system.caf"), sampleRate: 16_000, in: dir) { _, _ in
            try Data(repeating: 0, count: 4096).write(to: partial) // jak FluidAudio: część PCM zapisana, potem błąd
            throw FactoryFailed()
        }
    }
    #expect(!fm.fileExists(atPath: partial.path))
    #expect(fm.fileExists(atPath: old.path))
}

@Test func diarizerRunsOneAtATimeAcrossInstances() async throws {
    let counter = Mutex((active: 0, peak: 0, runs: 0))
    let work: SpeakerDiarizer.Work = { _ in
        counter.withLock { $0.active += 1; $0.peak = max($0.peak, $0.active); $0.runs += 1 }
        try await Task.sleep(for: .milliseconds(100))
        counter.withLock { $0.active -= 1 }
        throw FactoryFailed() // błąd też zwalnia kolejkę
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let store = DiarizerModelStore(directory: root, fetch: { _ in throw CancellationError() })
    let a = SpeakerDiarizer(store: store, work: work), b = SpeakerDiarizer(store: store, work: work)
    let track = root.appendingPathComponent("system.caf")
    async let x: Void = { _ = try? await a.run(systemTrack: track, sensitivity: .medium, progress: nil) }()
    async let y: Void = { _ = try? await b.run(systemTrack: track, sensitivity: .medium, progress: nil) }()
    async let z: Void = { _ = try? await a.run(systemTrack: track, sensitivity: .medium, progress: nil) }()
    _ = await (x, y, z)
    let (_, peak, runs) = counter.withLock { $0 }
    #expect(runs == 3)
    #expect(peak == 1)
}

/// Atrapa kroków menedżera: zapisuje kolejność; `prepare` rzuca, bo prawdziwego wyniku nie da się zbudować bez modelu.
private final class SpySteps: DiarizationSteps, Sendable {
    let calls = Mutex<[String]>([])
    let prepareError: any Error & Sendable
    init(prepareError: any Error & Sendable = FactoryFailed()) { self.prepareError = prepareError }
    func initialize(models: Int) { calls.withLock { $0.append("initialize(\(models))") } }
    func prepare(audioSource: any AudioSampleSource, audioLoadingSeconds: TimeInterval,
                 progressCallback: (@Sendable (Int, Int) -> Void)?) async throws -> PreparedDiarization {
        calls.withLock { $0.append("prepare") }
        throw prepareError
    }
    func cluster(_ prepared: PreparedDiarization) throws -> DiarizationResult {
        calls.withLock { $0.append("cluster") }
        throw FactoryFailed()
    }
}

@Test func diarizerInitializesTheManagerWithLoadedModelsBeforePrepare() async {
    let spy = SpySteps()
    let diarizer = SpeakerDiarizer(store: DiarizerModelStore(directory: URL(fileURLWithPath: "/nonexistent"), fetch: { _ in throw CancellationError() }))
    await #expect(throws: FactoryFailed.self) {
        _ = try await diarizer.diarize(spy, models: 7, source: ArrayAudioSampleSource(samples: []), progress: nil)
    }
    #expect(spy.calls.withLock { $0 } == ["initialize(7)", "prepare"])
}

/// Tor rozmówców bez mowy: FluidAudio rzuca `noSpeechDetected`; to pusty wynik (bez etykiet), nie błąd w aplikacji.
@Test func diarizerTreatsNoSpeechAsNoSegments() async throws {
    let spy = SpySteps(prepareError: OfflineDiarizationError.noSpeechDetected)
    let diarizer = SpeakerDiarizer(store: DiarizerModelStore(directory: URL(fileURLWithPath: "/nonexistent"), fetch: { _ in throw CancellationError() }))
    let segments = try await diarizer.diarize(spy, models: 1, source: ArrayAudioSampleSource(samples: []), progress: nil)
    #expect(segments.isEmpty)
    #expect(spy.calls.withLock { $0 } == ["initialize(1)", "prepare"])
}
