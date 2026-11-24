import Foundation
import Testing
@testable import YascribeTranscription

// TASK-127: kształt czasów z prawdziwej sesji (przerwa 0,92 s < Merger.utteranceGap, granica diaryzacji 149,13 → 149,80),
// słowa i klucze fikcyjne.
private let wordsA = [("alfa", 143.08, 144.5), ("beta", 144.6, 146.0), ("gamma", 146.1, 147.5), ("delta.", 147.6, 148.66)]
private let wordsB = [("Epsilon", 149.58, 151.0), ("zeta", 151.1, 155.0), ("eta", 155.1, 159.0), ("theta.", 159.1, 163.0)]

private func utterance(_ ws: [(String, Double, Double)], speaker: Speaker = .them, text: String? = nil,
                       approximate: Bool = false) -> Utterance {
    let words = ws.map { Word(text: $0.0, start: $0.1, end: $0.2) }
    return Utterance(speaker: speaker, start: words.first!.start, end: words.last!.end,
                     text: text ?? words.map(\.text).joined(separator: " "), words: words,
                     approximateTiming: approximate, languageMismatch: nil)
}
private func diarization(_ segments: [SpeakerDiarization.Segment]) -> SpeakerDiarization {
    SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil,
                       minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil, segments: segments)
}
/// Oba klucze ≥ 10 s mowy (filtr okruchów), granica jak w przykładzie.
private let boundary = [SpeakerDiarization.Segment(speaker: "A", start: 133.28, end: 149.13),
                        SpeakerDiarization.Segment(speaker: "B", start: 149.80, end: 162.84)]
private func labeled(_ us: [Utterance], _ segments: [SpeakerDiarization.Segment] = boundary) -> [Utterance] {
    Transcript(utterances: us, failedChunks: []).withSpeakerLabels(diarization(segments)).utterances
}

@Test func splitsAtDiarizationBoundary() {
    let parts = labeled([utterance(wordsA + wordsB)])
    #expect(parts.map(\.speakerKey) == ["A", "B"])
    #expect(parts.map(\.speakerLabel) == ["Speaker 1", "Speaker 2"])
    #expect(parts.map(\.start) == [143.08, 149.58])
    #expect(parts.map(\.end) == [148.66, 163.0])
    #expect(parts.map(\.text) == ["alfa beta gamma delta.", "Epsilon zeta eta theta."])
    #expect(parts.map(\.words.count) == [4, 4])
    #expect(parts.map { $0.part?.index } == [0, 0])
    #expect(parts.map { $0.part?.start } == [143.08, 143.08])
    #expect(parts.map { $0.part?.text } == Array(repeating: "alfa beta gamma delta. Epsilon zeta eta theta.", count: 2))
    #expect(parts.map(\.isFirstPart) == [true, false])
}

@Test func unsplitUtteranceHasNoPart() {
    let parts = labeled([utterance(wordsA)])
    #expect(parts.count == 1)
    #expect(parts[0].part == nil)
    #expect(parts[0].isFirstPart)
}

@Test func textOfPartsConcatenatesToSourceAfterCorrection() {
    // Ta sama liczba tokenów (podmiana słowa): cięcie po indeksie.
    let swapped = labeled([utterance(wordsA + wordsB, text: "Alfa beta Gamma delta. Epsilon Zeta eta theta.")])
    #expect(swapped.map(\.text) == ["Alfa beta Gamma delta.", "Epsilon Zeta eta theta."])
    // Usunięte słowo przed granicą i dodane za nią (liczba tokenów ta sama, treść przesunięta): wyrównanie LCS, nie indeks.
    let source = "alfa gamma delta. Epsilon i zeta eta theta."
    let aligned = labeled([utterance(wordsA + wordsB, text: source)])
    #expect(aligned.map(\.text) == ["alfa gamma delta.", "Epsilon i zeta eta theta."])
    #expect(aligned.map(\.text).joined(separator: " ") == source)
}

