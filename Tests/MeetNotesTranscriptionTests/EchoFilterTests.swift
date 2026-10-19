import Foundation
import Testing
import MeetNotesProviders
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

private func u(_ speaker: Speaker, _ start: Double, _ end: Double, _ text: String) -> Utterance {
    Utterance(speaker: speaker, start: start, end: end, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

private let sentence = "W sensie ja zauważam że jest rzeczywiście coraz większa presja na mężczyznach jeśli chodzi o wygląd"

@Test func speakerEchoIsMarkedAndKeptOutOfNotes() {
    // Odbiór T13: ta sama wypowiedź jako Them (tap) i Me (mikrofon łapie głośniki).
    let out = EchoFilter.mark([u(.me, 0.2, 19.8, sentence), u(.them, 0.2, 19.8, sentence + ".")])
    #expect(out[0].echoOfThem == true && out[0].excludedFromNotes)
    #expect(out[1].echoOfThem == nil && !out[1].excludedFromNotes) // oryginał po stronie Them zostaje
}

@Test func echoOfAPartOfALongerUtteranceIsMarked() {
    // Drugi przypadek z odbioru: Me = pierwsze 21 słów z 60-słowowej wypowiedzi Them.
    let long = (1...60).map { "słowo\($0)" }.joined(separator: " ")
    let part = (1...21).map { "słowo\($0)" }.joined(separator: " ")
    let out = EchoFilter.mark([u(.them, 21.9, 47.6, long), u(.me, 21.9, 28.9, part)])
    #expect(out[1].echoOfThem == true)
}

@Test func genuineAnswerIsNotMarkedAsEcho() {
    let out = EchoFilter.mark([u(.them, 0, 10, sentence), u(.me, 2, 8, "Nie zgadzam się, bo moim zdaniem to wynika z mediów społecznościowych")])
    #expect(out[1].echoOfThem == nil)
}

@Test func shortOrDistantUtterancesAreNotMarked() {
    let short = EchoFilter.mark([u(.them, 0, 2, "tak dokładnie tak"), u(.me, 0, 2, "tak dokładnie tak")]) // 2 różne słowa < minWords
    #expect(short[1].echoOfThem == nil)
    let distant = EchoFilter.mark([u(.them, 0, 10, sentence), u(.me, 120, 130, sentence)]) // 2 minuty później to nie echo
    #expect(distant[1].echoOfThem == nil)
}

@Test func echoMarkIsIdempotentAndOldTranscriptsStillDecode() throws {
    let once = EchoFilter.mark([u(.them, 0, 10, sentence), u(.me, 0, 10, sentence)])
    #expect(EchoFilter.mark(once) == once)
    // Transkrypt zapisany przed filtrem (bez klucza `echoOfThem`) wczytuje się i da się oznaczyć.
    let old = #"{"utterances":[{"speaker":"them","start":0,"end":10,"text":"\#(sentence)","words":[],"approximateTiming":false},{"speaker":"me","start":0,"end":10,"text":"\#(sentence)","words":[],"approximateTiming":false}],"failedChunks":[]}"#
    let t = try JSONDecoder().decode(Transcript.self, from: Data(old.utf8))
    #expect(t.utterances.allSatisfy { $0.echoOfThem == nil })
    #expect(t.echoMarked().echoCount == 1 && t.languageFlagCount == 0)
}

@Test func mergeMarksTheMicrophoneEchoOfTheOtherSide() throws {
    // Potok: ta sama treść z dwóch ścieżek (system = Them, mikrofon = Me) → w transkrypcie echo jest oznaczone.
    func result(_ words: String) throws -> TranscriptionResult {
        let ws = words.split(separator: " ").enumerated().map { #"{"word":"\#($1)","start":\#(Double($0) * 0.5),"end":\#(Double($0) * 0.5 + 0.4)}"# }
        return try JSONDecoder().decode(TranscriptionResult.self, from: Data(#"{"text":"\#(words)","words":[\#(ws.joined(separator: ","))]}"#.utf8))
    }
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 0, sourceEnd: 160_000, chunkStart: 0)], length: 160_000)
    let text = "to jest ta sama wypowiedź która leci z głośników"
    let system = ChunkResult(track: "system", chunk: chunk, result: try result(text))
    let mic = ChunkResult(track: "mic_raw", chunk: chunk, result: try result(text))
    let speakers: [String: Speaker] = ["system": .them, "mic_raw": .me]
    let summary = SessionSummary(startedHostTime: 0, timebase: Timebase(numer: 1, denom: 1), tracks: [])
    let t = Merger.merge([system, mic], speakers: speakers, clock: SessionClock(summary: summary), language: .polish)
    #expect(t.utterances.filter { $0.speaker == .me }.allSatisfy { $0.echoOfThem == true })
    #expect(t.echoCount == 1)
}
