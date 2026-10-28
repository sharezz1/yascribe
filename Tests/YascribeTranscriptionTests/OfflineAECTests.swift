import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

private let aecRate = 16_000

private func aecNoise(_ n: Int, seed: UInt64) -> [Float] {
    var state = seed
    var memory: Float = 0
    return (0..<n).map { i in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let random = Float(Int((state >> 32) % 65536) - 32768) / 32768
        memory = 0.8 * memory + 0.2 * random
        return memory * Float(0.5 + 0.5 * sin(Double(i)/16_000*2))
    }
}

private func aecSummary(_ n: Int, micOffset: Double = 0, micEffectiveRate: Double = 16_000,
                        extra: [JournalEvent] = []) throws -> SessionSummary {
    let base: UInt64 = 1_000_000_000
    let micFirst = UInt64(Double(base) + micOffset*1e9)
    var events: [JournalEvent] = [.sessionStarted(hostTime: base, timebase: ns, wallClock: Date(timeIntervalSince1970: 0))]
    for (id, first, rate) in [("system", base, 16_000.0), ("mic_raw", micFirst, micEffectiveRate)] {
        events += [.trackOpened(id, hostTime: base, sampleRate: 16_000, channels: 1, deviceUID: id),
                   .trackFirstSample(id, hostTime: first),
                   .trackClock(id, frameIndex: n, hostTime: first + UInt64(Double(n)/rate*1e9)),
                   .trackClosed(id, frames: n, hostTime: first + UInt64(Double(n)/rate*1e9))]
    }
    return try SessionSummary.rebuild(from: events + extra + [.sessionEnded(reason: "test", hostTime: base+20_000_000_000)])
}

private func aecEcho(_ reference: [Float]) -> [Float] {
    reference.indices.map { i in
        let a = i>=333 ? 0.5*reference[i-333] : 0
        let b = i>=777 ? 0.2*reference[i-777] : 0
        return a+b
    }
}

private func aecEnergy(_ x: ArraySlice<Float>) -> Double {
    x.reduce(0) { $0 + Double($1)*Double($1) } / Double(x.count)
}

@Test func offlineAECReducesEchoAndPreservesThePartialFinalFrame() throws {
    let n = 12*aecRate+137
    var far = aecNoise(n, seed: 100)
    let near = aecNoise(n, seed: 200)
    for i in 10*aecRate..<n { far[i] = 0 }
    var mic = aecEcho(far)
    for i in 10*aecRate..<n { mic[i] += near[i] }
    let result = try OfflineAEC.process(microphone: mic, system: far, summary: aecSummary(n), configuration: .init())
    #expect(result.report.disposition == .applied)
    #expect(result.report.correlation ?? 0 >= 0.25)
    #expect(result.samples.count == n)
    #expect(aecEnergy(result.samples[3*aecRate..<8*aecRate]) < aecEnergy(mic[3*aecRate..<8*aecRate])*0.01)
    #expect(aecEnergy(result.samples[(n-137)..<n]) > aecEnergy(mic[(n-137)..<n])*0.3)
}

@Test func offlineAECLeavesUncorrelatedOrMissingReferenceBitExact() throws {
    let n = 8*aecRate
    let far = aecNoise(n, seed: 11), mic = aecNoise(n, seed: 22)
    let sum = try aecSummary(n)
    let independent = try OfflineAEC.process(microphone: mic, system: far, summary: sum, configuration: .init())
    #expect(independent.report.disposition == .noEchoEvidence)
    #expect(independent.samples == mic)
    let absent = try OfflineAEC.process(microphone: mic, system: [], summary: sum, configuration: .init())
    #expect(absent.report.disposition == .notApplicable)
    #expect(absent.samples == mic)
    let silent = try OfflineAEC.process(microphone: mic, system: [Float](repeating: 0, count: n), summary: sum, configuration: .init())
    #expect(silent.report.disposition == .noEchoEvidence)
    #expect(silent.samples == mic)
}

