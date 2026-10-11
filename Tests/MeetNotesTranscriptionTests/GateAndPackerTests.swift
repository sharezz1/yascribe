import Foundation
import Testing
@testable import MeetNotesTranscription

private func floats(_ s: [Int16]) -> [Float] { s.map { Float($0) / 32_768 } }

@Test func resamplerKeepsDurationAndEnergy() throws {
    let stereo = tone(seconds: 1, rate: 48_000).flatMap { [$0, $0] }
    let x = try Resampler.toASR(stereo, sampleRate: 48_000, channels: 2)
    #expect(abs(x.count - 16_000) <= 16)
    let rms = (x.map { Double($0 * $0) }.reduce(0, +) / Double(x.count)).squareRoot()
    #expect(rms > 0.18 && rms < 0.25) // sinus 0,3 → RMS ≈ 0,21
}

@Test func pureSilenceProducesNoRegions() {
    // P6: cisza nie generuje żadnego żądania.
    #expect(EnergyGate().speechRegions(floats(silence(seconds: 30, rate: 16_000)), rate: 16_000).isEmpty)
}

@Test func burstBecomesOneRegionWithPadding() {
    let x = floats(silence(seconds: 5, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 5, rate: 16_000))
    let r = EnergyGate().speechRegions(x, rate: 16_000)
    #expect(r.count == 1)
    #expect(abs(Double(r[0].lowerBound) / 16_000 - 4.8) < 0.05)
    #expect(abs(Double(r[0].upperBound) / 16_000 - 7.2) < 0.05)
}

@Test func clickShorterThanAttackIsIgnored() {
    let x = floats(silence(seconds: 2, rate: 16_000) + tone(seconds: 0.04, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    #expect(EnergyGate().speechRegions(x, rate: 16_000).isEmpty)
}

@Test func shortPauseDoesNotSplitSpeech() {
    let x = floats(tone(seconds: 1, rate: 16_000) + silence(seconds: 0.3, rate: 16_000) + tone(seconds: 1, rate: 16_000)
                   + silence(seconds: 2, rate: 16_000))
    #expect(EnergyGate().speechRegions(x, rate: 16_000).count == 1)
}

@Test func shortRegionsArePackedIntoLongWindows() {
    // „Nie tnij na sekundy" (rozdz. 13): 12 fragmentów po 2,4 s → jedno okno, nie dwanaście.
    let regions = (0..<12).map { i in (i * 160_000)..<(i * 160_000 + 38_400) }
    let chunks = ChunkPacker(maxSeconds: 59).pack(regions, samples: [Float](repeating: 0.1, count: 12 * 160_000))
    #expect(chunks.count == 1)
    #expect(chunks[0].segments.count == 12)
    #expect(Double(chunks[0].length) / 16_000 < 59)
}

@Test func windowNeverExceedsModelLimit() {
    let regions = (0..<40).map { i in (i * 160_000)..<(i * 160_000 + 80_000) } // 40 × 5 s
    let chunks = ChunkPacker(maxSeconds: 59).pack(regions, samples: [Float](repeating: 0.1, count: 40 * 160_000))
    #expect(chunks.allSatisfy { Double($0.length) / 16_000 <= 59 })
    #expect(chunks.flatMap(\.segments).count == 40)
}

@Test func longSpeechIsCutAtTheQuietestPointBeforeTheLimit() {
    // 90 s ciągłej mowy z cichym miejscem w 57. sekundzie.
    var x = [Float](repeating: 0.3, count: 90 * 16_000)
    for i in (57 * 16_000)..<(57 * 16_000 + 800) { x[i] = 0.001 }
    let chunks = ChunkPacker(maxSeconds: 59).pack([0..<x.count], samples: x)
    #expect(chunks.count == 2)
    let cut = Double(chunks[0].segments[0].sourceEnd) / 16_000
    #expect(abs(cut - 57.025) < 0.03)
}

@Test func chunkTimeMapsBackToTrackTime() {
    let c = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                       ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    #expect(abs(c.sourceSeconds(chunkSeconds: 1.0, rate: 16_000) - 6.0) < 1e-9)   // w 1. fragmencie
    #expect(abs(c.sourceSeconds(chunkSeconds: 3.2, rate: 16_000) - 15.5) < 1e-9)  // 0,5 s w 2. fragmencie
    #expect(abs(c.sourceSeconds(chunkSeconds: 2.5, rate: 16_000) - 7.4) < 1e-9)   // w przerwie → krawędź 1. fragmentu
}

@Test func wavHasCorrectHeaderAndLength() {
    let d = WAVEncoder.wav([1, 2, 3, 4], rate: 16_000)
    #expect(d.count == 44 + 8)
    #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
    #expect(d[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) } == 16_000)
}
