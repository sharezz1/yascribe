import Foundation
import Testing
@testable import MeetNotesSessionFormat

/// 1 tik = 1 ns, żeby liczby w testach dało się czytać.
private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func baseEvents() -> [JournalEvent] {
    [
        .sessionStarted(hostTime: 0, timebase: ns, wallClock: Date(timeIntervalSince1970: 0)),
        .trackOpened("system", hostTime: 0, sampleRate: 48_000, channels: 2, deviceUID: "spk"),
        .trackOpened("mic_raw", hostTime: 0, sampleRate: 16_000, channels: 1, deviceUID: "mic"),
        .trackFirstSample("system", hostTime: 38_000_000),
        .trackFirstSample("mic_raw", hostTime: 203_000_000),
    ]
}

@Test func offsetsAreMeasuredAgainstSystemTrack() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents())
    let mic = try #require(sum.tracks.first { $0.id == "mic_raw" })
    #expect(abs((mic.offsetSeconds ?? 0) - 0.165) < 1e-9)
    #expect(sum.tracks.first { $0.id == "system" }?.offsetSeconds == 0)
}

@Test func sessionWithoutEndIsMarkedCrashed() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents())
    #expect(sum.crashed)
    #expect(sum.endReason == nil)
}

@Test func endedSessionCarriesReasonAndFrames() throws {
    let events = baseEvents() + [
        .trackClosed("system", frames: 480_000, hostTime: 10 * s),
        .sessionEnded(reason: "silence", hostTime: 10 * s),
    ]
    let sum = try SessionSummary.rebuild(from: events)
    #expect(!sum.crashed)
    #expect(sum.endReason == "silence")
    #expect(sum.tracks.first { $0.id == "system" }?.frames == 480_000)
}

@Test func gapsAndDeviceChangesAreCollected() throws {
    let events = baseEvents() + [
        .deviceChanged("system", deviceUID: "airpods", hostTime: 5 * s),
        .trackGap("system", frameIndex: 240_000, gapFrames: 14_400, hostTime: 5 * s),
    ]
    let sys = try #require(try SessionSummary.rebuild(from: events).tracks.first { $0.id == "system" })
    #expect(sys.deviceUIDs == ["spk", "airpods"])
    #expect(sys.gaps == [.init(frameIndex: 240_000, frames: 14_400)])
}

@Test func missingStartIsRejected() {
    #expect(throws: SessionSummaryError.missingSessionStart) {
        _ = try SessionSummary.rebuild(from: [.trackFirstSample("system", hostTime: 1)])
    }
}

@Test func clockAnchorsAbsorbDeviceClockDrift() throws {
    // Urządzenie deklaruje 48 000 Hz, a naprawdę daje 48 010 Hz (dryf ~208 ppm,
    // rząd wielkości zmierzony u Narady: 213 ms na 901 s).
    let real = 48_010.0
    var events = baseEvents()
    for k in 1...510 { // co 10 s przez 85 minut
        let frame = Int(Double(k) * 10 * real)
        events.append(.trackClock("system", frameIndex: frame, hostTime: 38_000_000 + UInt64(k) * 10 * s))
    }
    let sum = try SessionSummary.rebuild(from: events)
    let frame = Int(5_000 * real) // ok. 83 minuta
    let truth = 38_000_000 + 5_000 * s
    let got = try #require(sum.hostTime(track: "system", frame: frame))
    let errorMs = abs(ns.secondsBetween(got, truth)) * 1000
    #expect(errorMs <= 50) // T8
    // Nominalna częstotliwość pomyliłaby się o ponad sekundę:
    let naive = 38_000_000 + ns.ticks(seconds: Double(frame) / 48_000)
    #expect(abs(ns.secondsBetween(naive, truth)) > 1.0)
    #expect(abs((sum.tracks[0].effectiveSampleRate ?? 0) - real) < 0.5)
}

@Test func directoryInfersFramesOfCrashedTrackFromFileSize() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sd = SessionDirectory(url: dir)
    let j = try SessionJournal(url: sd.journalURL)
    for e in baseEvents() { try j.append(e) }
    try j.close()
    // 1000 ramek stereo Int16 = 4000 bajtów danych + nagłówek
    try Data(count: CAFLayout.headerSize + 4_000).write(to: sd.trackURL("system"))
    let sum = try sd.rebuildSummaryFile()
    #expect(sum.tracks.first { $0.id == "system" }?.frames == 1_000)
    #expect(FileManager.default.fileExists(atPath: sd.summaryURL.path))
}
