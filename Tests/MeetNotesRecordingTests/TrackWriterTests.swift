import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func makeWriter(rate: Double = 16_000, tolerance: Double = 0.03) throws -> (TrackWriter, SessionJournal, URL) {
    let caf = try tempURL("mic_raw.caf")
    let j = try SessionJournal(url: caf.deletingLastPathComponent().appendingPathComponent("journal.jsonl"))
    let w = try TrackWriter(trackID: "mic_raw", url: caf, format: TrackFormat(sampleRate: rate, channels: 1, deviceUID: "mic"),
                            journal: j, timebase: ns, gapToleranceSeconds: tolerance)
    return (w, j, caf)
}

@Test func firstChunkIsJournaledAsFirstSample() throws {
    let (w, j, _) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: 5 * s))
    let events = try SessionJournal.read(url: j.url)
    #expect(events.first?.type == .trackFirstSample)
    #expect(events.first?.hostTime == 5 * s)
}

@Test func jumpBetweenChunksBecomesJournaledSilence() throws {
    let (w, j, caf) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 16_000, channels: 1, rate: 16_000), hostTime: 0))   // 0–1 s
    try w.write(AudioChunk(samples: sine(frames: 16_000, channels: 1, rate: 16_000), hostTime: 3 * s)) // luka 2 s
    try w.close(hostTime: 4 * s)
    let gaps = try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }
    #expect(gaps.count == 1)
    #expect(gaps[0].frameIndex == 16_000)
    #expect(gaps[0].gapFrames == 32_000)
    let r = try readInt16(caf)
    #expect(r.samples.count == 64_000)
    #expect(r.samples[16_000..<48_000].allSatisfy { $0 == 0 })
}

@Test func jitterBelowToleranceIsNotAGap() throws {
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<100 {
        try w.write(AudioChunk(samples: sine(frames: 160, channels: 1, rate: 16_000), hostTime: t))
        t += 10_000_000 + 2_000_000 // 10 ms danych, 12 ms odstępu: 2 ms jittera
    }
    #expect(try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }.isEmpty)
}

@Test func accumulatedDriftNeverInsertsSilence() throws {
    // Zegar urządzenia szybszy o 200 ppm: po 1000 porcjach suma rozjazdu
    // przekracza tolerancję, ale żadna para sąsiednich porcji — nie.
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<1_000 {
        try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
        t += 100_000_000 - 20_000 // 100 ms danych w 99,98 ms czasu hosta
    }
    #expect(try SessionJournal.read(url: j.url).filter { $0.type == .trackGap }.isEmpty)
}

@Test func clockAnchorsAreWrittenPeriodicallyAndAfterGaps() throws {
    let (w, j, _) = try makeWriter()
    var t: UInt64 = 0
    for _ in 0..<250 { // 25 s po 100 ms
        try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
        t += 100_000_000
    }
    t += 1 * s // luka
    try w.write(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: t))
    let clocks = try SessionJournal.read(url: j.url).filter { $0.type == .trackClock }
    #expect(clocks.map { $0.frameIndex } == [160_000, 320_000, 416_000])
    #expect(clocks.last?.hostTime == t)
}

@Test func closeJournalsFrameCount() throws {
    let (w, j, _) = try makeWriter()
    try w.write(AudioChunk(samples: sine(frames: 800, channels: 1, rate: 16_000), hostTime: 0))
    try w.close(hostTime: s)
    let closed = try SessionJournal.read(url: j.url).first { $0.type == .trackClosed }
    #expect(closed?.frames == 800)
}
