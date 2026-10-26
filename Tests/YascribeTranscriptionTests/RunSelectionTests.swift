import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

/// R23 (Task 10b): bieżący przebieg = najnowszy ukończony, niepusty i bez luk; najnowsza próba osobno.
@Suite struct RunSelectionTests {
    // Nazwy muszą pasować do wzorca `RunDirectory.runIDs` — inaczej filtr pominie je po cichu.
    let old = "2026-10-21T10-00-00Z-aaaa"
    let new = "2026-10-23T09-00-00Z-bbbb"

    /// `noFinish`: transkrypt i `run.json` bez `finishedAt`; `legacy`: sam `transcript.json` (bez `run.json` i `input.json`).
    enum State { case running, thrown, partial, empty, complete, noFinish, legacy }

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
        if state == .legacy { return try JSONFile.save(Transcript(utterances: [line(text)], failedChunks: []), to: dir.transcript) }
        try JSONFile.save(RunInput(snapshot: s, gate: EnergyGate().config, maxChunkSeconds: 59, crosstalk: CrosstalkFilter(),
                                   trackFrames: ["system": 100]), to: dir.input)
        if state == .running { return }
        let gap = ChunkFailure(track: "system", index: 0, start: 0, end: 59, error: "offline")
        let t = Transcript(utterances: state == .empty ? [] : [line(text)], failedChunks: state == .partial ? [gap] : [])
        try JSONFile.save(t, to: dir.transcript)
        try JSONFile.save(RunMetadata(runID: id, snapshot: s, startedAt: Date(), finishedAt: state == .noFinish ? nil : Date(), chunkCount: 1, requestCount: 1,
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

    @Test func runWithoutFinishedAtIsNotPromoted() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .noFinish, snapshot: try snapshot())
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.notPromoted?.reason == .unfinished)
        #expect(!RunSelection.shouldPostProcess(session: s, runID: new))
    }

    @Test func garbageFilesAreTreatedAsUnavailable() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot(), text: "old")
        try write(s, new, .complete, snapshot: try snapshot())
        let dir = RunDirectory(session: s, runID: new)
        try Data("{not json".utf8).write(to: dir.transcript)
        try Data("garbage".utf8).write(to: dir.metadata)
        try Data("[]".utf8).write(to: dir.input)
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old)
        #expect(sel.transcript?.utterances.first?.text == "old")
        #expect(sel.notPromoted == RunSelection.Attempt(snapshot: nil, reason: .unfinished))
        // Sam uszkodzony przebieg: najnowszy katalog, bez transkryptu i migawki.
        let t = try session()
        try write(t, new, .thrown, snapshot: try snapshot())
        try Data("{".utf8).write(to: RunDirectory(session: t, runID: new).transcript)
        let lone = RunSelection.of(session: t)
        #expect(lone.currentID == new && lone.transcript == nil && lone.snapshot == nil)
    }

    @Test func legacyRunWithoutMetadataIsSelectableByFallback() throws {
        let s = try session()
        try write(s, old, .legacy, snapshot: try snapshot(), text: "legacy")
        let sel = RunSelection.of(session: s)
        #expect(sel.currentID == old && !sel.currentIsComplete && sel.snapshot == nil)
        #expect(sel.transcript?.utterances.first?.text == "legacy")
        #expect(RunSelection.shouldPostProcess(session: s, runID: old))
        // Obok ukończonego nowszego — nowszy.
        try write(s, new, .complete, snapshot: try snapshot())
        #expect(RunSelection.of(session: s).currentID == new)
    }

    @Test func resumedRejectedAttemptPromotesAndPostProcessesOnce() throws {
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .partial, snapshot: try snapshot(language: .english))
        #expect(!RunSelection.shouldPostProcess(session: s, runID: new))
        // „Resume Transcription with …": ten sam katalog kończy się bez luk.
        try write(s, new, .complete, snapshot: try snapshot(language: .english))
        #expect(RunSelection.of(session: s).currentID == new)
        #expect(RunSelection.shouldPostProcess(session: s, runID: new))
        #expect(!RunSelection.shouldPostProcess(session: s, runID: old))
    }

    @Test func olderCorrectionCannotTitleNewCurrentRun() throws {
        // A zakwalifikowany, korekta trwa; w tym czasie B kończy się i zostaje bieżącym — bramka przed autotytułem A: nie.
        let s = try session()
        try write(s, old, .complete, snapshot: try snapshot())
        #expect(RunSelection.shouldPostProcess(session: s, runID: old)) // start łańcucha A
        try write(s, new, .complete, snapshot: try snapshot(language: .english))
        #expect(!RunSelection.shouldPostProcess(session: s, runID: old)) // autotytuł A
        #expect(RunSelection.shouldPostProcess(session: s, runID: new))
    }

    @Test func retryCorrectionUsesSelectedRunLanguageAfterReload() throws {
        // `retryCorrection` = `RunLanguage.of(item.runSnapshot, fallback: preset)`, a `runSnapshot` pochodzi z `RunSelection.of`.
        let s = try session()
        let sessionPreset = try snapshot().preset // preset.json sesji: polski
        try write(s, old, .complete, snapshot: try snapshot())
        try write(s, new, .complete, snapshot: try snapshot(language: .english))
        for _ in 0..<2 { #expect(RunLanguage.of(RunSelection.of(session: s).snapshot, fallback: sessionPreset).language == .english) }
        let t = try session()
        try write(t, old, .complete, snapshot: try snapshot())
        try write(t, new, .complete, snapshot: try autoSnapshot())
        #expect(RunLanguage.of(RunSelection.of(session: t).snapshot, fallback: sessionPreset) == RunLanguage(language: nil, isAuto: true))
    }

    @Test func olderCorrectionFailureCannotOverwriteNewerEarlyFailure() {
        // A poprawia; B (nowy bieżący) zaczyna i od razu pada bez klienta; potem pada A.
        var ops = RunOperations()
        let a = ops.start(session: "s", runID: old)
        let b = ops.start(session: "s", runID: new)                 // bilet przed wczesnym wyjściem
        #expect(ops.finish(b).ownsMessage)                           // B zapisuje swoją porażkę
        #expect(!ops.finish(a).ownsMessage)                          // A nie nadpisuje
        #expect(!ops.isActive("s"))
        // Bez wyścigu: jedyna korekta kończy się jako właściciel i publikuje.
        let only = ops.start(session: "s", runID: old)
        #expect(ops.finish(only) == RunOperations.Outcome(ownsMessage: true, mayPublish: true))
    }

    @Test func twoCorrectionsOfOneRunKeepTheNewerResult() {
        // F2: dwie korekty tego samego przebiegu kończą się odwrotnie — `corrected.json` i ślad słownika zostają z nowszej.
        var ops = RunOperations()
        let first = ops.start(session: "s", runID: old)
        let second = ops.start(session: "s", runID: old)
        #expect(ops.finish(second) == RunOperations.Outcome(ownsMessage: true, mayPublish: true))
        #expect(ops.finish(first) == RunOperations.Outcome(ownsMessage: false, mayPublish: false))
        // Kolejność zwykła: starsza kończy pierwsza i też nie publikuje (nowsza i tak nadpisze), nowsza publikuje.
        let x = ops.start(session: "s", runID: old), y = ops.start(session: "s", runID: old)
        #expect(!ops.finish(x).mayPublish)
        #expect(ops.finish(y).mayPublish)
        // Inny przebieg i inna sesja się nie blokują.
        let p = ops.start(session: "s", runID: old), q = ops.start(session: "s", runID: new), r = ops.start(session: "t", runID: old)
        #expect(ops.finish(q).mayPublish && ops.finish(r).mayPublish && ops.finish(p).mayPublish)
    }

    @Test func olderOperationKeepsTheSessionBusyAfterNewerEnds() {
        // F3: A trwa, B kończy się wcześniej — sesja wciąż zajęta (blokada przenoszenia), dopóki A nie skończy.
        var ops = RunOperations()
        let a = ops.start(session: "s", runID: old)
        let b = ops.start(session: "s", runID: new)
        let other = ops.start(session: "t", runID: old)
        _ = ops.finish(b)
        #expect(ops.isActive("s") && ops.sessions == ["s", "t"])
        _ = ops.finish(other)
        #expect(ops.sessions == ["s"])
        _ = ops.finish(a)
        #expect(!ops.isActive("s") && ops.sessions.isEmpty)
        // Ta sama operacja dwa razy (np. dwa autotytuły jednej sesji): pierwszy koniec nie zwalnia sesji.
        let t1 = ops.start(session: "s", runID: new), t2 = ops.start(session: "s", runID: new)
        _ = ops.finish(t1)
        #expect(ops.isActive("s"))
        _ = ops.finish(t2)
        #expect(!ops.isActive("s"))
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

/// F7 (R26 odwołane): identyfikatory przebiegów ściśle rosnące w sesji — o kolejności nigdy nie decyduje losowy sufiks.
@Suite struct RunIDTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-23T09:00:00Z")! + 0.7

    @Test func nextRunIDIsStrictlyIncreasing() throws {
        let first = RunDirectory.nextRunID(latest: nil, now: now, suffix: "ffff")
        #expect(first == "2026-10-23T09-00-00Z-ffff")
        // Próba 1 pada od razu (błąd HTTP, CAF); próba 2 w tej samej sekundzie z „mniejszym" sufiksem — i tak nowsza.
        let second = RunDirectory.nextRunID(latest: first, now: now, suffix: "0000")
        #expect(second == "2026-10-23T09-00-01Z-0000" && second > first)
        // Najnowszy istniejący w przyszłości (zegar cofnięty, restart): następna sekunda po nim, także przez granicę minuty.
        #expect(RunDirectory.nextRunID(latest: "2026-10-23T10-00-59Z-aaaa", now: now, suffix: "0000") == "2026-10-23T10-01-00Z-0000")
        // Starszy najnowszy: zwykły znacznik „teraz".
        #expect(RunDirectory.nextRunID(latest: "2026-10-23T08-59-00Z-ffff", now: now, suffix: "0000") == "2026-10-23T09-00-00Z-0000")
        // Po restarcie z dysku: nowy katalog przechodzi filtr `runIDs` i jest najnowszą próbą.
        let s = FileManager.default.temporaryDirectory.appendingPathComponent("runid-\(UUID().uuidString)")
        for id in [first, second] { try FileManager.default.createDirectory(at: RunDirectory(session: s, runID: id).url, withIntermediateDirectories: true) }
        let third = RunDirectory.nextRunID(latest: RunDirectory.latestRunID(in: s), now: now, suffix: "0000")
        try FileManager.default.createDirectory(at: RunDirectory(session: s, runID: third).url, withIntermediateDirectories: true)
        #expect(RunDirectory.runIDs(in: s) == [first, second, third])
    }
}
