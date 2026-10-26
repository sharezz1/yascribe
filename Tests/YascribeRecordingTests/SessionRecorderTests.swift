import Foundation
import Testing
@testable import YascribeRecording
import YascribeSessionFormat

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
    // T9: 61 s zer cyfrowych na ścieżce systemowej → track.failed, a nie cichy plik.
    // Potem ~40 s bez porcji: nadzór nie może nadpisać przyczyny stalled30s (runda 3, M4).
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let sys = Pump("system")
    let r = SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: clock, timebase: ns)
    try r.start()
    for k in 1...100 {
        clock.set(UInt64(k) * s)
        if k <= 61 { sys.handler?(.chunk(AudioChunk(samples: [Int16](repeating: 0, count: 1_600), hostTime: UInt64(k) * s))) }
        r.tick()
    }
    r.stop()
    let events = try SessionJournal.read(url: SessionDirectory(url: dir).journalURL)
    #expect(!events.contains { $0.type == .trackFailed && $0.reason == "stalled30s" })
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

@Test func tickBeforeStartDoesNothing() {
    // Hermes 2.1: tick przed start nie może zakończyć sesji jako cisza.
    let r = SessionRecorder(directory: sessionDir(), sources: [], conditions: [SilenceCondition(seconds: 1)],
                            clock: ManualHostClock(10 * s), timebase: ns)
    r.tick()
    #expect(r.endReason == nil)
}

@Test func deadTrackIsFlaggedWhileOtherContinues() throws {
    // ChatGPT #9: tap umiera, mikrofon dostarcza dalej — awaria nie może się schować za żywym torem.
    final class Silent: AudioSource, @unchecked Sendable {
        let trackID = "system"
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
        func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {}
        func stop() {}
    }
    final class Pump: AudioSource, @unchecked Sendable {
        let trackID = "mic_raw"
        var handler: (@Sendable (AudioSourceEvent) -> Void)?
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 16_000, channels: 1, deviceUID: "m") }
        func start(_ h: @escaping @Sendable (AudioSourceEvent) -> Void) throws { handler = h }
        func stop() {}
    }
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let mic = Pump()
    let r = SessionRecorder(directory: dir, sources: [Silent(), mic], conditions: [StallCondition(seconds: 30)],
                            clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    let failure = { (id: String) in try SessionDirectory(url: dir).summarize().tracks.first { $0.id == id }?.failure }
    for k in 1...40 {
        clock.set(UInt64(k) * s)
        mic.handler?(.chunk(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: UInt64(k) * s)))
        r.tick()
        // Granica przypięta z obu stron (S4 P4): mutacje progu `* 10` i `/ 10` też dają czerwień.
        if k == 29 { #expect(try failure("system") == nil) }
        if k == 30 { #expect(try failure("system") == "stalled30s") }
    }
    #expect(r.endReason == nil) // mikrofon żyje, sesja trwa
    r.stop()
    #expect(try failure("system") == "stalled30s")
    #expect(try failure("mic_raw") == nil) // żywy tor nie jest oznaczany
}

private final class Pump: AudioSource, @unchecked Sendable {
    let trackID: String
    var handler: (@Sendable (AudioSourceEvent) -> Void)?
    init(_ id: String) { trackID = id }
    func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 16_000, channels: 1, deviceUID: "m") }
    func start(_ h: @escaping @Sendable (AudioSourceEvent) -> Void) throws { handler = h }
    func stop() {}
    func pump(at k: Int) {
        handler?(.chunk(AudioChunk(samples: sine(frames: 1_600, channels: 1, rate: 16_000), hostTime: UInt64(k) * s)))
    }
}

