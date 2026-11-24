import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeApp

/// Dane syntetyczne: fikcyjne imiona, wektory 4-wymiarowe, „model” mówców z pustych plików o rozmiarach z manifestu.
@MainActor private struct Fixture {
    let root: URL
    let model: AppModel
    let session: URL
    var item: SessionItem

    init(audio: Bool = true, trackTimes: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.path, 1)
        model = AppModel()
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        let store = model.speakerModel.store
        for (file, size) in DiarizerManifest.offline.files {
            let url = store.directory.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url); try handle.truncate(atOffset: UInt64(size)); try handle.close()
        }
        session = root.appendingPathComponent("sessions/s1")
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        if audio { FileManager.default.createFile(atPath: session.appendingPathComponent("system.caf").path, contents: Data([0])) }
        try JSONFile.save(Self.diarization(trackTimes: trackTimes), to: run.speakers)
        item = SessionItem(url: session, summary: nil, startedAt: Date(), transcript: nil, progress: nil)
        item.runID = "run"
    }

    nonisolated static func diarization(trackTimes: Bool = true) -> SpeakerDiarization {
        SpeakerDiarization(version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                           audioFingerprint: nil, createdAt: nil, segments: [
            .init(speaker: "S1", start: 0, end: 30, trackStart: trackTimes ? 0 : nil, trackEnd: trackTimes ? 30 : nil),
            .init(speaker: "S2", start: 30, end: 60, trackStart: trackTimes ? 30 : nil, trackEnd: trackTimes ? 60 : nil)])
    }

    func speakers() throws -> SpeakerDiarization? {
        try JSONFile.load(SpeakerDiarization?.self, from: RunDirectory(session: session, runID: "run").speakers, default: nil)
    }

    func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }
}

private actor EmbedGate {
    var calls = 0
    var continuation: CheckedContinuation<Void, Never>?
    var hold = false
    func setHold() { hold = true }
    func embed(_ speakers: [String: [ClosedRange<Double>]]) async -> [String: [Float]] {
        calls += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        return speakers.mapValues { _ in [1, 0, 0, 0] }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@Test func voiceLearningRefusalsAndConsent() {
    #expect(VoiceLearning.refusal(hasAudio: true, hasTrackTimes: true, seconds: 20, modelReady: true) == nil)
    #expect(VoiceLearning.refusal(hasAudio: false, hasTrackTimes: true, seconds: 30, modelReady: true) != nil)
    #expect(VoiceLearning.refusal(hasAudio: true, hasTrackTimes: false, seconds: 30, modelReady: true) != nil)
    #expect(VoiceLearning.refusal(hasAudio: true, hasTrackTimes: true, seconds: 19.9, modelReady: true) != nil)
    #expect(VoiceLearning.refusal(hasAudio: true, hasTrackTimes: true, seconds: 30, modelReady: false) != nil)
    #expect(VoiceLearning.shouldAsk(consent: nil, refusal: nil))
    #expect(!VoiceLearning.shouldAsk(consent: false, refusal: nil) && !VoiceLearning.shouldAsk(consent: nil, refusal: "x"))
    #expect(VoiceLearning.mayStore(consent: true) && !VoiceLearning.mayStore(consent: nil) && !VoiceLearning.mayStore(consent: false))
}

@Test func settingsDecodeWithoutVoiceFields() throws {
    let s = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    #expect(s.voiceProfiles == nil && s.voiceModelBeta == nil)
}

@Test @MainActor func namingAsksConsentOnceThenLearns() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let gate = EmbedGate()
    f.model.voiceEmbedOverride = { _, speakers, _ in await gate.embed(speakers) }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    #expect(try f.speakers()?.names == ["S1": "Anna Testowa"])
    #expect(f.model.voiceConsentPending?.key == "S1" && f.model.voiceProfiles.profiles.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: f.root).path))
    f.model.answerVoiceConsent(true)
    await f.waitFor { !f.model.voiceProfiles.profiles.isEmpty }
    #expect(f.model.settings.voiceProfiles == true && f.model.voiceConsentPending == nil)
    let saved = try VoiceProfiles.load(root: f.root)
    #expect(saved.profiles.map(\.name) == ["Anna Testowa"] && saved.profiles[0].samples[0].model == VoiceModel.diarizer.id)
    #expect(saved.profiles[0].samples[0].seconds == 30)
    // Zmiana imienia cofa próbkę z Anny i uczy profil Boba.
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Bob Example")
    await f.waitFor { f.model.voiceProfiles.profiles.map(\.name) == ["Bob Example"] }
    #expect(try VoiceProfiles.load(root: f.root).profiles.map(\.name) == ["Bob Example"])
}

@Test @MainActor func refusedConsentStoresNothing() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.voiceEmbedOverride = { _, _, _ in Issue.record("no embedding without consent"); return [:] }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    f.model.answerVoiceConsent(false)
    f.model.renameSpeaker(item: f.item, key: "S2", name: "Bob Example")
    #expect(f.model.voiceConsentPending == nil && f.model.settings.voiceProfiles == false)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: f.root).path))
}

