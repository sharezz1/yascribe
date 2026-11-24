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
