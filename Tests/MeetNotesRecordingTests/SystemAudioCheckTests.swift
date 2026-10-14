import Testing
@testable import MeetNotesRecording

@Test func toneAboveThresholdMeansWorking() {
    #expect(SystemAudioCheck.evaluate(levelsDBFS: [-160, -160, -23, -160]) == .works(peakDBFS: -23))
}

@Test func onlyZerosMeansSilent() {
    // Tak wygląda odmowa uprawnienia, jeśli system oddaje zera zamiast błędu.
    #expect(SystemAudioCheck.evaluate(levelsDBFS: [-160, -160, -160]) == .silent(peakDBFS: -160))
}

@Test func noChunksAtAllMeansSilent() {
    #expect(SystemAudioCheck.evaluate(levelsDBFS: []) == .silent(peakDBFS: -160))
}

import Foundation

private final class ThrowingSource: AudioSource, @unchecked Sendable {
    let trackID = "system"
    private let lock = NSLock()
    private var _stops = 0
    var stops: Int { lock.lock(); defer { lock.unlock() }; return _stops }
    func prepare() throws -> TrackFormat { TrackFormat(sampleRate: 48_000, channels: 2, deviceUID: "x") }
    func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws { throw AudioSourceError.deviceUnavailable("boom") }
    func stop() { lock.lock(); _stops += 1; lock.unlock() }
}

@Test func systemAudioCheckStopsTheTapWhenStartThrows() async {
    // S18 §2.2: gdy start rzuci, tap i urządzenie zbiorcze nie mogą zostać w systemie do końca procesu.
    let src = ThrowingSource()
    let r = await SystemAudioCheck.run(tap: src)
    if case .failed = r {} else { Issue.record("oczekiwano .failed, jest \(r)") }
    #expect(src.stops == 1)
}