@Test @MainActor func consentRevokedDuringLearningStoresNothing() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let gate = EmbedGate()
    await gate.setHold()
    f.model.voiceEmbedOverride = { _, speakers, _ in await gate.embed(speakers) }
    f.model.setVoiceConsent(true)
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    while await gate.calls == 0 { await Task.yield() }
    f.model.setVoiceConsent(false)
    await gate.release()
    try await Task.sleep(for: .milliseconds(100))
    #expect(f.model.voiceProfiles.profiles.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: f.root).path))
}

@Test @MainActor func learningWithoutAudioKeepsName() async throws {
    let f = try Fixture(audio: false); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.voiceEmbedOverride = { _, _, _ in Issue.record("no embedding without audio"); return [:] }
    f.model.setVoiceConsent(true)
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    #expect(try f.speakers()?.names == ["S1": "Anna Testowa"])
    #expect(f.model.lastError == VoiceLearning.refusal(hasAudio: false, hasTrackTimes: true, seconds: 30, modelReady: true))
    #expect(f.model.voiceProfiles.profiles.isEmpty)
}

@Test @MainActor func oldSpeakersFileCannotLearn() async throws {
    let f = try Fixture(trackTimes: false); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    #expect(try f.speakers()?.names == ["S1": "Anna Testowa"] && f.model.voiceConsentPending == nil)
}

@Test @MainActor func detectionFillsNamesFromProfiles() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.setVoiceConsent(true)
    f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    f.model.voiceEmbedOverride = { _, speakers, _ in
        speakers.keys.contains("S2") ? ["S1": [1, 0, 0, 0], "S2": [0, 1, 0, 0]] : [:]
    }
    f.model.speakerWorkOverride = { Fixture.diarization() }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    let saved = try #require(try f.speakers())
    #expect(saved.names == ["S1": "Anna Testowa"])
    #expect(saved.voiceMatches?["S1"]?.profileID == f.model.voiceProfiles.profiles[0].id && saved.voiceMatches?["S1"]?.model == VoiceModel.diarizer.id)
    // Bez zgody: etykiety bez imion, bez liczenia.
    f.model.setVoiceConsent(false)
    f.model.voiceEmbedOverride = { _, _, _ in Issue.record("no embedding without consent"); return [:] }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers()?.names == nil)
}

@Test @MainActor func embeddingFailureKeepsLabels() async throws {
    struct Broken: Error {}
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.setVoiceConsent(true)
    f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    f.model.voiceEmbedOverride = { _, _, _ in throw Broken() }
    f.model.speakerWorkOverride = { Fixture.diarization() }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers()?.segments.count == 2 && (try f.speakers()?.names) == nil)
    #expect(f.model.lastError?.hasPrefix("Couldn't recognize voices") == true)
}

@Test @MainActor func deleteAllRemovesFileAndCorruptCopies() throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: "m", values: [1], seconds: 40), now: Date())
    try f.model.voiceProfiles.save(root: f.root)
    let corrupt = f.root.appendingPathComponent("voice-profiles.json.corrupt-20261124-000000")
    try Data("x".utf8).write(to: corrupt)
    f.model.deleteAllVoiceProfiles()
    #expect(f.model.voiceProfiles.profiles.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: f.root).path) && !FileManager.default.fileExists(atPath: corrupt.path))
}

@Test func voiceProfilesTexts() {
    #expect(VoiceProfilesText.recognized(similarity: 0.874) == "Recognized by voice (87%)")
    let profile = VoiceProfile(name: "Anna Testowa", updatedAt: Date(), samples: [
        VoiceSample(id: "a", model: "m", values: [1], seconds: 20), VoiceSample(id: "b", model: "m", values: [1], seconds: 70),
        VoiceSample(id: "c", model: "old", values: [1], seconds: 600)])
    #expect(VoiceProfilesText.row(profile, model: "m") == "2 samples · 2 min")
    #expect(!VoiceProfilesText.needsSample(profile, model: "m") && VoiceProfilesText.needsSample(profile, model: "new"))
}

@Test @MainActor func recognitionShownOnlyForCurrentModel() throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    var item = f.item
    let id = f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    item.speakers = Fixture.diarization().applying([.init(key: "S1", profileID: id, similarity: 0.9)], names: [id: "Anna Testowa"], model: VoiceModel.diarizer.id)
    #expect(f.model.voiceRecognition(item, key: "S1") == 0.9)
    #expect(f.model.voiceRecognition(item, key: "S2") == nil)
    f.model.setVoiceBeta(true)
    #expect(f.model.voiceRecognition(item, key: "S1") == nil) // imię zostaje, znacznik „rozpoznano” tylko dla bieżącego modelu
    #expect(item.speakers?.names?["S1"] == "Anna Testowa")
}

