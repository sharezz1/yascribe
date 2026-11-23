import Foundation
import Testing
@testable import YascribeTranscription

private let model = "diarizer/test"
private let date = Date(timeIntervalSince1970: 0)

/// Wektor jednostkowy o zadanym cosinusie do osi x (w płaszczyźnie x–`axis`).
private func at(_ cos: Double, axis: Int = 1) -> [Float] {
    var v: [Float] = [Float(cos), 0, 0, 0]
    v[axis] = Float((1 - cos * cos).squareRoot())
    return v
}
private func profile(_ name: String, _ vector: [Float], model: String = model) -> VoiceProfile {
    VoiceProfile(name: name, updatedAt: date, samples: [VoiceSample(id: name, model: model, values: vector, seconds: 30)])
}
private func speaker(_ key: String = "S1", _ vector: [Float] = [1, 0, 0, 0], seconds: Double = 30) -> VoiceMatcher.Speaker {
    .init(key: key, vector: vector, seconds: seconds)
}
private func match(_ speakers: [VoiceMatcher.Speaker], _ profiles: [VoiceProfile], model m: String = model,
                   rejected: [String: [UUID]] = [:], skip: Set<String> = []) -> [VoiceMatcher.Match] {
    VoiceMatcher.match(speakers: speakers, profiles: profiles, model: m, rejected: rejected, skip: skip)
}

@Test func matchesAboveThreshold() {
    let anna = profile("Anna Testowa", at(0.705)) // tuż nad progiem 0,70 (Float nie trafia dokładnie w 0,70)
    let result = match([speaker()], [anna])
    #expect(result.map(\.profileID) == [anna.id])
    #expect(abs((result.first?.similarity ?? 0) - 0.705) < 0.001)
}

@Test func belowThresholdNoMatch() {
    #expect(match([speaker()], [profile("Anna Testowa", at(0.695))]).isEmpty)
}

@Test func marginBlocksTie() {
    #expect(match([speaker()], [profile("Anna Testowa", at(0.82)), profile("Bob Example", at(0.79, axis: 2))]).isEmpty)
    let anna = profile("Anna Testowa", at(0.90))
    #expect(match([speaker()], [anna, profile("Bob Example", at(0.80, axis: 2))]).map(\.profileID) == [anna.id])
}

@Test func shortSpeakerSkipped() {
    let anna = profile("Anna Testowa", at(0.95))
    #expect(match([speaker(seconds: 19.9)], [anna]).isEmpty)
    #expect(match([speaker(seconds: 20)], [anna]).count == 1)
}

@Test func otherModelIgnored() {
    #expect(match([speaker()], [profile("Anna Testowa", at(0.95), model: "diarizer/old")]).isEmpty)
}

@Test func oneProfileOneSpeaker() {
    let anna = profile("Anna Testowa", at(0.95))
    let result = match([speaker("S1", at(0.95)), speaker("S2", [1, 0, 0, 0])], [anna])
    #expect(result.map(\.key) == ["S1"] && result.map(\.profileID) == [anna.id]) // S1: cos 1,0; S2: 0,95 zostaje bez imienia
}

@Test func rejectedProfileSkipped() {
    let anna = profile("Anna Testowa", at(0.95))
    #expect(match([speaker()], [anna], rejected: ["S1": [anna.id]]).isEmpty)
    #expect(match([speaker()], [anna], rejected: ["S2": [anna.id]]).count == 1)
}

@Test func manualNameSkipped() {
    #expect(match([speaker()], [profile("Anna Testowa", at(0.95))], skip: ["S1"]).isEmpty)
}

@Test func campPlusNeverMatches() {
    let m = "campplus-v2@rev/fluidaudio"
    #expect(VoiceMatcher.threshold(model: m) == nil)
    #expect(match([speaker()], [profile("Anna Testowa", [1, 0, 0, 0], model: m)], model: m).isEmpty)
}
