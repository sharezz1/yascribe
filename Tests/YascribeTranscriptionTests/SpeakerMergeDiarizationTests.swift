import Foundation
import Testing
@testable import YascribeTranscription

private func seg(_ speaker: String, _ start: Double, _ end: Double) -> SpeakerDiarization.Segment {
    .init(speaker: speaker, start: start, end: end, trackStart: start, trackEnd: end)
}

private func make(_ segments: [SpeakerDiarization.Segment], names: [String: String]? = nil) -> SpeakerDiarization {
    var d = SpeakerDiarization(version: 1, modelPin: "pin", sensitivity: .medium, fa: nil, fb: nil, threshold: nil,
                               minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil, segments: segments)
    d.names = names
    return d
}

private let base = make([seg("A", 0, 10), seg("B", 10, 15), seg("C", 15, 30), seg("A", 30, 40), seg("B", 40, 42)])

@Test func mergeRewritesSegmentsAndKeepsTargetName() {
    let d = make(base.segments, names: ["A": "Anna Testowa", "B": "Bob Example"]).merging(["B": "A"], auto: false)
    #expect(d.segments.map(\.speaker) == ["A", "A", "C", "A", "A"])
    #expect(d.segments.map(\.originalSpeaker) == [nil, "B", nil, nil, "B"])
    #expect(d.names == ["A": "Anna Testowa"])
    #expect(d.merges == ["B": .init(into: "A", auto: false, name: "Bob Example")])
}

@Test func mergeIntoUnnamedKeepsName() {
    let d = make(base.segments, names: ["B": "Bob Example"]).merging(["B": "A"], auto: false)
    #expect(d.names == ["A": "Bob Example"])
}

@Test func mergeDropsSourceVoiceState() {
    var d = make(base.segments, names: ["A": "Anna Testowa", "B": "Bob Example"])
    let p1 = UUID(), p2 = UUID()
    d.voiceMatches = ["A": .init(profileID: p1, similarity: 0.9, model: "m"), "B": .init(profileID: p2, similarity: 0.8, model: "m")]
    d.voiceRejected = ["A": [p2], "B": [p1]]
    let m = d.merging(["B": "A"], auto: true)
    #expect(m.voiceMatches == ["A": .init(profileID: p1, similarity: 0.9, model: "m")])
    #expect(m.voiceRejected == ["A": [p2]])
    let split = m.splitting(original: "B")
    // Imię wraca do przywróconej grupy (ręczne imię nie ginie), dopasowanie nie.
    #expect(split?.names == ["A": "Anna Testowa", "B": "Bob Example"] && split?.voiceMatches?["B"] == nil)
}

@Test func cascadeSplitRestoresOnlyOriginal() throws {
    let d = base.merging(["B": "A"], auto: true).merging(["A": "C"], auto: false)
    #expect(Set(d.segments.map(\.speaker)) == ["C"])
    #expect(d.merges == ["B": .init(into: "C", auto: true), "A": .init(into: "C", auto: false)])
    let split = try #require(d.splitting(original: "A"))
    #expect(split.segments.map(\.speaker) == ["A", "C", "C", "A", "C"])
    #expect(split.merges == ["B": .init(into: "C", auto: true)])
    let all = try #require(split.splitting(original: "B"))
    #expect(all.segments == base.segments && all.merges == nil)
}

@Test func splitUnknownReturnsNil() {
    #expect(base.splitting(original: "A") == nil)
}

@Test func mergeIgnoresStaleAndSelf() {
    #expect(base.merging(["X": "A", "A": "A", "B": "Y"], auto: true) == base)
}

@Test func digestStableUnderMerge() throws {
    let merged = base.merging(["B": "A", "C": "A"], auto: true)
    #expect(merged.segmentsDigest == base.segmentsDigest)
    #expect(try #require(merged.splitting(original: "C")).segmentsDigest == base.segmentsDigest)
}

@Test func currentKeyFollowsMerge() {
    let d = base.merging(["B": "A"], auto: true).merging(["A": "C"], auto: true)
    #expect(d.currentKey("B") == "C" && d.currentKey("A") == "C" && d.currentKey("C") == "C" && d.currentKey("Z") == "Z")
}

@Test func mergedOriginalsSumsSeconds() {
    let d = base.merging(["B": "A"], auto: true).merging(["C": "A"], auto: false)
    let list = d.mergedOriginals(into: "A")
    #expect(list.map { $0.key } == ["B", "C"] && list.map { $0.seconds } == [7, 15] && list.map { $0.auto } == [true, false])
}

@Test func oldFileWithoutFieldsDecodes() throws {
    let json = #"{"version":1,"modelPin":"pin","segments":[{"speaker":"A","start":0,"end":1}]}"#
    let d = try JSONDecoder().decode(SpeakerDiarization.self, from: Data(json.utf8))
    #expect(d.merges == nil && d.segments[0].originalSpeaker == nil)
    let out = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
    #expect(!out.contains("merges") && !out.contains("originalSpeaker"))
}

@Test func splitDropsMovedNameButKeepsLaterRename() throws {
    var d = make(base.segments, names: ["B": "Bob Example"])
    d.voiceMatches = ["B": .init(profileID: UUID(), similarity: 0.9, model: "m")]
    let merged = d.merging(["B": "A"], auto: false)
    #expect(merged.names == ["A": "Bob Example"] && merged.voiceMatches == nil)
    #expect(merged.merges?["B"] == .init(into: "A", auto: false, name: "Bob Example", moved: true))
    let split = try #require(merged.splitting(original: "B"))
    #expect(split.names == ["B": "Bob Example"])
    // Użytkownik nadał celowi inne imię po złączeniu: „Rozdziel” go nie zdejmuje.
    let renamed = try #require(merged.renamed("A", to: "Anna Testowa")?.splitting(original: "B"))
    #expect(renamed.names == ["A": "Anna Testowa", "B": "Bob Example"])
}

@Test func cascadeNameStaysWithItsOwner() throws {
    // B („Bob”) → A (bez imienia), potem A → C: imię należy do B, nie do A.
    for cName in [nil, "Carol Example"] as [String?] {
        var start = make(base.segments, names: ["B": "Bob Example"])
        if let cName { start.names?["C"] = cName }
        let d = start.merging(["B": "A"], auto: false).merging(["A": "C"], auto: false)
        #expect(d.names?["C"] == (cName ?? "Bob Example"))
        for order in [["A", "B"], ["B", "A"]] {
            var s = d
            for key in order { s = try #require(s.splitting(original: key)) }
            #expect(s.names?["A"] == nil && s.names?["B"] == "Bob Example" && s.names?["C"] == cName, "\(cName ?? "-") \(order)")
        }
    }
}
