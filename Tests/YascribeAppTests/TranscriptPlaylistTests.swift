import Foundation
import Testing
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-131: mapowanie pozycja odtwarzania ↔ wiersz transkryptu, ukryte wypowiedzi i części podziału.

@Suite struct TranscriptPlaylistTests {
    private func u(_ speaker: Speaker, _ start: Double, _ end: Double, hidden: Bool = false) -> Utterance {
        var x = Utterance(speaker: speaker, start: start, end: end, text: "t", words: [], approximateTiming: true, languageMismatch: nil)
        if hidden { x.hidden = true }
        return x
    }

    private func list(_ us: [Utterance]) -> TranscriptPlaylist { TranscriptPlaylist(Transcript(utterances: us, failedChunks: [])) }

    @Test func rowAtPositionUsesRangeAndKeepsRowIndices() {
        let l = list([u(.me, 0, 2), u(.them, 3, 6), u(.me, 6, 8)])
        #expect(l.row(at: 1) == 0)
        #expect(l.row(at: 2.5) == nil) // cisza między wypowiedziami
        #expect(l.row(at: 3) == 1)
        #expect(l.row(at: 6) == 2) // koniec jest wyłączony, początek następnej wygrywa
        #expect(l.row(at: 8) == nil)
        #expect(l.duration == 8)
    }

    @Test func hiddenUtterancesAreSkippedButRowsStayAligned() {
        let l = list([u(.me, 0, 2), u(.them, 3, 6, hidden: true), u(.me, 7, 9)])
        #expect(l.entries.map(\.row) == [0, 2]) // wiersz 2 zostaje wierszem 2, nie 1
        #expect(l.row(at: 4) == nil)
        let first = l.entry(row: 0)!
        #expect(l.next(after: first, cursor: first.end)?.entry.row == 2)
        #expect(l.entry(row: 1) == nil)
    }

    @Test func splitPartsAreSeparateEntriesWithOwnRange() {
        // Podział (TASK-127): dwie części źródła 0 (me, them), potem wypowiedź źródła 1 — wiersze 0, 1, 2.
        var a = u(.me, 10, 12), b = u(.them, 12, 15), c = u(.me, 16, 18)
        a.part = UtterancePart(index: 0, start: 10, text: "a", isFirst: true); a.sourceIndex = 0
        b.part = UtterancePart(index: 0, start: 10, text: "b", isFirst: false); b.sourceIndex = 0
        c.sourceIndex = 1
        let l = list([a, b, c])
        #expect(l.row(at: 11) == 0)
        #expect(l.row(at: 13) == 1) // nie 0: zakres części, nie źródła
        #expect(l.row(at: 17) == 2)
    }

    @Test func startAtPositionInSilenceJumpsToNextUtteranceAndPastEndIsNil() {
        let l = list([u(.me, 0, 2), u(.them, 5, 6)])
        #expect(l.start(at: 1)?.entry.row == 0 && l.start(at: 1)?.from == 1)
        #expect(l.start(at: 3)?.entry.row == 1 && l.start(at: 3)?.from == 5)
        #expect(l.start(at: 6) == nil)
    }

    @Test func chainDoesNotRepeatOverlappingSpeech() {
        // Me 0–10 i Them 4–6 (cały w środku) i Them 8–14 (częściowo): po Me gra tylko ogon trzeciego.
        let l = list([u(.me, 0, 10), u(.them, 4, 6), u(.them, 8, 14)])
        let first = l.entry(row: 0)!
        let step = l.next(after: first, cursor: first.end)
        #expect(step?.entry.row == 2 && step?.from == 10)
        #expect(l.next(after: l.entry(row: 2)!, cursor: 14) == nil)
    }

    @Test func zeroLengthUtteranceGetsHalfSecond() {
        let l = list([u(.me, 5, 5)])
        #expect(l.entries.first?.end == 5.5)
    }
}