@Test func stalledTrackThatResumesIsNotLeftFailed() throws {
    // S4 P6: tor ożył po stalled30s — podsumowanie nie może go dalej pokazywać jako awarii.
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let sys = Pump("system"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    for k in 1...45 {
        clock.set(UInt64(k) * s)
        mic.pump(at: k)
        if k > 40 { sys.pump(at: k) }
        r.tick()
    }
    r.stop()
    let events = try SessionJournal.read(url: SessionDirectory(url: dir).journalURL)
    #expect(events.contains { $0.type == .trackFailed && $0.trackID == "system" })
    // Dokładnie jedno: tor wychodzi ze stalledTracks, kolejne porcje nie powielają zdarzenia (runda 3, M5).
    #expect(events.filter { $0.type == .trackRecovered && $0.trackID == "system" }.count == 1)
    #expect(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "system" }?.failure == nil)
}

@Test func currentStalledTracksShowsStallUntilItRecovers() throws {
    // Pigułka: „No system audio yet” po 30 s bez klatek, znika po pierwszej porcji.
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let sys = Pump("system"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    for k in 1...29 { clock.set(UInt64(k) * s); mic.pump(at: k); r.tick() }
    #expect(r.currentStalledTracks().isEmpty)
    clock.set(31 * s); mic.pump(at: 31); r.tick()
    #expect(r.currentStalledTracks() == ["system"])
    clock.set(32 * s); sys.pump(at: 32); r.tick()
    #expect(r.currentStalledTracks().isEmpty)
    r.stop()
}

@Test func stallDoesNotOverwriteEarlierFailure() throws {
    // S4 P2: tor, którego start() rzucił, nie dostaje po 30 s drugiego track.failed nadpisującego przyczynę.
    final class Broken: AudioSource, @unchecked Sendable {
        let trackID = "system"
        func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
        func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws { throw AudioSourceError.coreAudio("CreateIOProc", -1) }
        func stop() {}
    }
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [Broken(), mic], conditions: [], clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    for k in 1...40 { clock.set(UInt64(k) * s); mic.pump(at: k); r.tick() }
    r.stop()
    let sys = try #require(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "system" })
    #expect(sys.failure?.contains("CreateIOProc") == true)
}

@Test func failedTrackKeepsItsReasonThroughStallAndResume() throws {
    // Przegląd poprawek U4/U2: .failed ze źródła nie jest nadpisywany przez stalled30s,
    // a późniejsza prawdziwa awaria nie znika z podsumowania, gdy tor znów daje porcje.
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let early = Pump("system"), late = Pump("mic_aec"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [early, late, mic], conditions: [], clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    for k in 1...45 {
        clock.set(UInt64(k) * s)
        if k == 1 { early.handler?(.failed("reopen: A")) }
        if k == 35 { late.handler?(.failed("reopen: B")) } // po stalled30s z k=30
        mic.pump(at: k)
        if k > 40 { late.pump(at: k) }
        r.tick()
    }
    r.stop()
    let events = try SessionJournal.read(url: SessionDirectory(url: dir).journalURL)
    #expect(!events.contains { $0.type == .trackFailed && $0.trackID == "system" && $0.reason == "stalled30s" })
    #expect(!events.contains { $0.type == .trackRecovered && $0.trackID == "mic_aec" })
    #expect(!events.contains { $0.type == .trackRecovered && $0.trackID == "mic_raw" }) // nigdy nie stawał (M3)
    let tracks = try SessionDirectory(url: dir).summarize().tracks
    #expect(tracks.first { $0.id == "system" }?.failure == "reopen: A")
    #expect(tracks.first { $0.id == "mic_aec" }?.failure == "reopen: B")
}

@Test func unsafeTrackIDNeverLeavesSessionDirectory() throws {
    // S4 P12: trackID idzie do nazwy pliku.
    let dir = sessionDir()
    let evil = FileSource(trackID: "../evil", samples: sine(frames: 160, channels: 1, rate: 16_000), sampleRate: 16_000,
                          channels: 1, startHostTime: 0, timebase: ns)
    let r = SessionRecorder(directory: dir, sources: [evil], conditions: [], clock: ManualHostClock(), timebase: ns)
    try r.start()
    #expect(r.endReason == .noSources)
    #expect(!FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("evil.caf").path))
}

@Test func recorderReportsTheLastLevelPerTrack() throws {
    // Poziom to OSTATNIA porcja toru — nie pierwsza i nie maksimum (wskaźnik na pigułce ma opadać z ciszą).
    let dir = sessionDir()
    let loud = sine(frames: 1_600, channels: 1, rate: 16_000, amp: 0.5)
    let quiet = [Int16](repeating: 0, count: 1_600)
    let sys = FileSource(trackID: "system", samples: loud + quiet, sampleRate: 16_000, channels: 1, startHostTime: 0,
                         timebase: ns, chunkFrames: 1_600)
    let mic = FileSource(trackID: "mic_raw", samples: loud, sampleRate: 16_000, channels: 1, startHostTime: 0,
                         timebase: ns, chunkFrames: 1_600)
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(), timebase: ns, zeroWatch: [:])
    try r.start()
    let levels = r.currentLevels()
    #expect(levels["system"] == -160) // ostatnia porcja to cyfrowa cisza
    let m = try #require(levels["mic_raw"])
    #expect(m > -12 && m < -6) // sinus o amplitudzie 0,5 ≈ −9 dBFS RMS
}

@Test func levelsAreKeptPerTrackAndReadableAfterTheEnd() throws {
    let dir = sessionDir()
    let mic = FileSource(trackID: "mic_raw", samples: sine(frames: 1_600, channels: 1, rate: 16_000, amp: 0.5), sampleRate: 16_000,
                         channels: 1, startHostTime: 0, timebase: ns, chunkFrames: 1_600)
    let r = SessionRecorder(directory: dir, sources: [mic], conditions: [], clock: ManualHostClock(), timebase: ns, zeroWatch: [:])
    try r.start()
    #expect(r.endReason != nil) // sesja już zakończona (źródło plikowe)
    #expect(Set(r.currentLevels().keys) == ["mic_raw"]) // tor, którego nie było, nie ma poziomu
}

@Test func silentSecondsCountsFromTheLastLoudChunkWithTheSameThresholdAsSilenceCondition() throws {
    // T10: monitor pyta o koniec po `silenceSeconds` na tym samym progu (−50 dBFS), co bezpiecznik 600 s.
    let dir = sessionDir()
    let clock = ManualHostClock(0)
    let sys = Pump("system")
    let r = SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: clock, timebase: ns, zeroWatch: [:])
    try r.start()
    #expect(r.silentSeconds() == 0)
    clock.set(10 * s)
    sys.pump(at: 10)
    #expect(r.silentSeconds() == 0)
    clock.set(25 * s)
    sys.handler?(.chunk(AudioChunk(samples: [Int16](repeating: 3, count: 1_600), hostTime: 25 * s))) // około −80 dBFS: cisza
    #expect(r.silentSeconds() == 15)
    // Próg −50 dBFS: szum z pasma −60…−50 (tu ≈ −55) nadal jest ciszą, tuż nad progiem (≈ −44) już nie.
    clock.set(40 * s)
    sys.handler?(.chunk(AudioChunk(samples: [Int16](repeating: 58, count: 1_600), hostTime: 40 * s)))
    #expect(r.silentSeconds() == 30)
    clock.set(50 * s)
    sys.handler?(.chunk(AudioChunk(samples: [Int16](repeating: 200, count: 1_600), hostTime: 50 * s)))
    #expect(r.silentSeconds() == 0)
    r.stop()
}

// MARK: Wyciszanie torów (macos.md §11.5) i track.audible

/// Porcja 0,1 s (1 600 ramek przy 16 kHz) z ciągłym czasem hosta — bez luk.
private func feed(_ p: Pump, _ i: Int, zeros: Bool = false) {
    let samples = zeros ? [Int16](repeating: 0, count: 1_600) : sine(frames: 1_600, channels: 1, rate: 16_000)
    p.handler?(.chunk(AudioChunk(samples: samples, hostTime: UInt64(i) * s / 10)))
}

private func mutes(_ dir: URL, _ track: String) throws -> [[Int]]? {
    try SessionDirectory(url: dir).summarize().tracks.first { $0.id == track }?.mutes?.map { [$0.frameIndex, $0.endFrame ?? -1] }
}

@Test func mutedRangeIsDigitalSilenceAndTracksStayAligned() throws {
    let dir = sessionDir()
    let sys = Pump("system"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(0), timebase: ns)
    try r.start()
    for i in 0..<30 {
        if i == 10 { #expect(r.setMuted("mic_raw", true)) }
        if i == 20 { #expect(r.setMuted("mic_raw", false)) }
        feed(sys, i); feed(mic, i)
    }
    r.stop()
    let micSamples = try CAFReader(url: dir.appendingPathComponent("mic_raw.caf")).samples
    // Cisza, nie przerwa: tyle samo ramek co tor systemowy, bez luk.
    #expect(micSamples.count == (try CAFReader(url: dir.appendingPathComponent("system.caf")).frames))
    #expect(micSamples.count == 30 * 1_600)
    #expect(micSamples[16_000..<32_000].allSatisfy { $0 == 0 })
    #expect(micSamples[0..<16_000].contains { $0 != 0 })
    #expect(micSamples[32_000...].contains { $0 != 0 })
    #expect(try SessionDirectory(url: dir).summarize().tracks.allSatisfy { $0.gaps.isEmpty })
    #expect(try mutes(dir, "mic_raw") == [[16_000, 32_000]])
    #expect(try mutes(dir, "system") == nil)
}

@Test func bothTracksCannotBeMutedAtOnce() throws {
    let dir = sessionDir()
    let sys = Pump("system"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(0), timebase: ns)
    try r.start()
    #expect(r.setMuted("system", true))
    #expect(!r.setMuted("mic_raw", true)) // „Nothing is being recorded”
    #expect(r.mutedTracks() == ["system"])
    #expect(r.setMuted("system", false))
    #expect(r.setMuted("mic_raw", true))
    #expect(r.setMuted("mic_raw", true)) // ponowne wyciszenie to nie nowy okres
    r.stop()
    let events = try SessionJournal.read(url: SessionDirectory(url: dir).journalURL)
    #expect(events.filter { $0.type == .trackMuted }.map(\.trackID) == ["system", "mic_raw"])
    #expect(events.filter { $0.type == .trackUnmuted }.map(\.trackID) == ["system"])
    // Wyciszenie trwające przy Stop kończy się na ostatniej ramce toru (tu: 0).
    #expect(try mutes(dir, "mic_raw") == [[0, 0]])

    // Jedyny tor (drugi bez uprawnienia) też nie może zamilknąć.
    let dir2 = sessionDir()
    let lone = Pump("mic_raw")
    let r2 = SessionRecorder(directory: dir2, sources: [DeniedSource("system"), lone], conditions: [], clock: ManualHostClock(0), timebase: ns)
    try r2.start()
    #expect(!r2.setMuted("mic_raw", true))
    r2.stop()
}

@Test func mutedTrackIsSilentForTheSilenceConditionButKeepsItsRealLevel() throws {
    let dir = sessionDir()
    let mic = Pump("mic_raw"), sys = Pump("system")
    let clock = ManualHostClock(0)
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: clock, timebase: ns)
    try r.start()
    #expect(r.setMuted("mic_raw", true))
    for i in 0..<20 { feed(mic, i); feed(sys, i, zeros: true) }
    clock.set(2 * s)
    #expect(r.silentSeconds() >= 2) // wyciszony głos nie podtrzymuje nagrania (decyzja 4)
    #expect((r.currentLevels()["mic_raw"] ?? -160) > -50) // miernik pokazuje, że mówisz (decyzja 3)
    r.stop()
}

@Test func soundAfterAllZerosIsJournaledAsAudible() throws {
    // Decyzja (b) z F15-T13 część B: cisza na początku trwale odróżniona od braku uprawnienia.
    let dir = sessionDir()
    let sys = Pump("system")
    let r = SessionRecorder(directory: dir, sources: [sys], conditions: [], clock: ManualHostClock(0), timebase: ns,
                            zeroWatch: ["system": 1])
    try r.start()
    for i in 0..<15 { feed(sys, i, zeros: true) }
    for i in 15..<20 { feed(sys, i) }
    r.stop()
    let events = try SessionJournal.read(url: SessionDirectory(url: dir).journalURL)
    #expect(events.filter { $0.type == .trackAudible }.count == 1)
    let t = try #require(try SessionDirectory(url: dir).summarize().tracks.first)
    #expect(t.failure == "allZeros1s")
    #expect((24_000...24_001).contains(t.audibleFrame ?? -1)) // pierwsza próbka sinusa to 0
}

@Test func mutedSystemTrackIsNotMistakenForMissingPermission() throws {
    // Wykrywacz zer patrzy na surowy dźwięk: wyciszony, ale działający tor nie dostaje allZeros.
    let dir = sessionDir()
    let sys = Pump("system"), mic = Pump("mic_raw")
    let r = SessionRecorder(directory: dir, sources: [sys, mic], conditions: [], clock: ManualHostClock(0), timebase: ns,
                            zeroWatch: ["system": 1])
    try r.start()
    #expect(r.setMuted("system", true))
    for i in 0..<20 { feed(sys, i); feed(mic, i) }
    r.stop()
    #expect(try SessionDirectory(url: dir).summarize().tracks.first { $0.id == "system" }?.failure == nil)
    #expect(try CAFReader(url: dir.appendingPathComponent("system.caf")).samples.allSatisfy { $0 == 0 })
}