@Test func offlineAECBypassesChangedDevicesBadClocksAndFailedTracks() throws {
    let n = 8*aecRate, far = aecNoise(8*aecRate, seed: 1)
    let mic = aecEcho(far)
    var sum = try aecSummary(n)
    sum.tracks[0].deviceUIDs.append("another-output")
    let changed = try OfflineAEC.process(microphone: mic, system: far, summary: sum, configuration: .init())
    #expect(changed.report.disposition == .deviceChanged)
    #expect(changed.samples == mic)
    sum = try aecSummary(n)
    sum.tracks[1].firstSampleHostTime = nil
    let invalid = try OfflineAEC.process(microphone: mic, system: far, summary: sum, configuration: .init())
    #expect(invalid.report.disposition == .unreliableClock)
    #expect(invalid.samples == mic)
    sum = try aecSummary(n)
    sum.tracks[0].failure = "test interruption"
    let failed = try OfflineAEC.process(microphone: mic, system: far, summary: sum, configuration: .init())
    #expect(failed.report.disposition == .unhealthyTrack)
    #expect(failed.samples == mic)
}

@Test func offlineAECPreservesMutedGapsAndReferenceOutagesWithoutShiftingSamples() throws {
    let n = 14*aecRate
    var far = aecNoise(n, seed: 40)
    var mic = aecEcho(far)
    for i in 5*aecRate..<6*aecRate { mic[i] = 0 }
    for i in 7*aecRate..<8*aecRate { far[i] = 0 }
    let events: [JournalEvent] = [
        .trackMute("mic_raw", muted: true, frameIndex: 4*aecRate, hostTime: 5_000_000_000),
        .trackMute("mic_raw", muted: false, frameIndex: 5*aecRate, hostTime: 6_000_000_000),
        .trackGap("mic_raw", frameIndex: 5*aecRate, gapFrames: aecRate, hostTime: 6_000_000_000),
        .trackGap("system", frameIndex: 7*aecRate, gapFrames: aecRate, hostTime: 8_000_000_000)]
    let result = try OfflineAEC.process(microphone: mic, system: far, summary: aecSummary(n, extra: events), configuration: .init())
    #expect(result.report.disposition == .applied)
    #expect(result.samples.count == mic.count)
    #expect(result.samples[4*aecRate..<6*aecRate] == mic[4*aecRate..<6*aecRate])
    #expect(result.samples[7*aecRate..<8*aecRate] == mic[7*aecRate..<8*aecRate])
    #expect(result.samples[5*aecRate..<6*aecRate].allSatisfy { $0 == 0 })
    #expect(result.report.processedSamples <= n - 3*aecRate)
    #expect(result.report.processedSamples > n - 4*aecRate)
}

@Test func offlineAECAlignsAnEarlierMicrophoneAndDriftingClock() throws {
    let n = 14*aecRate
    let offset = -0.12, micRate = 16_032.0, delay = 0.04
    // Broadband reference identifies a unique lag; periodic tones do not.
    let far = aecNoise(n, seed: 789)
    func signal(_ t: Double) -> Float {
        let position = t * 16_000
        guard position >= 0, position < Double(n-1) else { return 0 }
        let i = Int(position), fraction = Float(position-Double(i))
        return far[i]*(1-fraction) + far[i+1]*fraction
    }
    let mic = (0..<n).map { 0.4*signal(offset+Double($0)/micRate-delay) }
    let result = try OfflineAEC.process(microphone: mic, system: far,
                                        summary: aecSummary(n, micOffset: offset, micEffectiveRate: micRate), configuration: .init())
    #expect(result.report.disposition == .applied)
    #expect(result.samples.count == n)
    #expect(aecEnergy(result.samples[4*aecRate..<10*aecRate]) < aecEnergy(mic[4*aecRate..<10*aecRate])*0.1)
    #expect(result.samples[0..<1900] == mic[0..<1900])
}

