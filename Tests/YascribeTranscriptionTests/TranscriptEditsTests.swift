import Foundation
import Testing
@testable import YascribeTranscription

// TASK-109: ręczne poprawki segmentów jako nakładka `runs/<runID>/edits.json`.

private func u(_ speaker: Speaker, _ start: Double, _ text: String) -> Utterance {
    Utterance(speaker: speaker, start: start, end: start + 2, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

private let sample = Transcript(utterances: [u(.them, 1, "helo there"), u(.me, 1, "hi"), u(.them, 5, "bye")], failedChunks: [])

private func edit(_ i: Int, _ text: String, in t: Transcript = sample) -> TranscriptEdits {
    TranscriptEdits().setting(text, at: i, of: t.utterances[i], original: t.utterances[i].text)
}

@Suite struct TranscriptEditsTests {
    @Test func appliesAtIndex() {
        #expect(edit(0, "hello there").apply(to: sample).utterances.map(\.text) == ["hello there", "hi", "bye"])
        #expect(edit(1, "hey").apply(to: sample).utterances.map(\.text) == ["helo there", "hey", "bye"])
    }

    @Test func skipsWhenSpeakerOrStartDiffer() {
        var other = sample
        other.utterances[2].speaker = .me
        #expect(edit(2, "x").apply(to: other).utterances[2].text == "bye")
        other = sample
        other.utterances[2].start = 5.002
        #expect(edit(2, "x").apply(to: other).utterances[2].text == "bye")
        other.utterances[2].start = 5.0005
        #expect(edit(2, "x").apply(to: other).utterances[2].text == "x")
        #expect(!edit(2, "x").isEdited(index: 2, in: Transcript(utterances: [], failedChunks: [])))
    }

    @Test func secondDuplicateLeavesFirstUntouched() {
        let t = Transcript(utterances: [u(.them, 3, "a"), u(.them, 3, "b")], failedChunks: [])
        let e = edit(1, "z", in: t)
        #expect(e.apply(to: t).utterances.map(\.text) == ["a", "z"])
        #expect(!e.isEdited(index: 0, in: t))
        #expect(e.isEdited(index: 1, in: t))
    }

    @Test func settingOriginalRemovesEdit() {
        let back = edit(0, "hello there").setting("  helo there\n", at: 0, of: sample.utterances[0], original: "helo there")
        #expect(back.edits.isEmpty)
        #expect(!back.isEdited(index: 0, in: sample))
    }

    @Test func settingEmptyKeepsEdits() {
        let e = edit(0, "hello there")
        #expect(e.setting(" \n ", at: 0, of: sample.utterances[0], original: "helo there") == e)
    }

    @Test func settingReplacesExistingWithoutDuplicate() {
        let e = edit(0, "hello there").setting(" hello, there ", at: 0, of: sample.utterances[0], original: "helo there")
        #expect(e.edits == [.init(index: 0, speaker: .them, start: 1, text: "hello, there")])
        #expect(e.isEdited(index: 0, in: sample))
        #expect(!e.isEdited(index: 1, in: sample))
    }

    @Test func saveLoadRoundTripAndCorruptFile() throws {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        let run = RunDirectory(session: session, runID: "r1")
        #expect(TranscriptEdits.load(run: run) == nil)
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        #expect(try TranscriptEdits.loadForEditing(run: run) == nil)
        let e = edit(1, "hey")
        try e.save(run: run)
        #expect(TranscriptEdits.load(run: run) == e)
        try "{broken".write(to: run.edits, atomically: true, encoding: .utf8)
        #expect(TranscriptEdits.load(run: run) == nil)
        #expect(throws: (any Error).self) { try TranscriptEdits.loadForEditing(run: run) }
    }
}
