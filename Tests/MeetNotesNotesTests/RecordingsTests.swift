import Foundation
import Testing
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

private let ns1 = Timebase(numer: 1, denom: 1)
private let day: TimeInterval = 86_400

/// Sesja w `root/name`: `system.caf` + dziennik (wallClock = teraz), opcjonalnie przebieg z transkryptem i My notes.
@discardableResult
private func seed(_ root: URL, _ name: String, run: String? = "2026-10-01-1000", transcript t: Transcript? = transcript([utt("hej")]),
                  myNotes: String = "moje") throws -> URL {
    let dir = root.appendingPathComponent(name)
    let src = FileSource(trackID: "system", samples: [Int16](repeating: 100, count: 16_000), sampleRate: 16_000, channels: 1,
                         startHostTime: 1_000_000_000, timebase: ns1, chunkFrames: 1_600)
    try SessionRecorder(directory: dir, sources: [src], conditions: [], clock: ManualHostClock(), timebase: ns1, zeroWatch: [:]).start()
    if let run {
        let rd = RunDirectory(session: dir, runID: run)
        try FileManager.default.createDirectory(at: rd.url, withIntermediateDirectories: true)
        if let t { try JSONFile.save(t, to: rd.transcript) }
    }
    try NotesStore(session: dir).writeMyNotes(myNotes)
    return dir
}

private func files(_ dir: URL) -> Set<String> {
    Set((FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String]) ?? [])
}

@Test func retentionKeepsAudioWithoutFinishedTranscription() throws {
    let root = tempDir()
    let noRun = try seed(root, "no-run", run: nil)
    let inProgress = try seed(root, "in-progress", transcript: nil)
    var gaps = transcript([utt("hej")])
    gaps.failedChunks = [ChunkFailure(track: "system", index: 0, start: 0, end: 59, error: "500")]
    let partial = try seed(root, "partial", transcript: gaps)
    // Starszy przebieg ukończony, nowszy przerwany („Transcribe again”) — liczy się najnowszy.
    let rerun = try seed(root, "rerun", run: "2026-10-01-1000")
    try FileManager.default.createDirectory(at: RunDirectory(session: rerun, runID: "2026-10-02-1000").url, withIntermediateDirectories: true)
    let busy = try seed(root, "busy")

    let r = AudioRetention.apply(sessions: root, days: 30, now: Date() + 31 * day, skip: ["busy"])
    #expect(r.purged.isEmpty)
    #expect(r.errors.isEmpty)
    for s in [noRun, inProgress, partial, rerun, busy] {
        #expect(AudioRetention.audioFiles(s).count == 1, "\(s.lastPathComponent)")
        #expect(AudioDeletion.read(s) == nil)
    }
}

@Test func retentionDeletesOnlyCafAndOnlyAfterTheTerm() throws {
    let root = tempDir()
    let s = try seed(root, "done")
    let before = files(s)
    #expect(before.contains("system.caf"))

    // Przed terminem i przy Forever — nic.
    #expect(AudioRetention.apply(sessions: root, days: 30, now: Date() + 29 * day, skip: []).purged.isEmpty)
    #expect(AudioRetention.apply(sessions: root, days: nil, now: Date() + 3_650 * day, skip: []).purged.isEmpty)
    #expect(files(s) == before)

    let r = AudioRetention.apply(sessions: root, days: 30, now: Date() + 31 * day, skip: [])
    #expect(r.purged == ["done"])
    #expect(r.errors.isEmpty)
    #expect(files(s) == before.subtracting(["system.caf"]).union(["audio-deleted.json"]))
    #expect(AudioDeletion.read(s)?.afterDays == 30)
    #expect(NotesStore(session: s).readMyNotes() == "moje")
    // Drugi przebieg: nie ma już audio — nic do zrobienia.
    #expect(AudioRetention.apply(sessions: root, days: 30, now: Date() + 40 * day, skip: []).purged.isEmpty)
}

