import Foundation
import Testing
@testable import YascribeTranscription

private let date = Date(timeIntervalSince1970: 0)
private func sample(_ id: String, _ values: [Float] = [1, 0], seconds: Double = 30, model: String = "m") -> VoiceSample {
    VoiceSample(id: id, model: model, values: values, seconds: seconds)
}

@Test func learnCreatesThenUpdatesByName() {
    var p = VoiceProfiles()
    let first = p.learn(name: "Anna Testowa", sample: sample("a"), now: date)
    let second = p.learn(name: " anna testowa ", sample: sample("b"), now: date.addingTimeInterval(5))
    #expect(first == second && p.profiles.count == 1)
    #expect(p.profiles[0].samples.map(\.id) == ["a", "b"] && p.profiles[0].updatedAt == date.addingTimeInterval(5))
    p.learn(name: "Bob Example", sample: sample("c"), now: date)
    #expect(p.profiles.map(\.name) == ["Anna Testowa", "Bob Example"])
}

@Test func sameSampleNotTwice() {
    var p = VoiceProfiles()
    p.learn(name: "Anna Testowa", sample: sample("a"), now: date)
    p.learn(name: "Anna Testowa", sample: sample("a", [0, 1]), now: date)
    #expect(p.profiles[0].samples.count == 1)
}

@Test func capsTwentyPerModel() {
    var p = VoiceProfiles()
    p.learn(name: "Anna Testowa", sample: sample("other", model: "x"), now: date)
    for i in 0..<21 { p.learn(name: "Anna Testowa", sample: sample("s\(i)"), now: date) }
    let own = p.profiles[0].samples.filter { $0.model == "m" }
    #expect(own.count == 20 && own.first?.id == "s1")
    #expect(p.profiles[0].samples.contains { $0.id == "other" })
}

@Test func forgetRemovesSampleAndEmptyProfile() {
    var p = VoiceProfiles()
    p.learn(name: "Anna Testowa", sample: sample("a"), now: date)
    p.learn(name: "Anna Testowa", sample: sample("b"), now: date)
    p.learn(name: "Bob Example", sample: sample("c"), now: date)
    p.forget(sampleID: "a")
    p.forget(sampleID: "c")
    #expect(p.profiles.map(\.name) == ["Anna Testowa"] && p.profiles[0].samples.map(\.id) == ["b"])
}

@Test func vectorIsWeightedMean() throws {
    let profile = VoiceProfile(name: "Anna Testowa", updatedAt: date, samples: [
        sample("a", [2, 0], seconds: 30), sample("b", [0, 5], seconds: 10), sample("c", [9, 9], model: "other")])
    let v = try #require(profile.vector(model: "m"))
    #expect(abs(Double(v[0]) - 3 / 10.0.squareRoot()) < 0.0001 && abs(Double(v[1]) - 1 / 10.0.squareRoot()) < 0.0001)
    #expect(profile.vector(model: "none") == nil)
    #expect(profile.seconds(model: "m") == 40)
}

@Test func corruptFileThrowsAndRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try VoiceProfiles.load(root: root) == VoiceProfiles())
    var p = VoiceProfiles()
    p.learn(name: "Anna Testowa", sample: sample("a"), now: date)
    try p.save(root: root)
    #expect(try VoiceProfiles.load(root: root) == p)
    try Data("broken".utf8).write(to: VoiceProfiles.url(root: root))
    #expect(throws: (any Error).self) { try VoiceProfiles.load(root: root) }
    try VoiceProfiles.delete(root: root)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: root).path))
}

@Test func sampleIDIncludesDigest() {
    #expect(VoiceSample.id(session: "s", run: "r", key: "S1", digest: "d") == "s/r/S1/d")
}
