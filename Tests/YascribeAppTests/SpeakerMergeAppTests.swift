import Foundation
import Testing
import YascribeLocalASR
import YascribeMeetings
import YascribeNotes
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeApp

/// Dane syntetyczne: trzy grupy, z czego S1 i S2 to ten sam „głos”.
@MainActor private struct MergeFixture {
    let root: URL
    let model: AppModel
    let session: URL
    var item: SessionItem

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.path, 1)
        model = AppModel()
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        session = root.appendingPathComponent("sessions/s1")
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: session.appendingPathComponent("system.caf").path, contents: Data([0]))
        try JSONFile.save(Self.diarization, to: run.speakers)
        item = SessionItem(url: session, summary: nil, startedAt: Date(), transcript: nil, progress: nil)
        item.runID = "run"
    }

    nonisolated static let diarization = SpeakerDiarization(
        version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
        audioFingerprint: nil, createdAt: nil, segments: [
            .init(speaker: "S1", start: 0, end: 30, trackStart: 0, trackEnd: 30),
            .init(speaker: "S2", start: 30, end: 50, trackStart: 30, trackEnd: 50),
            .init(speaker: "S3", start: 50, end: 80, trackStart: 50, trackEnd: 80)])

    nonisolated static func vectors(_ spans: [String: [ClosedRange<Double>]]) -> [String: [Float]] {
        let all: [String: [Float]] = ["S1": [1, 0, 0, 0], "S2": [0.99, 0.14, 0, 0], "S3": [0, 1, 0, 0]]
        return all.filter { spans.keys.contains($0.key) }
    }

    /// Puste pliki o rozmiarach z manifestu: magazyn modelu mówców `.ready` (rozpoznawanie profili tego wymaga).
    func installModel() throws {
        let store = model.speakerModel.store
        for (file, size) in DiarizerManifest.offline.files {
            let url = store.directory.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url); try handle.truncate(atOffset: UInt64(size)); try handle.close()
        }
    }

    func speakers() throws -> SpeakerDiarization? {
        try JSONFile.load(SpeakerDiarization?.self, from: RunDirectory(session: session, runID: "run").speakers, default: nil)
    }
}

@Test @MainActor func detectionMergesDuplicateGroups() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.speakerMergeEmbedOverride = { _, spans, model in
        #expect(model == .diarizer)
        return MergeFixture.vectors(spans)
    }
    f.model.speakerWorkOverride = { MergeFixture.diarization }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    let saved = try #require(try f.speakers())
    #expect(Set(saved.segments.map(\.speaker)) == ["S1", "S3"])
    #expect(saved.merges == ["S2": .init(into: "S1", auto: true)])
}

@Test @MainActor func detectionWithoutEmbedKeepsGroups() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    // Brak pobranego modelu mówców i brak atrapy: bez łączenia, bez błędu.
    f.model.speakerWorkOverride = { MergeFixture.diarization }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers() == MergeFixture.diarization)
    #expect(f.model.lastError == nil)
    // Błąd liczenia: też bez łączenia i bez komunikatu.
    f.model.speakerMergeEmbedOverride = { _, _, _ in throw CocoaError(.fileReadCorruptFile) }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers() == MergeFixture.diarization && f.model.lastError == nil)
}

@Test @MainActor func mergeRunsWithoutVoiceConsent() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.setVoiceConsent(false)
    f.model.speakerMergeEmbedOverride = { _, spans, _ in MergeFixture.vectors(spans) }
    f.model.speakerWorkOverride = { MergeFixture.diarization }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers()?.merges?["S2"] != nil)
}

