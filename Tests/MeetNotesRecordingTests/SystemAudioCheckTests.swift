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