@Test func offlineAECCompensatesAcousticDelayLongerThanItsFilterTail() throws {
    let n = 12*aecRate, lag = 4500
    let far = aecNoise(n, seed: 100)
    let mic = (0..<n).map { $0>=lag ? far[$0-lag]*0.5 : 0 }
    let result = try OfflineAEC.process(microphone: mic, system: far, summary: aecSummary(n), configuration: .init())
    #expect(result.report.disposition == .applied)
    #expect(abs((result.report.lagSeconds ?? 0)-Double(lag)/16_000) < 0.001)
    #expect(aecEnergy(result.samples[4*aecRate..<10*aecRate]) < aecEnergy(mic[4*aecRate..<10*aecRate])*0.01)
}

@Test func offlineAECProtectsArtificialReferencePrefixWhenSystemStartedEarlier() throws {
    let n = 12*aecRate, lag = 4500
    let far = aecNoise(n+aecRate, seed: 100)
    let mic = (0..<n).map { far[$0+aecRate-lag]*0.5 }
    var summary = try aecSummary(n, micOffset: 1)
    summary.tracks[0].frames = far.count
    let result = try OfflineAEC.process(microphone: mic, system: far, summary: summary, configuration: .init())
    #expect(result.report.disposition == .applied)
    // Delaying the already-aligned array creates this prefix regardless of
    // whether the original system file contained earlier reference history.
    let prefix = lag-256
    #expect(result.samples[0..<prefix] == mic[0..<prefix])
    #expect(aecEnergy(result.samples[4*aecRate..<10*aecRate]) < aecEnergy(mic[4*aecRate..<10*aecRate])*0.01)
}

@Test func offlineAECKeepsDoubleTalkSignalAndDoesNotAddLatency() throws {
    let n = 12*aecRate+137
    let far = aecNoise(n, seed: 100), near = aecNoise(n, seed: 200)
    var mic = aecEcho(far)
    for i in 6*aecRate..<n { mic[i] += near[i] }
    let result = try OfflineAEC.process(microphone: mic, system: far, summary: aecSummary(n), configuration: .init())
    #expect(result.report.disposition == .applied)
    let start = 8*aecRate
    var best = (-Double.infinity, 0)
    for lag in -300...300 {
        var xy=0.0, xx=0.0, yy=0.0
        for i in stride(from: start, to: n-300, by: 8) {
            let x=Double(result.samples[i]), y=Double(near[i-lag]); xy+=x*y; xx+=x*x; yy+=y*y
        }
        let correlation = xy/(xx*yy).squareRoot()
        if correlation > best.0 { best = (correlation, lag) }
    }
    #expect(best.0 > 0.8)
    #expect(best.1 == 0)
}

