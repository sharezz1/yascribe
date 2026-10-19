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

// MARK: Wyciszanie torów i track.audible (macos.md §11.5)

@Test func mutePeriodsAreCollectedAndOneOpenAtStopEndsWithTheTrack() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents() + [
        .trackMute("mic_raw", muted: true, frameIndex: 80_000, hostTime: 5 * s),
        .trackMute("mic_raw", muted: false, frameIndex: 192_000, hostTime: 12 * s),
        .trackMute("mic_raw", muted: true, frameIndex: 320_000, hostTime: 20 * s),
        .trackAudible("system", frameIndex: 2_880_000, hostTime: 60 * s),
        .trackClosed("mic_raw", frames: 400_000, hostTime: 25 * s),
        .sessionEnded(reason: "button", hostTime: 25 * s),
    ])
    let mic = try #require(sum.tracks.first { $0.id == "mic_raw" })
    #expect(mic.mutes == [.init(frameIndex: 80_000, endFrame: 192_000), .init(frameIndex: 320_000, endFrame: 400_000)])
    #expect(sum.tracks.first { $0.id == "system" }?.audibleFrame == 2_880_000)
    #expect(sum.tracks.first { $0.id == "system" }?.mutes == nil)
}

@Test func crashWhileMutedLeavesTheMuteOpen() throws {
    let sum = try SessionSummary.rebuild(from: baseEvents() + [.trackMute("mic_raw", muted: true, frameIndex: 16_000, hostTime: s)])
    #expect(sum.tracks.first { $0.id == "mic_raw" }?.mutes == [.init(frameIndex: 16_000, endFrame: nil)])
}

/// Prawdziwy dziennik i `session.json` sprzed wyciszania (`.devdata`, sesja 2026-10-13T10-27-14Z): dziennik wczytuje się,
/// stare podsumowanie dekoduje się bez nowych pól, a przebudowa daje dokładnie to samo podsumowanie.
@Test func journalAndSummaryFromBeforeMutingLoadUnchanged() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mn-oldjournal-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(oldJournal.utf8).write(to: url)
    let rebuilt = try SessionSummary.rebuild(from: SessionJournal.read(url: url))
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let stored = try d.decode(SessionSummary.self, from: Data(oldSummary.utf8))
    #expect(rebuilt == stored)
    #expect(rebuilt.tracks.allSatisfy { $0.mutes == nil && $0.audibleFrame == nil })
}

private let oldJournal = #"""
{"hostTime":9653240567350,"timebase":{"denom":3,"numer":125},"type":"session.started","wallClock":"2026-10-13T10:27:14Z"}
{"channels":2,"deviceUID":"BuiltInSpeakerDevice","hostTime":9653241227925,"sampleFormat":"int16","sampleRate":48000,"trackID":"system","type":"track.opened"}
{"channels":1,"deviceUID":"BuiltInMicrophoneDevice","hostTime":9653241240234,"sampleFormat":"int16","sampleRate":16000,"trackID":"mic_raw","type":"track.opened"}
{"hostTime":9653242120099,"trackID":"mic_raw","type":"track.firstSample"}
{"frameIndex":160085,"hostTime":9653482246848,"trackID":"mic_raw","type":"track.clock"}
{"frameIndex":320170,"hostTime":9653722373589,"trackID":"mic_raw","type":"track.clock"}
{"hostTime":9653962190707,"reason":"stalled30s","trackID":"system","type":"track.failed"}
{"frameIndex":480256,"hostTime":9653962500344,"trackID":"mic_raw","type":"track.clock"}
{"frameIndex":640341,"hostTime":9654202627083,"trackID":"mic_raw","type":"track.clock"}
{"frameIndex":800426,"hostTime":9654442753809,"trackID":"mic_raw","type":"track.clock"}
{"hostTime":9654611985347,"trackID":"system","type":"track.firstSample"}
{"hostTime":9654611985347,"trackID":"system","type":"track.recovered"}
{"frameIndex":960512,"hostTime":9654682880545,"trackID":"mic_raw","type":"track.clock"}
{"frames":178688,"hostTime":9654702088245,"trackID":"system","type":"track.closed"}
{"frames":972800,"hostTime":9654702088245,"trackID":"mic_raw","type":"track.closed"}
{"hostTime":9654702088245,"reason":"button","type":"session.ended"}
"""#

private let oldSummary = #"""
{"crashed": false, "endReason": "button", "startedHostTime": 9653240567350, "timebase": {"denom": 3, "numer": 125}, "tracks": [{"channels": 2, "clock": [{"frameIndex": 0, "hostTime": 9654611985347}], "deviceUIDs": ["BuiltInSpeakerDevice"], "firstSampleHostTime": 9654611985347, "frames": 178688, "gaps": [], "id": "system", "offsetSeconds": 0, "sampleRate": 48000}, {"channels": 1, "clock": [{"frameIndex": 0, "hostTime": 9653242120099}, {"frameIndex": 160085, "hostTime": 9653482246848}, {"frameIndex": 320170, "hostTime": 9653722373589}, {"frameIndex": 480256, "hostTime": 9653962500344}, {"frameIndex": 640341, "hostTime": 9654202627083}, {"frameIndex": 800426, "hostTime": 9654442753809}, {"frameIndex": 960512, "hostTime": 9654682880545}], "deviceUIDs": ["BuiltInMicrophoneDevice"], "effectiveSampleRate": 16000.083889032583, "firstSampleHostTime": 9653242120099, "frames": 972800, "gaps": [], "id": "mic_raw", "offsetSeconds": -57.07771866666666, "sampleRate": 16000}], "wallClock": "2026-10-13T10:27:14Z"}
"""#
