import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

private func temporarySession() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func sampleDiarization() -> SpeakerDiarization {
    SpeakerDiarization(version: 1, modelPin: "pin", sensitivity: .medium, fa: 0.15, fb: 0.4, threshold: 0.6,
                       minClusterSeconds: 10, audioFingerprint: "fingerprint", createdAt: Date(timeIntervalSince1970: 100),
                       segments: [.init(speaker: "s", start: 1, end: 12)])
}
@Test func speakerDiarizationLoadsOnlyMatchingVersionPinAndFingerprint() throws {
    let session = try temporarySession(); defer { try? FileManager.default.removeItem(at: session) }
    let run = RunDirectory(session: session, runID: "r")
    #expect(run.speakers == session.appendingPathComponent("runs/r/speakers.json"))
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: nil) == nil)
    let sample = sampleDiarization()
    try JSONFile.save(sample, to: run.speakers)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: "fingerprint") == sample)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: nil) == sample)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["other"], currentAudioFingerprint: nil) == nil)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: "other") == nil)
    var future = sample; future.version = 2
    try JSONFile.save(future, to: run.speakers)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: nil) == nil)
    try Data("broken".utf8).write(to: run.speakers)
    #expect(SpeakerDiarization.load(run: run, acceptedPins: ["pin"], currentAudioFingerprint: nil) == nil)
}
@Test func speakerDiarizationDecodesWithoutOptionalFields() throws {
    let d = try JSONDecoder().decode(SpeakerDiarization.self, from: Data(#"{"version":1,"modelPin":"p","segments":[]}"#.utf8))
    #expect(d.sensitivity == nil && d.fa == nil && d.fb == nil && d.threshold == nil && d.minClusterSeconds == nil && d.audioFingerprint == nil && d.createdAt == nil)
}
@Test func speakerDiarizationConvertsBothTrackEndpointsUsingClockDrift() throws {
    let anchors = try JSONDecoder().decode([SessionSummary.ClockAnchor].self, from: Data(#"[{"frameIndex":0,"hostTime":1200000000},{"frameIndex":1600000,"hostTime":101300000000}]"#.utf8))
    let gaps = try JSONDecoder().decode([SessionSummary.Gap].self, from: Data(#"[{"frameIndex":400000,"frames":16000}]"#.utf8))
    let summary = SessionSummary(startedHostTime: 0, timebase: Timebase(numer: 1, denom: 1), tracks: [
        .init(id: "system", sampleRate: 16000, channels: 1, firstSampleHostTime: 1000000000),
        .init(id: "mic_raw", sampleRate: 16000, channels: 1, firstSampleHostTime: 1200000000, offsetSeconds: 0.2, gaps: gaps, clock: anchors)])
    let d = SpeakerDiarization.fromTrack(segments: [("s", 50, 80)], clock: SessionClock(summary: summary), track: "mic_raw", modelPin: "p", sensitivity: .high, audioFingerprint: nil, createdAt: Date())
    #expect(abs(d.segments[0].start - 50.25) < 0.001)
    #expect(abs(d.segments[0].end - 80.28) < 0.001)
    #expect(d.fa == 0.3 && d.fb == 0.8 && d.threshold == 0.6 && d.minClusterSeconds == 10)
}
@Test func speakerAudioFingerprintTracksJournalAndSizeButNotModificationTime() throws {
    let session = try temporarySession(); defer { try? FileManager.default.removeItem(at: session) }
    let journal = session.appendingPathComponent("journal.jsonl"), audio = session.appendingPathComponent("system.caf")
    try Data("journal".utf8).write(to: journal)
    #expect(SpeakerDiarization.audioFingerprint(session: session) == nil)
    try Data([1, 2]).write(to: audio)
    let original = try #require(SpeakerDiarization.audioFingerprint(session: session))
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: audio.path)
    #expect(SpeakerDiarization.audioFingerprint(session: session) == original)
    try Data("changed".utf8).write(to: journal)
    let changed = try #require(SpeakerDiarization.audioFingerprint(session: session))
    #expect(changed != original)
    try Data([1, 2, 3]).write(to: audio)
    #expect(SpeakerDiarization.audioFingerprint(session: session) != changed)
}
@Test func fromTrackKeepsTrackTimes() throws {
    let summary = SessionSummary(startedHostTime: 0, timebase: Timebase(numer: 1, denom: 1), tracks: [])
    let d = SpeakerDiarization.fromTrack(segments: [("S1", 2, 5)], clock: SessionClock(summary: summary), modelPin: "p", sensitivity: nil,
                                         audioFingerprint: nil, createdAt: Date())
    #expect(d.segments[0].trackStart == 2 && d.segments[0].trackEnd == 5)
    let old = try JSONDecoder().decode(SpeakerDiarization.self, from: Data(#"{"version":1,"modelPin":"p","segments":[{"speaker":"s","start":1,"end":2}]}"#.utf8))
    #expect(old.segments[0].trackStart == nil && old.segments[0].trackEnd == nil)
    var moved = d; moved.segments[0].trackStart = 9
    #expect(moved.segmentsDigest == d.segmentsDigest) // czas toru nie zmienia tożsamości wykrycia
}
