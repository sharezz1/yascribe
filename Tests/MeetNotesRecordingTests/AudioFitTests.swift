import AVFoundation
import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

private func noise(_ n: Int, seed: UInt64) -> [Float] {
    var x = seed
    return (0..<n).map { _ in
        x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: x >> 11) % 2_000 - 1_000) / 4_000 // średnia zero
    }
}

@Test func identityGivesRSquaredOne() {
    let a = noise(8_000, seed: 1)
    let r = AudioFit.fit(reference: a, recorded: a, maxLagFrames: 10)
    #expect(r.rSquared > 0.9999)
    #expect(abs(r.gain - 1) < 1e-6)
    #expect(r.lagFrames == 0)
}

@Test func findsDelayedAndAttenuatedCopy() {
    // Profil inne narzędziea z rozdz. 18: system w nagraniu ze wzmocnieniem 0,06 i opóźnieniem.
    let a = noise(8_000, seed: 2)
    let delayed = [Float](repeating: 0, count: 240) + a.map { $0 * 0.06 }
    let r = AudioFit.fit(reference: a, recorded: delayed, maxLagFrames: 400)
    #expect(r.lagFrames == 240)
    #expect(abs(r.gain - 0.06) < 1e-3)
}

@Test func independentSignalsHaveLowCorrelation() {
    // T3: po AEC korelacja mikrofonu z systemem ≤ 0,12 (rozdz. 7).
    let r = AudioFit.fit(reference: noise(8_000, seed: 3), recorded: noise(8_000, seed: 4), maxLagFrames: 50)
    #expect(abs(r.correlation) < 0.12)
}

@Test func resampleKeepsDuration() {
    let x = [Float](repeating: 0.1, count: 48_000)
    #expect(AudioFit.resample(x, from: 48_000, to: 16_000).count == 16_000)
}

@Test func fitFilesFindsDelayedCopyInRealFiles() throws {
    // S3-9: to, co liczy `meetnotes-cli fit` — wzorzec przez AVAudioFile (wav), nagranie przez nasz CAF.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mn-fit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let ref = noise(8_000, seed: 5).map { Int16($0 * 32_000) }
    let refURL = dir.appendingPathComponent("ref.wav"), recURL = dir.appendingPathComponent("rec.caf")
    do {
        let fmt = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let f = try AVAudioFile(forWriting: refURL, settings: fmt.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let b = try #require(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(ref.count)))
        b.frameLength = AVAudioFrameCount(ref.count)
        ref.withUnsafeBufferPointer { b.int16ChannelData![0].update(from: $0.baseAddress!, count: ref.count) }
        try f.write(from: b)
    } // AVAudioFile domyka plik w deinit
    let w = try CAFWriter(url: recURL, sampleRate: 16_000, channels: 1)
    try w.append([Int16](repeating: 0, count: 240) + ref.map { Int16((Double($0) * 0.06).rounded()) })
    try w.close()
    let r = try AudioFit.fitFiles(reference: refURL, recording: recURL, maxLagMs: 25)
    #expect(r.lagFrames == 240)
    #expect(abs(r.gain - 0.06) < 1e-3)
    #expect(try AudioFit.readAnyAudio(refURL).samples == ref)
    #expect(throws: AudioSourceError.self) { try AudioFit.readAnyAudio(refURL, maxSeconds: 0.1) } // S3-1
}