@Test func ambiguousBoundaryKeepsWholeUtterance() {
    let parts = labeled([utterance(wordsA + wordsB, text: "Całkiem inny tekst bez wspólnych słów")])
    #expect(parts.count == 1)
    #expect(parts[0].part == nil)
    #expect(parts[0].speakerKey == "B") // jak dotąd: klucz z większym pokryciem całej wypowiedzi
}

@Test func singleWordIslandDoesNotSplit() {
    let island = [SpeakerDiarization.Segment(speaker: "A", start: 133, end: 146.05),
                  SpeakerDiarization.Segment(speaker: "B", start: 146.05, end: 147.55),
                  SpeakerDiarization.Segment(speaker: "A", start: 147.55, end: 149.0),
                  SpeakerDiarization.Segment(speaker: "B", start: 150, end: 162)]
    let parts = labeled([utterance(wordsA)], island)
    #expect(parts.count == 1)
    #expect(parts[0].speakerKey == "A")
}

@Test func wordsWithoutOverlapFollowNeighbour() {
    // Słowo w ciszy diaryzacji (przed pierwszym odcinkiem i między odcinkami) dziedziczy klucz sąsiada.
    let gappy = [SpeakerDiarization.Segment(speaker: "A", start: 134, end: 146.05),
                 SpeakerDiarization.Segment(speaker: "B", start: 151.05, end: 170)]
    let early = [("zero", 130.0, 131.0)]
    let parts = labeled([utterance(early + wordsA + wordsB)], gappy)
    #expect(parts.map(\.text) == ["zero alfa beta gamma delta. Epsilon", "zeta eta theta."])
    #expect(parts.map(\.speakerKey) == ["A", "B"])
}

@Test func mergedGroupDoesNotSplit() {
    let merged = [SpeakerDiarization.Segment(speaker: "A", start: 133.28, end: 149.13),
                  SpeakerDiarization.Segment(speaker: "A", start: 149.80, end: 162.84, originalSpeaker: "B")]
    let parts = labeled([utterance(wordsA + wordsB)], merged)
    #expect(parts.count == 1)
    #expect(parts[0].part == nil)
}

@Test func approximateTimingAndMeAreNotSplit() {
    #expect(labeled([utterance(wordsA + wordsB, approximate: true)]).count == 1)
    let me = labeled([utterance(wordsA + wordsB, speaker: .me)])
    #expect(me.count == 1)
    #expect(me[0].speakerKey == nil)
}

@Test func numbersFollowSplit() {
    // B pierwszy raz w części (149,58), C później (200) — B dostaje 2, nie 3.
    let segments = boundary + [SpeakerDiarization.Segment(speaker: "C", start: 195, end: 210)]
    let later = utterance([("omega", 200.0, 201.0), ("psi", 201.1, 202.0)])
    let parts = labeled([utterance(wordsA + wordsB), later], segments)
    #expect(parts.map(\.speakerLabel) == ["Speaker 1", "Speaker 2", "Speaker 3"])
    #expect(parts.map { $0.part?.index } == [0, 0, nil])
    #expect(SpeakerLabels.numbers(for: Transcript(utterances: parts, failedChunks: [])) == ["A": 1, "B": 2, "C": 3])
}

@Test func partsKeepSourceIndexAfterEarlierUtterances() {
    let first = utterance([("jeden", 100.0, 101.0), ("dwa", 101.1, 102.0)], speaker: .me)
    let parts = labeled([first, utterance(wordsA + wordsB)])
    #expect(parts.count == 3)
    #expect(parts.map { $0.part?.index } == [nil, 1, 1])
}

@Test func speakerKeysKeepUtteranceCount() {
    let t = Transcript(utterances: [utterance(wordsA + wordsB)], failedChunks: [])
    #expect(SpeakerLabels.speakerKeys(for: t, diarization: diarization(boundary)).count == 1)
}

@Test func flagsAreCopiedToParts() {
    var u = utterance(wordsA + wordsB)
    u.hidden = true
    u.echoOfThem = true
    let parts = labeled([u])
    #expect(parts.map(\.hidden) == [true, true])
    #expect(parts.map(\.echoOfThem) == [true, true])
}
