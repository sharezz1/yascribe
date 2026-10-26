import Foundation
import Testing
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeNotes
@testable import YascribeTranscription

private let ns1 = Timebase(numer: 1, denom: 1)

private func makeSession() throws -> URL {
    let dir = tempDir()
    let src = FileSource(trackID: "system", samples: [Int16](repeating: 100, count: 16_000), sampleRate: 16_000, channels: 1,
                         startHostTime: 1_000_000_000, timebase: ns1, chunkFrames: 1_600)
    try SessionRecorder(directory: dir, sources: [src], conditions: [], clock: ManualHostClock(), timebase: ns1, zeroWatch: [:]).start()
    return dir
}

@Test func searchMatchesTitleNotesSummaryAndTranscript() {
    let t = transcript([utt("Prognoza na sobotę")])
    func hit(_ q: String, title: String = "Forecast review", notes: String = "ask about Sunday", summary: String? = "## Staffing", tr: Transcript? = t) -> Bool {
        SessionSearch.matches(q, title: title, myNotes: notes, summary: summary, transcript: tr)
    }
    #expect(hit("forecast")) // tytuł, bez względu na wielkość liter
    #expect(hit("sunday")) // My notes
    #expect(hit("staffing")) // notatka
    #expect(hit("sobotę")) // transkrypt
    #expect(hit("")) // puste zapytanie pokazuje wszystko
    #expect(!hit("zebra"))
    #expect(!hit("zebra", summary: nil, tr: nil))
}

@Test func sessionSummaryIgnoresTheNotesDirectory() throws {
    let dir = try makeSession()
    defer { try? FileManager.default.removeItem(at: dir) }
    let before = try SessionDirectory(url: dir).summarize()
    let store = NotesStore(session: dir)
    try store.writeMyNotes("x")
    try store.writeSummary(NoteSummary(title: nil, markdown: "a", templateID: "standard", model: "m", context: "", generatedAt: Date()))
    try store.writeSummary(NoteSummary(title: nil, markdown: "b", templateID: "standard", model: "m", context: "", generatedAt: Date()))
    #expect(try SessionDirectory(url: dir).summarize() == before)
}

@Test func latestRunIgnoresTheNotesDirectory() throws {
    let dir = try makeSession()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(RunDirectory.latestRunID(in: dir) == nil)
    let runs = dir.appendingPathComponent("runs")
    try FileManager.default.createDirectory(at: runs.appendingPathComponent("2026-10-14T10-00-00Z-aaaa"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: runs.appendingPathComponent("2026-10-14T11-00-00Z-bbbb"), withIntermediateDirectories: true)
    try Data().write(to: runs.appendingPathComponent("zz stray.txt")) // spoza wzorca runID i sortuje się ZA prawdziwymi przebiegami
    try Data().write(to: runs.appendingPathComponent("notes.txt"))
    try FileManager.default.createDirectory(at: runs.appendingPathComponent("debug"), withIntermediateDirectories: true) // `--run debug` z CLI
    try NotesStore(session: dir).writeMyNotes("x") // katalog notes/ obok runs/
    #expect(RunDirectory.latestRunID(in: dir) == "2026-10-14T11-00-00Z-bbbb")
}