@Test @MainActor func voiceProfilesLiveOutsideMeetingsAndDeletedProfileLosesMark() throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    // Biometria w katalogu danych, poza folderem spotkań (archiwum i MCP czytają tylko spotkania).
    #expect(VoiceProfiles.url(root: f.model.paths.root).deletingLastPathComponent().standardizedFileURL.path == f.model.paths.root.standardizedFileURL.path)
    #expect(!VoiceProfiles.url(root: f.model.paths.root).path.hasPrefix(f.model.paths.sessions.path + "/"))
    let id = f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    var item = f.item
    item.speakers = Fixture.diarization().applying([.init(key: "S1", profileID: id, similarity: 0.9)], names: [id: "Anna Testowa"], model: VoiceModel.diarizer.id)
    #expect(f.model.voiceRecognition(item, key: "S1") == 0.9)
    f.model.deleteVoiceProfile(id)
    #expect(f.model.voiceRecognition(item, key: "S1") == nil)
}

@Test @MainActor func consentRevokedDuringDetectionDropsNames() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.setVoiceConsent(true)
    f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    let gate = EmbedGate()
    await gate.setHold()
    f.model.voiceEmbedOverride = { _, speakers, _ in await gate.embed(speakers) }
    f.model.speakerWorkOverride = { Fixture.diarization() }
    let detection = Task { await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium) }
    while await gate.calls == 0 { await Task.yield() }
    f.model.setVoiceConsent(false)
    await gate.release()
    await detection.value
    let saved = try #require(try f.speakers())
    #expect(saved.names == nil && saved.voiceMatches == nil && saved.segments.count == 2)
}

@Test @MainActor func renameDuringLearningStoresOnlyLatestName() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let gate = EmbedGate()
    await gate.setHold()
    f.model.voiceEmbedOverride = { _, speakers, _ in await gate.embed(speakers) }
    f.model.setVoiceConsent(true)
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    while await gate.calls == 0 { await Task.yield() }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Bob Example")
    while await gate.calls < 2 { await gate.release(); await Task.yield() }
    await gate.release()
    await f.waitFor { f.model.voiceProfiles.profiles.contains { $0.name == "Bob Example" } }
    try await Task.sleep(for: .milliseconds(100))
    #expect(f.model.voiceProfiles.profiles.map(\.name) == ["Bob Example"])
    #expect(f.model.voiceProfiles.profiles.first?.samples.count == 1)
}

@Test @MainActor func shortSpeakerNamedQuietly() throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let run = RunDirectory(session: f.session, runID: "run")
    var d = Fixture.diarization()
    d.segments[0].end = 10; d.segments[0].trackEnd = 10
    try JSONFile.save(d, to: run.speakers)
    f.model.voiceEmbedOverride = { _, _, _ in Issue.record("no embedding for a short speaker"); return [:] }
    f.model.setVoiceConsent(true)
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    #expect(try f.speakers()?.names == ["S1": "Anna Testowa"] && f.model.lastError == nil)
}

@Test func stillNamedRequiresSameNameAndDetection() {
    let d = Fixture.diarization().renamed("S1", to: "Anna Testowa")!
    #expect(VoiceLearning.stillNamed(d, key: "S1", name: "anna testowa", digest: d.segmentsDigest, sampleKey: "S1"))
    #expect(!VoiceLearning.stillNamed(d, key: "S1", name: "Bob Example", digest: d.segmentsDigest, sampleKey: "S1"))
    #expect(!VoiceLearning.stillNamed(d, key: "S1", name: "Anna Testowa", digest: "other", sampleKey: "S1"))
    #expect(!VoiceLearning.stillNamed(nil, key: "S1", name: "Anna Testowa", digest: d.segmentsDigest, sampleKey: "S1"))
    #expect(!VoiceLearning.stillNamed(d, key: "S1", name: "Anna Testowa", digest: d.segmentsDigest, sampleKey: "S1+S2"))
}

@Test @MainActor func deleteDuringLearningStaysDeleted() async throws {
    let f = try Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let gate = EmbedGate()
    await gate.setHold()
    f.model.voiceEmbedOverride = { _, speakers, _ in await gate.embed(speakers) }
    f.model.setVoiceConsent(true)
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    while await gate.calls == 0 { await Task.yield() }
    f.model.deleteAllVoiceProfiles()
    await gate.release()
    try await Task.sleep(for: .milliseconds(100))
    #expect(f.model.voiceProfiles.profiles.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: VoiceProfiles.url(root: f.root).path))
}
