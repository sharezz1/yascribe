import Foundation
import Testing
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

private func status(recording: Bool = false, progress: Double? = nil, correcting: Bool = false, titling: Bool = false,
                    crashed: Bool = false, transcript: Transcript? = nil, hasRun: Bool = false, notes: Bool = false,
                    correctionFailed: Bool = false) -> SessionStatus {
    SessionStatus.of(isRecording: recording, progress: progress, correcting: correcting, titling: titling, crashed: crashed,
                     transcript: transcript, hasRun: hasRun, hasNotes: notes, correctionFailed: correctionFailed)
}

@Test func recordingSessionIsNeverRecovered() {
    // Trwające nagranie ma w podsumowaniu crashed == true (brak session.ended) — to nie jest „Recovered".
    #expect(status(recording: true, crashed: true) == .recording)
}

@Test func crashedSessionThatIsNotRecordingIsRecovered() {
    #expect(status(crashed: true) == .recovered)
}

@Test func statusFollowsTheLifecycleOrder() {
    let t = transcript([utt("x")])
    #expect(status(progress: 0.4, transcript: t) == .transcribing(0.4))
    #expect(status(correcting: true, transcript: t) == .correcting)
    #expect(status(titling: true, transcript: t) == .titling)
    #expect(status() == .notTranscribed)
    #expect(status(hasRun: true) == .interrupted)
    #expect(status(transcript: t) == .transcriptReady)
}

@Test func notesReadyBeatsTranscriptReadyButNotGaps() {
    let ok = transcript([utt("x")])
    var gaps = ok
    gaps.failedChunks = [ChunkFailure(track: "system", index: 0, start: 0, end: 1, error: "boom")]
    let flagged = transcript([utt("x", flagged: true)])
    #expect(status(transcript: ok, notes: true) == .notesReady)
    #expect(status(transcript: gaps, notes: true) == .partial(gaps: 1))
    #expect(status(transcript: flagged) == .flagged(1))
}

@Test func directoryListingURLMatchesTheRecordingURL() throws {
    // Hipoteza z BACKLOG: URL z contentsOfDirectory (ze „/" na końcu) ≠ URL z appendingPathComponent.
    let sessions = tempDir()
    defer { try? FileManager.default.removeItem(at: sessions) }
    let built = sessions.appendingPathComponent("20261014-1000")
    try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
    let listed = try #require(try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil).first)
    #expect(SessionStatus.isRecording(listed, recordingDirectory: built))
    #expect(!SessionStatus.isRecording(listed, recordingDirectory: nil))
    #expect(!SessionStatus.isRecording(listed, recordingDirectory: sessions.appendingPathComponent("other")))
}

@Test func correctionFailureIsVisibleInTheStatusUntilRetried() {
    // Odbiór T13: nieudana korekta nie może znikać ani wisieć — wiersz mówi „Correction failed".
    let t = transcript([utt("x")])
    #expect(status(transcript: t, correctionFailed: true) == .correctionFailed)
    #expect(status(transcript: t, notes: true, correctionFailed: true) == .correctionFailed) // także gdy notatka już jest
    #expect(status(correcting: true, transcript: t, correctionFailed: true) == .correcting) // ponowienie w toku wygrywa
}

@Test func openNoteGoesToMyNotesOfTheRecordedMeeting() {
    // Drugi odbiór 2026-10-16: „Open note” w pigułce → Meetings, nagrywana sesja (nazwa katalogu = SessionItem.id), My notes.
    let dir = URL(fileURLWithPath: "/tmp/sessions/2026-10-16-1430/", isDirectory: true)
    #expect(OpenNoteDestination.forRecording(directory: dir)
            == OpenNoteDestination(section: .meetings, sessionID: "2026-10-16-1430", tab: .myNotes))
    // Nagranie już się skończyło: sama lista spotkań, bez otwierania czegokolwiek.
    #expect(OpenNoteDestination.forRecording(directory: nil) == OpenNoteDestination(section: .meetings, sessionID: nil, tab: nil))
}