@Test func retentionPlanMatchesWhatRetentionDeletes() throws {
    let root = tempDir()
    let done = try seed(root, "done")
    try seed(root, "no-run", run: nil)
    try seed(root, "busy")
    let done2 = try seed(root, "done2")
    let now = Date() + 31 * day
    let cafBytes = Int64(try done.appendingPathComponent("system.caf").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    #expect(cafBytes > 0)
    let before = files(root)

    #expect(AudioRetention.plan(sessions: root, days: nil, now: now, skip: []).sessions.isEmpty) // Forever
    let p = AudioRetention.plan(sessions: root, days: 30, now: now, skip: ["busy"])
    #expect(p.sessions.map(\.lastPathComponent) == ["done", "done2"])
    #expect(p.bytes == 2 * cafBytes)
    #expect(files(root) == before) // plan niczego nie kasuje
    // Przed terminem (90 dni) — nic.
    #expect(AudioRetention.plan(sessions: root, days: 90, now: now, skip: ["busy"]).sessions.isEmpty)

    let r = AudioRetention.apply(sessions: root, days: 30, now: now, skip: ["busy"])
    #expect(r.purged == p.sessions.map(\.lastPathComponent))
    #expect(AudioRetention.audioFiles(done).isEmpty)
    #expect(AudioRetention.audioFiles(done2).isEmpty)
    #expect(AudioRetention.plan(sessions: root, days: 30, now: now, skip: ["busy"]).sessions.isEmpty)
}

@Test func settingsWithoutRecordingFieldsStillLoad() throws {
    let old = try JSONDecoder().decode(GlobalSettings.self, from: Data(#"{"defaultPresetID":null}"#.utf8))
    #expect(old.recordingsPath == nil)
    #expect(old.audioRetentionDays == 30)
    #expect(GlobalSettings(keepAudioDays: 7, keepAudioForever: true).audioRetentionDays == nil)
    #expect(GlobalSettings(keepAudioDays: 0).audioRetentionDays == 1) // żadna liczba dni nie kasuje „od razu”
}

private func oldAndNew() throws -> (URL, URL) {
    let root = tempDir()
    let old = root.appendingPathComponent("old")
    try seed(old, "a")
    try seed(old, "b")
    return (old, root.appendingPathComponent("new"))
}

@Test func moveDeletesNothingWhenCopyFails() async throws {
    let (old, new) = try oldAndNew()
    let before = files(old)
    struct Boom: Error {}
    // Druga sesja: kopia urwana w połowie (pusty katalog) i błąd; w trakcie ktoś wrzucił do celu obcy plik.
    let failSecond: RecordingsMove.Copy = { from, to in
        if from.lastPathComponent == "b" {
            try Data("cudze".utf8).write(to: to.deletingLastPathComponent().appendingPathComponent("foreign.txt"))
            try FileManager.default.createDirectory(at: to, withIntermediateDirectories: false)
            throw Boom()
        }
        try FileManager.default.copyItem(at: from, to: to)
    }
    await #expect(throws: RecordingsMove.Failure.self) {
        _ = try await RecordingsMove.run(from: old, to: new, copy: failSecond) { Issue.record("commit po błędzie kopii") }
    }
    #expect(files(old) == before)
    // R2: nasza częściowa kopia (a, urwane b) zniknęła, obcy plik został.
    #expect(files(new) == ["foreign.txt"])
}

@Test func moveCleanupLeavesEntriesItDidNotCreate() async throws {
    let (old, new) = try oldAndNew()
    let before = files(old)
    // Obcy wpis o nazwie sesji pojawia się w celu, zanim do niego dojdziemy — kopia na nim pada, ale go nie kasujemy.
    let foreignB: RecordingsMove.Copy = { from, to in
        if from.lastPathComponent == "a" {
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent().appendingPathComponent("b/obce"),
                                                    withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: from, to: to)
    }
    await #expect(throws: RecordingsMove.Failure.self) {
        _ = try await RecordingsMove.run(from: old, to: new, copy: foreignB) { Issue.record("commit po błędzie kopii") }
    }
    #expect(files(old) == before)
    #expect(files(new) == ["b", "b/obce"])
}

@Test func moveDeletesNothingWhenVerificationFails() async throws {
    let (old, new) = try oldAndNew()
    let before = files(old)
    // Kopia „udana”, ale jeden plik ucięty — weryfikacja rozmiarów musi to złapać.
    let truncating: RecordingsMove.Copy = { from, to in
        try FileManager.default.copyItem(at: from, to: to)
        if from.lastPathComponent == "b" { try Data().write(to: to.appendingPathComponent("system.caf")) }
    }
    await #expect(throws: RecordingsMove.Failure.self) {
        _ = try await RecordingsMove.run(from: old, to: new, copy: truncating) { Issue.record("commit po złej weryfikacji") }
    }
    #expect(files(old) == before)
    // R2: folder utworzony przez przebieg i pusty po sprzątaniu — usunięty; ponowna próba do niego przechodzi.
    #expect(!FileManager.default.fileExists(atPath: new.path))
    #expect(try await RecordingsMove.run(from: old, to: new) {}.isEmpty)
    #expect(files(new) == before)
}

@Test func moveCopiesVerifiesThenDeletes() async throws {
    let (old, new) = try oldAndNew()
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true) // pusty folder z panelu
    let before = files(old)
    struct NoSave: Error {}
    // Commit (zapis ustawień) nieudany — nic nie kasujemy ze starego miejsca, nasza kopia znika, folder zostaje.
    await #expect(throws: RecordingsMove.Failure.self) {
        _ = try await RecordingsMove.run(from: old, to: new) { throw NoSave() }
    }
    #expect(files(old) == before)
    #expect(files(new).isEmpty)
    #expect(FileManager.default.fileExists(atPath: new.path))

    // Ponowna próba do tego samego folderu (R2).
    let leftovers = try await RecordingsMove.run(from: old, to: new) {}
    #expect(leftovers.isEmpty)
    #expect(files(new) == before)
    #expect(RecordingsMove.topLevel(old).isEmpty)
}

@Test func moveRefusesBadDestinations() throws {
    let (old, new) = try oldAndNew()
    #expect(RecordingsMove.destinationRefusal(from: old, to: old) != nil)
    #expect(RecordingsMove.destinationRefusal(from: old, to: old.appendingPathComponent("x")) != nil)
    #expect(RecordingsMove.destinationRefusal(from: old, to: old.deletingLastPathComponent()) != nil)
    #expect(RecordingsMove.destinationRefusal(from: old, to: old.appendingPathComponent("a")) != nil) // niepusty i wewnątrz
    #expect(RecordingsMove.destinationRefusal(from: old, to: new) == nil) // nie istnieje = pusty
    try FileManager.default.createDirectory(at: new.appendingPathComponent("x"), withIntermediateDirectories: true)
    #expect(RecordingsMove.destinationRefusal(from: old, to: new) != nil) // niepusty
    #expect(RecordingsMove.blocked(recording: true, busy: false, moving: false) != nil)
    #expect(RecordingsMove.blocked(recording: false, busy: true, moving: false) != nil)
    #expect(RecordingsMove.blocked(recording: false, busy: false, moving: false) == nil)
}
