import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-109: ręczna poprawka segmentu — nakładka w obu wersjach i zapis przez AppModel.

private func u(_ speaker: Speaker, _ start: Double, _ text: String) -> Utterance {
    Utterance(speaker: speaker, start: start, end: start + 2, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

private func item(session: URL) -> SessionItem {
    var i = SessionItem(url: session, summary: nil, startedAt: Date(),
                        transcript: Transcript(utterances: [u(.them, 1, "helo Rokm"), u(.me, 4, "hi")], failedChunks: []), progress: nil)
    i.runID = "run"
    i.corrected = CorrectedTranscript(transcript: Transcript(utterances: [u(.them, 1, "Hello Rokm."), u(.me, 4, "Hi.")], failedChunks: []),
                                      model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    return i
}

@Suite @MainActor struct TranscriptEditsAppTests {
    @Test func editsApplyToBothVersionsButNotToMisalignedCorrection() {
        var i = item(session: URL(fileURLWithPath: "/nonexistent"))
        i.edits = TranscriptEdits(edits: [.init(index: 1, speaker: .me, start: 4, text: "Hey.")])
        #expect(i.transcript(corrected: false)?.utterances.map(\.text) == ["helo Rokm", "Hey."])
        #expect(i.transcript(corrected: true)?.utterances.map(\.text) == ["Hello Rokm.", "Hey."])
        #expect(i.uneditedTranscript(corrected: true)?.utterances[1].text == "Hi.")
        #expect(i.canEdit(corrected: true))
        i.corrected?.transcript.utterances.append(u(.them, 9, "extra"))
        #expect(i.transcript(corrected: true)?.utterances[1].text == "Hi.")
        #expect(!i.canEdit(corrected: true))
        #expect(i.canEdit(corrected: false))
        #expect(i.transcript(corrected: false)?.utterances[1].text == "Hey.")
    }

    @Test func editUtteranceRereadsFileRefusesCorruptAndStaleRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.path, 1)
        let model = AppModel()
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        let session = root.appendingPathComponent("session")
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        let stale = item(session: session)

        // Dwa zapisy z tej samej (starej) migawki: drugi nie kasuje pierwszego.
        #expect(model.editUtterance(stale, runID: "run", index: 0, corrected: true, text: "Hello, Rokm."))
        #expect(model.editUtterance(stale, runID: "run", index: 1, corrected: false, text: "hey"))
        #expect(TranscriptEdits.load(run: run)?.edits.map(\.text) == ["Hello, Rokm.", "hey"])

        // Szkic z innego przebiegu nie trafia do bieżącego.
        let other = RunDirectory(session: session, runID: "other")
        try FileManager.default.createDirectory(at: other.url, withIntermediateDirectories: true)
        #expect(!model.editUtterance(stale, runID: "other", index: 0, corrected: true, text: "x"))
        #expect(!FileManager.default.fileExists(atPath: other.edits.path))
        #expect(!model.editUtterance(stale, runID: "run", index: 5, corrected: true, text: "x"))
        // Korekta niezgodna z transkryptem: edycja tylko w Original, zapis w Corrected odmówiony.
        var misaligned = stale
        misaligned.corrected?.transcript.utterances.append(u(.them, 9, "extra"))
        #expect(!model.editUtterance(misaligned, runID: "run", index: 1, corrected: true, text: "nope"))
        #expect(TranscriptEdits.load(run: run)?.edits.map(\.text) == ["Hello, Rokm.", "hey"])

        // Tekst równy widocznemu (po słowniku) usuwa poprawkę zamiast tworzyć pozorną.
        model.dictionary = UserDictionary(terms: [DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")])])
        #expect(model.editUtterance(stale, runID: "run", index: 0, corrected: true, text: "Hello Nimbu."))
        #expect(TranscriptEdits.load(run: run)?.edits.map(\.index) == [1])

        // Uszkodzony plik: bez zapisu, bajty zostają, komunikat.
        try Data("{broken".utf8).write(to: run.edits)
        #expect(!model.editUtterance(stale, runID: "run", index: 0, corrected: true, text: "y"))
        #expect(try Data(contentsOf: run.edits) == Data("{broken".utf8))
        #expect(model.lastError?.hasPrefix("Couldn't save the edit") == true)
    }
}
