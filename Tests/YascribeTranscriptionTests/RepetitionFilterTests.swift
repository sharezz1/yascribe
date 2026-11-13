import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

@Suite struct RepetitionFilterTests {
    @Test func detectsShortWordAndPhraseLoopsFromSpike() {
        for text in ["Tak, tak, tak, tak.", "sp sp sp sp sp sp sp sp", "Dla mnie to nie jest łatwe. Dla mnie to nie jest łatwe. Dla mnie to nie jest łatwe.", "no tak no tak no tak", "to jest ważne to jest ważne to jest ważne", "raz dwa trzy cztery raz dwa trzy cztery raz dwa trzy cztery"] {
            #expect(RepetitionFilter.isHallucinated(text), "\(text)")
        }
    }

    @Test func normalSpeechAndQuotedPhrasesRemainUnflagged() {
        for text in ["Tak. Tak. Tak. Zgadzam się na tę zmianę.", "Nie, nie. Dzisiaj podejmujemy decyzję o wdrożeniu.", "W umowie jest cytat wszystkie prawa zastrzeżone i trzeba go zachować.", "Dla mnie to nie jest łatwe, ale decyduję o wdrożeniu jutro.", ""] {
            #expect(!RepetitionFilter.isHallucinated(text), "\(text)")
        }
    }

    @Test func detectsRepeatedPhrasesAcrossWindowsWithNormalization() {
        #expect(RepetitionFilter.isHallucinated("Dla mnie to nie jest łatwe.", previousText: "DLA MNIE TO NIE JEST ŁATWE!"))
        #expect(RepetitionFilter.isHallucinated("Nowy wstęp i dla mnie to nie jest łatwe teraz.", previousText: "Poprzedni wstęp dla mnie to nie jest łatwe wcześniej."))
        #expect(!RepetitionFilter.isHallucinated("Tak tak", previousText: "Tak tak"))
        #expect(!RepetitionFilter.isHallucinated("To jest nowa decyzja o środowej premierze.", previousText: "To jest dyskusja o piątkowej premierze."))
    }

    @Test func mergerPreservesFlagsWithWordTimingsWithoutFlaggingTheNeighbor() {
        let first = Chunk(index: 0, segments: [.init(sourceStart: 0, sourceEnd: 16_000, chunkStart: 0)], length: 16_000)
        let second = Chunk(index: 1, segments: [.init(sourceStart: 16_000, sourceEnd: 32_000, chunkStart: 0)], length: 16_000)
        let results = [ChunkResult(track: "system", chunk: first, result: .init(text: "pętla", words: [.init(word: "pętla", start: 0, end: 1)]), suspectedHallucination: true),
                       ChunkResult(track: "system", chunk: second, result: .init(text: "decyzja", words: [.init(word: "decyzja", start: 0, end: 1)]))]
        let clock = SessionClock(summary: .init(startedHostTime: 0, timebase: .init(numer: 1, denom: 1)))
        let transcript = Merger.merge(results, speakers: ["system": .them], clock: clock, language: nil)
        #expect(transcript.utterances.map(\.text) == ["pętla", "decyzja"])
        #expect(transcript.utterances.map(\.suspectedHallucination) == [true, nil])
        #expect(transcript.utterances.map(\.excludedFromNotes) == [true, false])
    }

    @Test func oldChunkAndUtteranceDecodeWithNoFlag() throws {
        let chunk = Chunk(index: 0, segments: [.init(sourceStart: 0, sourceEnd: 16_000, chunkStart: 0)], length: 16_000)
        let old = ChunkResult(track: "system", chunk: chunk, result: .init(text: "tekst", words: []))
        #expect(try JSONDecoder().decode(ChunkResult.self, from: JSONEncoder().encode(old)).suspectedHallucination == nil)
        let utterance = Utterance(speaker: .them, start: 0, end: 1, text: "tekst", words: [], approximateTiming: true)
        #expect(try JSONDecoder().decode(Utterance.self, from: JSONEncoder().encode(utterance)).suspectedHallucination == nil)
    }
}
