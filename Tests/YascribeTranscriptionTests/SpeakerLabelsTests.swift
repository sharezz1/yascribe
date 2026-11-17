import Foundation
import Testing
@testable import YascribeTranscription

private func line(_ start: Double, _ end: Double, _ speaker: Speaker = .them) -> Utterance {
    Utterance(speaker: speaker, start: start, end: end, text: "", words: [], approximateTiming: false, languageMismatch: nil)
}
private func labels(_ lines: [Utterance], _ segments: [SpeakerDiarization.Segment], minimum: Double? = nil) -> [String?] {
    let d = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil,
                               minClusterSeconds: minimum, audioFingerprint: nil, createdAt: nil, segments: segments)
    return SpeakerLabels.labels(for: Transcript(utterances: lines, failedChunks: []), diarization: d)
}
private func seg(_ speaker: String, _ start: Double, _ end: Double) -> SpeakerDiarization.Segment {
    .init(speaker: speaker, start: start, end: end)
}

@Test func speakerLabelsChooseMostOverlapAndEarlierSpeakerOnTie() {
    let segments = [seg("later", 5, 20), seg("earlier", 0, 10)]
    #expect(labels([line(7, 15), line(5, 10)], segments) == ["B", "A"])
}
@Test func speakerLabelsUseNearestWithinOneSecond() {
    #expect(labels([line(11, 12), line(11.01, 12)], [seg("s", 0, 10)]) == ["A", nil])
}
@Test func speakerLabelsExcludeCrumbsButKeepTenSeconds() {
    #expect(labels([line(0, 9), line(20, 30)], [seg("crumb", 0, 9.9), seg("full", 20, 30)]) == [nil, "A"])
}
@Test func speakerLabelsFollowUtteranceOrderNotSegmentOrderOrSpeechDuration() {
    let segments = [seg("B", 0, 12), seg("A", 20, 50)]
    #expect(labels([line(21, 22), line(1, 2), line(25, 26)], segments) == ["B", "A", "B"])
    #expect(labels([line(21, 22), line(40, 41)], [seg("B", 0, 10), seg("A", 20, 30), seg("B", 40, 60)]) == ["A", "B"])
}
@Test func speakerLabelsLeaveMeAndMissingDiarizationUnlabeled() {
    let lines = [line(0, 3, .me), line(0, 3)]
    #expect(labels(lines, [seg("s", 0, 10)]) == [nil, "A"])
    #expect(SpeakerLabels.labels(for: Transcript(utterances: lines, failedChunks: []), diarization: nil) == [nil, nil])
}
@Test func speakerLabelsUseNumbersAfterZ() {
    let segments = (0..<28).map { seg("s\($0)", Double($0 * 20), Double($0 * 20 + 10)) }
    let lines = (0..<28).map { line(Double($0 * 20), Double($0 * 20 + 1)) }
    let result = labels(lines, segments)
    #expect(result[25] == "Z" && result[26] == "27" && result[27] == "28")
}
