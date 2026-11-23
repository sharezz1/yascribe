import Foundation
import Testing
@testable import YascribeTranscription

private let anna = UUID()
private func diarization(_ segments: [SpeakerDiarization.Segment] = [.init(speaker: "S1", start: 0, end: 30, trackStart: 0, trackEnd: 30),
                                                                    .init(speaker: "S2", start: 30, end: 60, trackStart: 30, trackEnd: 60)]) -> SpeakerDiarization {
    SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                       audioFingerprint: nil, createdAt: nil, segments: segments)
}
private var matched: SpeakerDiarization {
    diarization().applying([.init(key: "S1", profileID: anna, similarity: 0.9)], names: [anna: "Anna Testowa"], model: "m")
}

@Test func applyingWritesNamesAndMatches() {
    #expect(matched.names == ["S1": "Anna Testowa"])
    #expect(matched.voiceMatches == ["S1": VoiceMatch(profileID: anna, similarity: 0.9, model: "m")])
    // Klucz spoza odcinków i profil bez imienia nic nie wpisują.
    let none = diarization().applying([.init(key: "S9", profileID: anna, similarity: 0.9), .init(key: "S2", profileID: UUID(), similarity: 0.9)],
                                      names: [anna: "Anna Testowa"], model: "m")
    #expect(none.names == nil && none.voiceMatches == nil)
}

@Test func matchingSkipsManualNames() throws {
    let manual = try #require(diarization().renamed("S1", to: "Bob Example"))
    #expect(manual.namedKeys == ["S1"])
    let after = manual.applying([.init(key: "S1", profileID: anna, similarity: 0.99)], names: [anna: "Anna Testowa"], model: "m")
    #expect(after.names == ["S1": "Bob Example"] && after.voiceMatches == nil)
}

@Test func confirmLearnsAndClearsMatch() throws {
    let o = try #require(VoiceNaming.rename(matched, key: "S1", to: "anna testowa"))
    #expect(o.learn && !o.forgetPrevious)
    #expect(o.diarization.voiceMatches == nil && o.diarization.voiceRejected == nil && o.diarization.names == ["S1": "anna testowa"])
}

@Test func rejectRecordsAndClears() throws {
    let o = try #require(VoiceNaming.rename(matched, key: "S1", to: "Bob Example"))
    #expect(o.learn && !o.forgetPrevious)
    #expect(o.diarization.voiceRejected == ["S1": [anna]] && o.diarization.voiceMatches == nil && o.diarization.names == ["S1": "Bob Example"])
}

@Test func useSpeakerNRejects() throws {
    let o = try #require(VoiceNaming.rename(matched, key: "S1", to: nil))
    #expect(!o.learn && !o.forgetPrevious)
    #expect(o.diarization.voiceRejected == ["S1": [anna]] && o.diarization.names == nil)
}

@Test func renameManualForgetsPrevious() throws {
    let manual = try #require(diarization().renamed("S1", to: "Bob Example"))
    let renamed = try #require(VoiceNaming.rename(manual, key: "S1", to: "Anna Testowa"))
    #expect(renamed.learn && renamed.forgetPrevious)
    let cleared = try #require(VoiceNaming.rename(manual, key: "S1", to: nil))
    #expect(!cleared.learn && cleared.forgetPrevious)
    let same = try #require(VoiceNaming.rename(manual, key: "S1", to: "bob example"))
    #expect(same.learn && !same.forgetPrevious)
    let first = try #require(VoiceNaming.rename(diarization(), key: "S1", to: "Bob Example"))
    #expect(first.learn && !first.forgetPrevious)
    #expect(VoiceNaming.rename(diarization(), key: "S9", to: "X") == nil)
}

@Test func noVectorsInSpeakersJSON() throws {
    let text = String(decoding: try JSONEncoder().encode(matched), as: UTF8.self)
    #expect(text.contains("voiceMatches") && !text.contains("values") && !text.contains("vector"))
    let old = try JSONDecoder().decode(SpeakerDiarization.self, from: Data(#"{"version":1,"modelPin":"p","segments":[]}"#.utf8))
    #expect(old.voiceMatches == nil && old.voiceRejected == nil)
}
