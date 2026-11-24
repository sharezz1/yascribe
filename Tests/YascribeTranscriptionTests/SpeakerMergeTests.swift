import Foundation
import Testing
@testable import YascribeTranscription

/// Wektor o zadanym cosinusie względem [1, 0].
private func v(_ cos: Double) -> [Float] { [Float(cos), Float((1 - cos * cos).squareRoot())] }
private func g(_ key: String, _ vector: [Float], _ seconds: Double = 60, name: String? = nil) -> SpeakerMerge.Group {
    SpeakerMerge.Group(key: key, vector: vector, seconds: seconds, name: name)
}

@Test func mergesSameVoiceIntoLonger() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.95), 40)], expected: nil) == ["b": "a"])
}

@Test func keepsDifferentVoices() {
    #expect(SpeakerMerge.plan([g("a", v(1)), g("b", v(0.5))], expected: nil) == [:])
}

@Test func neverMergesTwoNames() {
    #expect(SpeakerMerge.plan([g("a", v(1), name: "Anna Testowa"), g("b", v(0.99), name: "Bob Example")], expected: nil) == [:])
}

@Test func namedGroupIsTarget() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.95), 40, name: "Anna Testowa")], expected: nil) == ["a": "b"])
}

@Test func smallJoinsNearestAboveSmallThreshold() {
    let big = [g("a", [1, 0, 0], 100), g("b", [0, 0, 1], 100)]
    #expect(SpeakerMerge.plan(big + [g("s", v(0.70) + [0], 2)], expected: nil) == ["s": "a"])
    #expect(SpeakerMerge.plan(big + [g("s", v(0.60) + [0], 2)], expected: nil) == [:])
}

@Test func hintRelaxesThreshold() {
    let groups = [g("a", v(1), 100), g("b", v(0.67), 50)]
    #expect(SpeakerMerge.plan(groups, expected: 1) == ["b": "a"])
    #expect(SpeakerMerge.plan(groups, expected: nil) == [:])
    #expect(SpeakerMerge.plan(groups, expected: 2) == [:])
}

@Test func hintNeverForcesBelowFloor() {
    let groups = [g("a", [1, 0, 0]), g("b", [0.5, 0.866, 0]), g("c", [0.5, 0, 0.866])]
    #expect(SpeakerMerge.plan(groups, expected: 2) == [:])
}

@Test func chainsCollapseToFinalTarget() {
    // b łączy się z a; c jest blisko b, ale dopiero średnia a+b przekracza próg… tu wystarczy, że oba wskazują a.
    let plan = SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.9), 50), g("c", v(0.8), 30)], expected: nil)
    #expect(plan == ["b": "a", "c": "a"])
}

@Test func thresholdsAreInclusive() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.705), 50)], expected: nil) == ["b": "a"])
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.695), 50)], expected: nil) == [:])
}

@Test func customThresholdForDryRun() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.75), 50)], expected: nil, mergeThreshold: 0.80) == [:])
}

@Test func smallNeverJoinsDifferentName() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100, name: "Anna Testowa"), g("s", v(0.99), 2, name: "Bob Example")], expected: nil) == [:])
}

@Test func smallUsesLowerThreshold() {
    #expect(SpeakerMerge.plan([g("a", [1, 0, 0], 100), g("b", [0, 0, 1], 100), g("s", v(0.67) + [0], 2)], expected: nil) == ["s": "a"])
}

@Test func hintFloorHoldsForLowThreshold() {
    #expect(SpeakerMerge.plan([g("a", v(1), 100), g("b", v(0.63), 50)], expected: 1, mergeThreshold: 0.66) == [:])
}

@Test func namedGroupIsTargetEitherSide() {
    #expect(SpeakerMerge.plan([g("a", v(1), 40, name: "Anna Testowa"), g("b", v(0.95), 100)], expected: nil) == ["b": "a"])
}

private func timed(_ speaker: String, _ a: Double, _ b: Double) -> SpeakerDiarization.Segment {
    .init(speaker: speaker, start: a, end: b, trackStart: a, trackEnd: b)
}
private let three = SpeakerDiarization(version: 1, modelPin: "pin", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                                       audioFingerprint: nil, createdAt: nil,
                                       segments: [timed("S1", 0, 30), timed("S2", 30, 50), timed("S3", 50, 80)])

@Test func applyMergesSameVoices() async throws {
    let d = try await SpeakerMerge.apply(three, expected: nil) { spans in
        #expect(Set(spans.keys) == ["S1", "S2", "S3"])
        return ["S1": [1, 0], "S2": [0.99, 0.14], "S3": [0, 1]]
    }
    #expect(Set(d.segments.map(\.speaker)) == ["S1", "S3"] && d.merges == ["S2": .init(into: "S1", auto: true)])
}

@Test func applySkipsSingleGroupAndUntimed() async throws {
    var one = three; one.segments = [timed("S1", 0, 30)]
    let same = try await SpeakerMerge.apply(one, expected: nil) { _ in Issue.record("no embed for one group"); return [:] }
    #expect(same == one)
    var untimed = three; untimed.segments = three.segments.map { var s = $0; s.trackStart = nil; s.trackEnd = nil; return s }
    #expect(try await SpeakerMerge.apply(untimed, expected: nil) { _ in Issue.record("no embed"); return [:] } == untimed)
}

@Test func expectedFromAttendees() {
    #expect(SpeakerMerge.expected(attendees: 3) == 2 && SpeakerMerge.expected(attendees: 1) == nil && SpeakerMerge.expected(attendees: 0) == nil)
}
