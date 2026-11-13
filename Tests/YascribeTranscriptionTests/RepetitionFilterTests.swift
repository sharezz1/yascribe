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

    /// Próg TTR 0,4 z compare.py przypięty na granicy: 3 różne słowa na 10, bez pętli n-gramów (każdy bigram raz).
    @Test func typeTokenRatioThresholdMatchesComparePy() {
        #expect(RepetitionFilter.isHallucinated("tak tak nie nie może może tak może nie tak"))
        #expect(!RepetitionFilter.isHallucinated("tak tak nie nie może może tak może nie jutro"))
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

extension RepetitionFilterTests {
    /// Próbka spike'u to prywatne transkrypcje w ignorowanym `docs/superpowers/`: parytet tylko lokalnie, czysty checkout go pomija.
    private static let loopSample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/superpowers/spikes/2026-11-12-task102-cohere/results/loop-sample.json")

    /// Zaakceptowany fałszywy alarm (8677/47) przypięty bez prywatnych danych.
    @Test func acceptedFalseAlarmStaysFlagged() {
        #expect(RepetitionFilter.isHallucinated("Ale nie, nie, nie, nie, nie, nie. Okej."))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: loopSample.path)))
    func parityWithSpikeIncludingAcceptedFalseAlarm() throws {
        struct Sample: Decodable {
            let session: String; let window: Int; let text: String; let prev: String; let heuristic: Bool
        }
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: Self.loopSample))
        #expect(samples.count == 30)
        var acceptedFalseAlarm = false
        for sample in samples {
            // Zaakceptowany przez hub fałszywy alarm: 8677/47 „nie, nie, nie…”. Progu nie zmieniamy.
            if sample.session == "8677", sample.window == 47 { acceptedFalseAlarm = true; #expect(sample.heuristic) }
            #expect(RepetitionFilter.isHallucinated(sample.text, previousText: sample.prev) == sample.heuristic,
                    "\(sample.session)/\(sample.window)")
        }
        #expect(acceptedFalseAlarm)
    }
}