@Test @MainActor func mergeHappensBeforeRecognition() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    f.model.voiceProfiles.learn(name: "Anna Testowa", sample: VoiceSample(id: "x", model: VoiceModel.diarizer.id, values: [1, 0, 0, 0], seconds: 40), now: Date())
    f.model.speakerMergeEmbedOverride = { _, spans, _ in MergeFixture.vectors(spans) }
    // Profile widzą już złączoną grupę S1 (50 s) — S2 nie istnieje.
    f.model.voiceEmbedOverride = { _, spans, _ in
        #expect(!spans.keys.contains("S2"))
        return MergeFixture.vectors(spans)
    }
    f.model.speakerWorkOverride = { MergeFixture.diarization }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    let saved = try #require(try f.speakers())
    #expect(saved.names == ["S1": "Anna Testowa"] && saved.merges?["S2"]?.into == "S1")
}

@Test @MainActor func calendarHintLowersThreshold() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    // S1 i S2 podobne tylko na 0.67 — łączy je dopiero wskazówka z kalendarza (2 uczestników = 1 zdalny).
    f.model.speakerMergeEmbedOverride = { _, spans, _ in
        let all: [String: [Float]] = ["S1": [1, 0, 0, 0], "S2": [0.67, 0.7424, 0, 0], "S3": [0.67, -0.7424, 0, 0]]
        return all.filter { spans.keys.contains($0.key) }
    }
    f.model.speakerWorkOverride = { MergeFixture.diarization }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers()?.merges == nil)
    _ = try NotesStore(session: f.session).updateMeta {
        $0.calendarEvent = CalendarLink(title: "t", start: Date(), end: Date(), attendees: [.init(name: "Ja"), .init(name: "Anna Testowa")])
    }
    await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium)
    #expect(try f.speakers()?.merges != nil)
}

private actor Gate {
    var waiting: CheckedContinuation<Void, Never>?
    var started = false
    func wait() async { started = true; await withCheckedContinuation { waiting = $0 } }
    func release() { waiting?.resume(); waiting = nil }
}

@Test @MainActor func manualMergeSavesAndLearnsTarget() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    f.model.voiceEmbedOverride = { _, spans, _ in spans.mapValues { _ in [1, 0, 0, 0] } }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.count == 1 }
    let before = try #require(f.model.voiceProfiles.profiles.first?.samples.first)
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    let saved = try #require(try f.speakers())
    #expect(saved.merges == ["S2": .init(into: "S1", auto: false)] && saved.names == ["S1": "Anna Testowa"])
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.first?.id != before.id }
    #expect(!f.model.voiceProfiles.profiles.isEmpty)
    // Stara próbka (30 s) zastąpiona próbką całej złączonej mowy (50 s).
    #expect(f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [50])
}

@Test @MainActor func manualMergeWithoutConsentDoesNotLearn() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(false)
    f.model.voiceEmbedOverride = { _, _, _ in Issue.record("no embedding without consent"); return [:] }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    try await Task.sleep(for: .milliseconds(100))
    #expect(try f.speakers()?.merges?["S2"] != nil && f.model.voiceProfiles.profiles.isEmpty)
}

@Test @MainActor func manualMergeIntoRecognizedLearns() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    var d = MergeFixture.diarization
    d.names = ["S1": "Anna Testowa"]
    d.voiceMatches = ["S1": .init(profileID: UUID(), similarity: 0.9, model: VoiceModel.diarizer.id)]
    try JSONFile.save(d, to: RunDirectory(session: f.session, runID: "run").speakers)
    f.model.voiceEmbedOverride = { _, spans, _ in spans.mapValues { _ in [1, 0, 0, 0] } }
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    #expect(try f.speakers()?.voiceMatches == nil)
    await waitUntil { !f.model.voiceProfiles.profiles.isEmpty }
    #expect(f.model.voiceProfiles.profiles.map(\.name) == ["Anna Testowa"])
}

@Test @MainActor func splitRestoresGroup() throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    f.model.splitSpeaker(item: f.item, original: "S2")
    #expect(try f.speakers() == MergeFixture.diarization)
}

@Test @MainActor func mergeOnStaleFileIsNoop() throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.model.mergeSpeaker(item: f.item, key: "S9", into: "S1")
    f.model.splitSpeaker(item: f.item, original: "S2")
    #expect(try f.speakers() == MergeFixture.diarization && f.model.lastError == nil)
}