@Test func offlineAECRejectsUnknownProcessingVersions() throws {
    let unsupported = try JSONDecoder().decode(OfflineAEC.Configuration.self,
        from: Data(#"{"algorithmVersion":99,"libraryVersion":"1.2.1"}"#.utf8))
    #expect(throws: OfflineAEC.ProcessingError.unsupportedConfiguration) {
        _ = try OfflineAEC.process(microphone: [], system: [], summary: aecSummary(0), configuration: unsupported)
    }
}

@Test func offlineAECRunnerPreservesChunksAndLegacyResumeAndRejectsChangedAudio() async throws {
    let n = 12*aecRate
    let far = aecNoise(n, seed: 100), near = aecNoise(n, seed: 200)
    var mic = aecEcho(far)
    for i in 6*aecRate..<n { mic[i] += near[i] }
    let pcm: ([Float]) -> [Int16] = { $0.map { Int16(($0*16000).rounded()) } }
    let dir = try makeSession(system: pcm(far), mic: pcm(mic))
    var crosstalk = CrosstalkFilter(); crosstalk.correlationThreshold = 2
    let snap = try snapshot()
    _ = try await TranscriptionRunner(session: dir, runID: "legacy", snapshot: snap, client: client(ListeningASR()),
                                      maxChunkSeconds: 4, crosstalk: crosstalk, offlineAEC: nil).run()
    let again = ListeningASR()
    _ = try await TranscriptionRunner(session: dir, runID: "legacy", snapshot: snap, client: client(again),
                                      maxChunkSeconds: 4, crosstalk: crosstalk).run()
    #expect(again.requests == 0)
    let legacy = RunDirectory(session: dir, runID: "legacy")
    #expect(try JSONFile.load(RunInput?.self, from: legacy.input, default: nil)?.offlineAEC == nil)
    _ = try await TranscriptionRunner(session: dir, runID: "enabled", snapshot: snap, client: client(ListeningASR()),
                                      maxChunkSeconds: 4, crosstalk: crosstalk).run()
    let enabled = RunDirectory(session: dir, runID: "enabled")
    let meta = try #require(try JSONFile.load(RunMetadata?.self, from: enabled.metadata, default: nil))
    #expect(meta.offlineAEC?.disposition == .applied)
    let files = try FileManager.default.contentsOfDirectory(at: legacy.url.appendingPathComponent("chunks"), includingPropertiesForKeys: nil)
    for file in files {
        let a = try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: file))
        let b = try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: enabled.url.appendingPathComponent("chunks").appendingPathComponent(file.lastPathComponent)))
        #expect(a.chunk == b.chunk)
    }
    let audio = dir.appendingPathComponent("mic_raw.caf")
    let original = try Data(contentsOf: audio)
    var changed = original; changed[68+12345*2] ^= 1
    try changed.write(to: audio)
    let refused = ListeningASR()
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "enabled", snapshot: snap, client: client(refused),
                                          maxChunkSeconds: 4, crosstalk: crosstalk).run()
    }
    #expect(refused.requests == 0)
    try original.write(to: audio)
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "enabled", snapshot: snap, client: client(refused),
                                          maxChunkSeconds: 4, crosstalk: crosstalk, offlineAEC: nil).run()
    }
    let journal = dir.appendingPathComponent("journal.jsonl")
    var data = try Data(contentsOf: journal)
    data.append(try JSONEncoder().encode(JournalEvent.deviceChanged("system", deviceUID: "new-output", hostTime: 20_000_000_000)))
    data.append(0x0a); try data.write(to: journal)
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "enabled", snapshot: snap, client: client(refused),
                                          maxChunkSeconds: 4, crosstalk: crosstalk).run()
    }
    #expect(refused.requests == 0)
}

@Test func offlineAECRunnerAlsoFingerprintsBypassedSingleTrackAudio() async throws {
    let dir = try makeSession(system: tone(seconds: 3, rate: 16_000))
    let snap = try snapshot()
    _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(ListeningASR())).run()
    let input = try #require(try JSONFile.load(RunInput?.self, from: RunDirectory(session: dir, runID: "r").input, default: nil))
    #expect(input.offlineAECFingerprint != nil)
    let audio = dir.appendingPathComponent("system.caf")
    var data = try Data(contentsOf: audio); data[68+3000*2] ^= 1; try data.write(to: audio)
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(ListeningASR())).run()
    }
}

@Test func offlineAECRunnerDoesNotReprocessHealthyRecordedAEC() async throws {
    let samples = tone(seconds: 5, rate: 16_000)
    let dir = try makeSession(system: samples, mic: samples, micTrack: "mic_aec")
    let snap = try snapshot()
    _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(ListeningASR())).run()
    let run = RunDirectory(session: dir, runID: "r")
    let meta = try #require(try JSONFile.load(RunMetadata?.self, from: run.metadata, default: nil))
    #expect(meta.offlineAEC?.disposition == .notApplicable)
    let audio = dir.appendingPathComponent("mic_aec.caf")
    var data = try Data(contentsOf: audio); data[68+3000*2] ^= 1; try data.write(to: audio)
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "r", snapshot: snap, client: client(ListeningASR())).run()
    }
}
