import Foundation
import Testing
import YascribeProviders
@testable import YascribeTranscription

private func diarization(_ segments: [(String, Double, Double)], minimum: Double? = 10) -> SpeakerDiarization {
    SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: minimum,
                       audioFingerprint: nil, createdAt: nil, segments: segments.map { .init(speaker: $0.0, start: $0.1, end: $0.2) })
}
private func line(_ start: Double, _ end: Double, _ speaker: Speaker = .them) -> Utterance {
    Utterance(speaker: speaker, start: start, end: end, text: "", words: [], approximateTiming: false, languageMismatch: nil)
}

@Test func speakerStatsSumSecondsPerSpeakerLargestFirst() {
    let d = diarization([("b", 0, 4), ("a", 10, 30), ("b", 40, 46)])
    #expect(d.secondsBySpeaker.map(\.speaker) == ["a", "b"])
    #expect(d.secondsBySpeaker.map(\.seconds) == [20, 10])
}

@Test func speakerStatsCountCrumbsBelowTheMinimumOnly() {
    let d = diarization([("full", 0, 10), ("almost", 20, 29.9), ("crumb", 40, 41)])
    #expect(d.crumbCount == 2)
    #expect(diarization([("s", 0, 10)], minimum: nil).crumbCount == 0)
    #expect(diarization([("s", 0, 10)], minimum: 11).crumbCount == 1)
}

@Test func speakerLabelCountsReportLettersAndUnlabeledThemOnly() {
    let d = diarization([("x", 0, 20), ("y", 30, 50), ("crumb", 100, 103)])
    let t = Transcript(utterances: [line(1, 2), line(31, 32), line(2, 3, .me), line(101, 102), line(200, 201)], failedChunks: [])
    let counts = SpeakerLabelCounts(transcript: t, diarization: d)
    #expect(counts.letters == 2 && counts.them == 4 && counts.unlabeled == 2)
}

@Test func speakerSensitivityParsesNamesAndRejectsAnythingElse() throws {
    #expect(try SpeakerSensitivity.parse(nil) == .medium)
    #expect(try SpeakerSensitivity.parse("low") == .low)
    #expect(try SpeakerSensitivity.parse("high") == .high)
    for bad in ["Medium", "", "max", "0.3"] {
        #expect(throws: SpeakerSensitivityError(value: bad)) { try SpeakerSensitivity.parse(bad) }
    }
}
