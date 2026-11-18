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
    #expect(labels([line(7, 15), line(5, 10)], segments) == ["Speaker 2", "Speaker 1"])
}
@Test func speakerLabelsUseNearestWithinOneSecond() {
    #expect(labels([line(11, 12), line(11.01, 12)], [seg("s", 0, 10)]) == ["Speaker 1", nil])
}
@Test func speakerLabelsExcludeCrumbsButKeepTenSeconds() {
    #expect(labels([line(0, 9), line(20, 30)], [seg("crumb", 0, 9.9), seg("full", 20, 30)]) == [nil, "Speaker 1"])
}
@Test func speakerLabelsFollowUtteranceOrderNotSegmentOrderOrSpeechDuration() {
    let segments = [seg("B", 0, 12), seg("A", 20, 50)]
    #expect(labels([line(21, 22), line(1, 2), line(25, 26)], segments) == ["Speaker 2", "Speaker 1", "Speaker 2"])
    #expect(labels([line(21, 22), line(40, 41)], [seg("B", 0, 10), seg("A", 20, 30), seg("B", 40, 60)]) == ["Speaker 1", "Speaker 2"])
}
@Test func speakerLabelsLeaveMeAndMissingDiarizationUnlabeled() {
    let lines = [line(0, 3, .me), line(0, 3)]
    #expect(labels(lines, [seg("s", 0, 10)]) == [nil, "Speaker 1"])
    #expect(SpeakerLabels.labels(for: Transcript(utterances: lines, failedChunks: []), diarization: nil) == [nil, nil])
}
@Test func speakerLabelsUseNumbersAfterZ() {
    let segments = (0..<28).map { seg("s\($0)", Double($0 * 20), Double($0 * 20 + 10)) }
    let lines = (0..<28).map { line(Double($0 * 20), Double($0 * 20 + 1)) }
    let result = labels(lines, segments)
    #expect(result[25] == "Speaker 26" && result[26] == "Speaker 27" && result[27] == "Speaker 28")
}

@Test func speakerLabelsNamesAndKeysRemainIndependent() throws {
    let d = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil,
        minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil, segments: [seg("a", 0, 10), seg("b", 20, 30)])
    let named = try #require(d.renamed("a", to: " Ala ")?.renamed("b", to: "Ala"))
    let changed = try #require(named.renamed("a", to: "Ola"))
    let result = Transcript(utterances: [line(1, 2), line(21, 22)], failedChunks: []).withSpeakerLabels(changed)
    #expect(result.utterances.map(\.speakerKey) == ["a", "b"])
    #expect(result.utterances.map(\.speakerLabel) == ["Ola", "Ala"])
    #expect(changed.renamed("unknown", to: "X") == nil)
    #expect(changed.renamed("a", to: "  \n")?.names?["a"] == nil)
    #expect(changed.renamed("b", to: nil)?.names?["b"] == nil)
    let cleared = try #require(changed.renamed("a", to: " "))
    #expect(Transcript(utterances: [line(1, 2)], failedChunks: []).withSpeakerLabels(cleared).utterances[0].speakerLabel == "Speaker 1")
    #expect(Transcript(utterances: [line(1, 2)], failedChunks: []).withSpeakerLabels(nil).utterances[0].speakerKey == nil)
}

@Test func speakerLabelsOldSpeakersFileDecodesWithoutNames() throws {
    let json = #"{"version":1,"modelPin":"p","segments":[]}"#
    let d = try JSONDecoder().decode(SpeakerDiarization.self, from: Data(json.utf8))
    #expect(d.names == nil)
}

@Test func speakerNumbersFollowFirstUtterance() {
    var lines = [line(9, 10), line(5, 6), line(1, 2, .me)]
    lines[0].speakerKey = "a"
    lines[1].speakerKey = "b"
    #expect(SpeakerLabels.numbers(for: Transcript(utterances: lines, failedChunks: [])) == ["b": 1, "a": 2])
}

@Test func segmentsDigestIgnoresNamesButNotSegments() {
    var d = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                               audioFingerprint: nil, createdAt: nil, segments: [seg("speaker_0", 0, 10)])
    let before = d.segmentsDigest
    d.names = ["speaker_0": "Ala"]
    #expect(d.segmentsDigest == before)
    d.segments = [seg("speaker_0", 0, 11)]
    #expect(d.segmentsDigest != before)
}
