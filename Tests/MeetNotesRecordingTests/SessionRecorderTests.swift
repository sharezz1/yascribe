import Foundation
import Testing
@testable import MeetNotesRecording
import MeetNotesSessionFormat

private let ns = Timebase(numer: 1, denom: 1)
private let s: UInt64 = 1_000_000_000

private func sessionDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mn-session-\(UUID().uuidString)")
}

private final class DeniedSource: AudioSource, @unchecked Sendable {
    let trackID: String
    init(_ id: String) { trackID = id }
    func prepare() throws -> TrackFormat { throw AudioSourceError.permissionDenied("systemAudio") }
    func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
    func stop() {}
}

@Test func twoSourcesProduceTwoFilesAndAClosedSession() throws {
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 48_000, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 0, timebase: ns)
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 16_000, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 165_000_000, timebase: ns)
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .endOfInput)
    let sum = try SessionDirectory(url: dir).summarize()
    #expect(!sum.crashed)
    #expect(sum.endReason == "endOfInput")
    #expect(Set(sum.tracks.map(\.id)) == ["system", "mic_raw"])
    #expect(try CAFReader(url: dir.appendingPathComponent("system.caf")).frames == 48_000)
    #expect(try CAFReader(url: dir.appendingPathComponent("mic_raw.caf")).frames == 16_000)
}

@Test func startOffsetIsMeasuredNotAssumed() throws {
    // T2: sztuczne 500 ms opóźnienia mikrofonu ma się pojawić w podsumowaniu.
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 4_800, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 1 * s, timebase: ns)
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 1_600, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 1 * s + 500_000_000, timebase: ns)
    try SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let mic2 = try #require(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "mic_raw" })
    #expect(abs((mic2.offsetSeconds ?? 0) - 0.5) < 1e-6)
}

@Test func silenceEndsTheSession() throws {
    // T5: 30 s mowy, potem 120 s ciszy cyfrowej; warunek 60 s ciszy.
    let dir = sessionDir()
    let speech = sine(frames: 30 * 16_000, channels: 1, rate: 16_000)
    let silence = [Int16](repeating: 0, count: 120 * 16_000)
    let mic = FileSource(trackID: "mic_raw", samples: speech + silence, sampleRate: 16_000, channels: 1,
                         startHostTime: 0, timebase: ns, chunkFrames: 1_600)
    let r = SessionRecorder(directory: dir, sources: [mic], conditions: [SilenceCondition(seconds: 60)],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .silence)
    let frames = try CAFReader(url: dir.appendingPathComponent("mic_raw.caf")).frames
    #expect(frames < (30 + 120) * 16_000) // nie dociągnęła do końca pliku
    #expect(frames >= (30 + 60) * 16_000)
}

@Test func deniedPermissionIsJournaledAndSessionContinues() throws {
    // T9 (część, która nie zależy od sondy): odmowa w prepare() jest jawna.
    let dir = sessionDir()
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 1_600, channels: 1, rate: 16_000), sampleRate: 16_000,
                         channels: 1, startHostTime: 0, timebase: ns)
    let r = SessionRecorder(directory: dir, sources: [DeniedSource("system"), mic], conditions: [],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    let sum = try SessionDirectory(url: dir).summarize()
    #expect(sum.tracks.first { $0.id == "system" }?.permissionDenied == "systemAudio")
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("system.caf").path))
    #expect(r.endReason == .endOfInput)
}

@Test func noUsableSourceEndsImmediately() throws {
    let dir = sessionDir()
    let r = SessionRecorder(directory: dir, sources: [DeniedSource("system")], conditions: [],
                            clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .noSources)
    #expect(try SessionDirectory(url: dir).summarize().endReason == "noSources")
}

@Test func stallIsDetectedByTick() throws {
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    final class Silent: AudioSource, @unchecked Sendable {
        let trackID = "system"
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
        func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
        func stop() {}
    }
    let r = SessionRecorder(directory: dir, sources: [Silent()], conditions: [StallCondition(seconds: 30)],
                            clock: clock, timebase: ns)
    try r.start()
    clock.set(29 * s); r.tick()
    #expect(r.endReason == nil)
    clock.set(31 * s); r.tick()
    #expect(r.endReason == .sourceStalled)
}

@Test func deviceSwitchGapIsFilledAndJournaled() throws {
    // T6: skok 0,5 s w środku strumienia (przepięcie słuchawek).
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: sine(frames: 96_000, channels: 2), sampleRate: 48_000, channels: 2,
                         startHostTime: 0, timebase: ns, jumps: [48_128: 0.5])
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let t = try #require(try SessionDirectory(url: dir).summarize().tracks.first)
    #expect(t.gaps.count == 1)
    #expect(t.gaps[0].frames == 24_000)
    #expect(try CAFReader(url: dir.appendingPathComponent("system.caf")).frames == 96_000 + 24_000)
}

@Test func existingSessionDirectoryIsNeverOverwritten() throws {
    let dir = sessionDir()
    let mk = { FileSource(trackID: "mic_raw", samples: sine(frames: 160, channels: 1, rate: 16_000), sampleRate: 16_000,
                          channels: 1, startHostTime: 0, timebase: ns) }
    try SessionRecorder(directory: dir, sources: [mk()], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    #expect(throws: JournalError.self) {
        try SessionRecorder(directory: dir, sources: [mk()], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    }
}

@Test func diskFullIsRecognized() {
    #expect(SessionRecorder.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
    #expect(SessionRecorder.isDiskFull(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)))
    #expect(!SessionRecorder.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
}

@Test func systemTrackOfPureZerosIsFlagged() throws {
    // T9: 70 s zer cyfrowych na ścieżce systemowej → track.failed, a nie cichy plik.
    let dir = sessionDir()
    let sys = FileSource(trackID: "system", samples: [Int16](repeating: 0, count: 70 * 8_000), sampleRate: 8_000,
                         channels: 1, startHostTime: 0, timebase: ns, chunkFrames: 800)
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    let t = try #require(try SessionDirectory(url: dir).summarize().tracks.first)
    #expect(t.failure == "allZeros60s")
}

@Test func quietStartFollowedBySoundIsNotFlagged() throws {
    let dir = sessionDir()
    let samples = [Int16](repeating: 0, count: 30 * 8_000) + sine(frames: 8_000, channels: 1, rate: 8_000)
        + [Int16](repeating: 0, count: 60 * 8_000)
    let sys = FileSource(trackID: "system", samples: samples, sampleRate: 8_000, channels: 1,
                         startHostTime: 0, timebase: ns, chunkFrames: 800)
    try SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(), timebase: ns).start()
    #expect(try SessionDirectory(url: dir).summarize().tracks.first?.failure == nil)
}