@Test @MainActor func mergeRefusedDuringDetection() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let gate = Gate()
    f.model.speakerWorkOverride = { await gate.wait(); return MergeFixture.diarization }
    let detection = Task { await f.model.detectSpeakers(sessionURL: f.session, runID: "run", sensitivity: .medium) }
    while await !gate.started { await Task.yield() }
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    let saved = try f.speakers()
    #expect(f.model.lastError != nil && saved?.merges == nil)
    await gate.release()
    await detection.value
}

@Test @MainActor func mergeOptionsListOthersAndMerged() throws {
    var f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    f.item.speakers = MergeFixture.diarization.merging(["S2": "S1"], auto: true)
    let options = f.model.speakerMergeOptions(f.item, key: "S1", numbers: ["S1": 1, "S3": 2])
    #expect(options.others.map(\.key) == ["S3"] && options.others.map(\.label) == ["Speaker 2"])
    #expect(options.merged.map(\.key) == ["S2"] && options.merged.map(\.auto) == [true])
}

@MainActor private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

@Test @MainActor func mergeOptionsWithoutNoteUseTranscriptNumbers() throws {
    var f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    func u(_ at: Double) -> Utterance {
        Utterance(speaker: .them, start: at, end: at + 2, text: "x", words: [], approximateTiming: false, languageMismatch: nil)
    }
    f.item.transcript = Transcript(utterances: [u(5), u(35), u(60)], failedChunks: [])
    f.item.speakers = MergeFixture.diarization
    #expect(f.model.speakerMergeOptions(f.item, key: "S1").others.map(\.key) == ["S2", "S3"])
}

private actor HoldFirst {
    var calls = 0
    var waiting: CheckedContinuation<Void, Never>?
    func embed(_ spans: [String: [ClosedRange<Double>]]) async -> [String: [Float]] {
        calls += 1
        if calls == 1 { await withCheckedContinuation { waiting = $0 } }
        return spans.mapValues { _ in [1, 0, 0, 0] }
    }
    func release() { waiting?.resume(); waiting = nil }
}

@Test @MainActor func mergeDuringLearningStoresOnlyMergedSample() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    let gate = HoldFirst()
    f.model.voiceEmbedOverride = { _, spans, _ in await gate.embed(spans) }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    while await gate.calls == 0 { await Task.yield() }
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.isEmpty == false }
    await gate.release()
    try await Task.sleep(for: .milliseconds(100))
    // Nauka sprzed złączenia (30 s samego S1) nie trafia do profilu — grupa zmieniła skład w trakcie liczenia.
    #expect(f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [50])
}

@Test @MainActor func splitForgetsMixedSampleAndRelearns() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    f.model.voiceEmbedOverride = { _, spans, _ in spans.mapValues { _ in [1, 0, 0, 0] } }
    f.model.renameSpeaker(item: f.item, key: "S1", name: "Anna Testowa")
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [50] }
    f.model.splitSpeaker(item: f.item, original: "S2")
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [30] }
    #expect(f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [30])
}

@Test @MainActor func splitReturnsNameAndRelearnsSource() async throws {
    let f = try MergeFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.installModel()
    f.model.setVoiceConsent(true)
    f.model.voiceEmbedOverride = { _, spans, _ in spans.mapValues { _ in [1, 0, 0, 0] } }
    f.model.renameSpeaker(item: f.item, key: "S2", name: "Bob Example")
    f.model.mergeSpeaker(item: f.item, key: "S2", into: "S1")
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [50] }
    f.model.splitSpeaker(item: f.item, original: "S2")
    #expect(try f.speakers()?.names == ["S2": "Bob Example"])
    await waitUntil { f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [20] }
    #expect(f.model.voiceProfiles.profiles.map(\.name) == ["Bob Example"])
    #expect(f.model.voiceProfiles.profiles.first?.samples.map(\.seconds) == [20])
}
