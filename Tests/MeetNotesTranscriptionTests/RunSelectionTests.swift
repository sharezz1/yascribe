import Foundation
import Testing
import MeetNotesProviders
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

/// R23 (Task 10b): bieżący przebieg = najnowszy ukończony, niepusty i bez luk; najnowsza próba osobno.
@Suite struct RunSelectionTests {
    // Nazwy muszą pasować do wzorca `RunDirectory.runIDs` — inaczej filtr pominie je po cichu.
    let old = "2026-10-21T10-00-00Z-aaaa"
    let new = "2026-10-23T09-00-00Z-bbbb"

    enum State { case running, thrown, partial, empty, complete }

    func session() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("runsel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("runs"), withIntermediateDirectories: true)
        return url
    }

    func line(_ text: String) -> Utterance {
        Utterance(speaker: .them, start: 0, end: 1, text: text, words: [], approximateTiming: false, languageMismatch: nil)
    }

    /// Katalog przebiegu tak, jak zostawia go `TranscriptionRunner` w danym stanie.
    func write(_ session: URL, _ id: String, _ state: State, snapshot s: RunSnapshot, text: String = "hello") throws {
        let dir = RunDirectory(session: session, runID: id)
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        if state == .thrown { return } // padło zaraz po utworzeniu katalogu
        try JSONFile.save(RunInput(snapshot: s, gate: EnergyGate().config, maxChunkSeconds: 59, crosstalk: CrosstalkFilter(),
                                   trackFrames: ["system": 100]), to: dir.input)
        if state == .running { return }
        let gap = ChunkFailure(track: "system", index: 0, start: 0, end: 59, error: "offline")
        let t = Transcript(utterances: state == .empty ? [] : [line(text)], failedChunks: state == .partial ? [gap] : [])
        try JSONFile.save(t, to: dir.transcript)
        try JSONFile.save(RunMetadata(runID: id, snapshot: s, startedAt: Date(), finishedAt: Date(), chunkCount: 1, requestCount: 1,
                                      audioSecondsSent: 59, failedChunkCount: t.failedChunks.count, languageFlagCount: 0),
                          to: dir.metadata)
    }

    @Test func runningReplacementKeepsOldTranscriptCurrent() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot(), text: "old")
        try write(s, new, .running, snapshot: try snapshot(language: .english))
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.transcript?.utterances.first?.text == "old")
        #expect(sel.snapshot?.language == .polish)
        // Wznowienie idzie do najnowszej próby niezależnie od bieżącego przebiegu.
        #expect(sel.latestAttemptID == new)
        #expect(sel.notPromoted == RunSelection.Attempt(snapshot: try snapshot(language: .english), reason: .unfinished))
    }

    @Test func thrownOrCancelledReplacementKeepsOld() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .thrown, snapshot: try snapshot())
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.latestAttemptID == new)
        #expect(sel.notPromoted == RunSelection.Attempt(snapshot: nil, reason: .unfinished))
    }

    @Test func partialReplacementKeepsOld() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .partial, snapshot: try snapshot(language: .english))
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.notPromoted?.reason == .gaps(1))
    }

    @Test func emptyReplacementKeepsOld() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .empty, snapshot: try snapshot())
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.notPromoted?.reason == .empty)
    }

    @Test func successfulReplacementBecomesCurrent() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot(), text: "old")
        try write(s, new, .complete, snapshot: try snapshot(language: .english), text: "new")
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == new)
        #expect(sel.transcript?.utterances.first?.text == "new")
        #expect(sel.snapshot?.language == .english)
        #expect(sel.latestAttemptID == new)
        #expect(sel.notPromoted == nil)
    }

    @Test func onlyRunWithGapsIsCurrentByFallback() throws {
        // Pierwszy przebieg z luką zostaje bieżącym (jak przed 2.1), więc dostaje łańcuch korekta → autotytuł.
        let s = try session()
        try write(s, old, .partial, snapshot: try snapshot())
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.transcript?.failedChunks.count == 1)
        #expect(sel.notPromoted == nil)
    }

    @Test func withoutCompleteRunsNewestWithTranscriptWins() throws {
        let s = try session()
        try write(s, old, .partial, snapshot: try snapshot(), text: "old")
        try write(s, new, .partial, snapshot: try snapshot(), text: "new")
        #expect(RunSelection.of(session: s).currentID == new)

        let t = try session()
        try write(t, old, .partial, snapshot: try snapshot(), text: "old")
        try write(t, new, .running, snapshot: try snapshot())
        let sel = RunSelection.of(session: t)
        #expect(sel.currentID == old)
        #expect(sel.latestAttemptID == new)

        let u = try session()
        try write(u, new, .thrown, snapshot: try snapshot())
        #expect(RunSelection.of(session: u).currentID == new) // bez transkryptów: najnowszy katalog
        #expect(RunSelection.of(session: try session()).currentID == nil)
    }

    @Test func emptyReplacementDoesNotHideOldTextWithGaps() throws {
        // Np. zły klucz albo offline: każde okno padło, runner zapisał pusty transkrypt z `run.json`.
        let s = try session()
        try write(s, old, .partial, snapshot: try snapshot(), text: "old")
        try write(s, new, .empty, snapshot: try snapshot())
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.transcript?.utterances.first?.text == "old")
        #expect(sel.notPromoted?.reason == .empty)
    }

    @Test func postProcessingOnlyForPromotedRuns() throws {
        func gate(_ older: State?, _ newer: State, finished id: String? = nil) throws -> Bool {
            let s = try session()
            if let older { try write(s, old, older, snapshot: try snapshot()) }
            try write(s, new, newer, snapshot: try snapshot())
            return RunSelection.shouldPostProcess(session: s, runID: id ?? new)
        }
        #expect(try gate(nil, .partial))             // pierwsza transkrypcja z luką: jak przed 2.1
        #expect(try gate(nil, .complete))
        #expect(try gate(nil, .empty))               // pusty jedyny: bieżący przez fallback, łańcuch jak dotąd
        #expect(try !gate(.complete, .partial))
        #expect(try !gate(.complete, .empty))
        #expect(try !gate(.partial, .partial))       // wyświetlanie przechodzi na nowszy, ale bez automatycznej korekty
        #expect(try !gate(.partial, .empty))
        #expect(try gate(.partial, .complete))
        #expect(try gate(.complete, .complete))
        #expect(try !gate(.complete, .complete, finished: old)) // wznowiony starszy, nowszy już bieżący
    }

    @Test func reloadGivesTheSameSelection() throws {
        // Przeładowanie listy (np. powiązanie wydarzenia w trakcie przebiegu) i restart aplikacji wołają to samo od nowa.
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .partial, snapshot: try snapshot())
        #expect(RunSelection.of(session: s) == RunSelection.of(session: s))
        #expect(RunSelection.of(session: s).currentID == old)
    }

    @Test func languageComesFromTheRunSnapshot() throws {
        let polishPreset = try snapshot().preset
        let english = RunLanguage.of(try snapshot(language: .english), fallback: polishPreset)
        #expect(english == RunLanguage(language: .english, isAuto: false))
        #expect(RunLanguage.of(try autoSnapshot(), fallback: polishPreset) == RunLanguage(language: nil, isAuto: true))
        // Przebieg bez migawki: preset sesji.
        #expect(RunLanguage.of(nil, fallback: polishPreset) == RunLanguage(language: .polish, isAuto: false))
        #expect(RunLanguage.of(nil, fallback: try autoSnapshot().preset).isAuto)
        #expect(RunLanguage.of(nil, fallback: nil) == RunLanguage(language: nil, isAuto: false))
    }
}
