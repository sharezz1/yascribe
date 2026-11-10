import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

@Suite struct CorrectionHistoryTests {
    private func makeRun() throws -> RunDirectory {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID().uuidString)")
        let run = RunDirectory(session: session, runID: "2026-11-10T08-51-29Z-82ab")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        return run
    }

    private func writeCorrection(_ run: RunDirectory, model: String, text: String, system: String) throws {
        let t = transcript([utt(text)])
        try JSONFile.save(CorrectedTranscript(transcript: t, model: model, batches: 1, failedBatches: 0, rejectedLines: 0), to: run.corrected, createParents: false)
        try "terms".write(to: run.url.appendingPathComponent("vocabulary.txt"), atomically: true, encoding: .utf8)
        try system.write(to: run.url.appendingPathComponent("correction-system.txt"), atomically: true, encoding: .utf8)
    }

    @Test func archivesCurrentCorrectionWithTracesAndKeepsItInPlace() throws {
        let run = try makeRun()
        try writeCorrection(run, model: "org/qwen:4b", text: "stara wersja", system: "prompt v1")
        #expect(CorrectionHistory.archive(run: run) == nil)
        let entry = try #require(CorrectionHistory.entries(of: run).first)
        #expect(entry.lastPathComponent.hasSuffix("-org_qwen_4b"))
        let archived = try JSONFile.load(CorrectedTranscript?.self, from: entry.appendingPathComponent("corrected.json"), default: nil)
        #expect(archived?.transcript.utterances.first?.text == "stara wersja")
        #expect(try String(contentsOf: entry.appendingPathComponent("correction-system.txt"), encoding: .utf8) == "prompt v1")
        #expect(try String(contentsOf: entry.appendingPathComponent("vocabulary.txt"), encoding: .utf8) == "terms")
        #expect(FileManager.default.fileExists(atPath: run.corrected.path)) // kopia, nie przeniesienie
    }

    @Test func overwritingAfterArchiveKeepsBothVersions() throws {
        let run = try makeRun()
        try writeCorrection(run, model: "qwen", text: "wersja 1", system: "p1")
        #expect(CorrectionHistory.archive(run: run) == nil)
        try writeCorrection(run, model: "gemma", text: "wersja 2", system: "p2")
        let entry = try #require(CorrectionHistory.entries(of: run).first)
        let old = try JSONFile.load(CorrectedTranscript?.self, from: entry.appendingPathComponent("corrected.json"), default: nil)
        let now = try JSONFile.load(CorrectedTranscript?.self, from: run.corrected, default: nil)
        #expect(old?.transcript.utterances.first?.text == "wersja 1" && old?.model == "qwen")
        #expect(now?.transcript.utterances.first?.text == "wersja 2" && now?.model == "gemma")
    }

    @Test func sameCorrectionIsArchivedOnlyOnce() throws {
        let run = try makeRun()
        try writeCorrection(run, model: "qwen", text: "x", system: "p")
        #expect(CorrectionHistory.archive(run: run) == nil)
        #expect(CorrectionHistory.archive(run: run) == nil)
        #expect(CorrectionHistory.entries(of: run).count == 1)
    }

    @Test func nothingToArchiveWithoutCorrection() throws {
        let run = try makeRun()
        #expect(CorrectionHistory.archive(run: run) == nil)
        #expect(CorrectionHistory.entries(of: run).isEmpty)
    }
}
