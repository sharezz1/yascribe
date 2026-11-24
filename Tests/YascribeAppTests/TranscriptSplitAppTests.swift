import Foundation
import Testing
import YascribeNotes
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-127: wiersze części jednej wypowiedzi — edycja, ukrycie i liczniki idą po źródle.

private func shown(hiddenFirst: Bool = false) -> Transcript {
    let words = [("alfa", 143.08, 144.5), ("beta", 144.6, 146.0), ("gamma", 146.1, 147.5), ("delta.", 147.6, 148.66),
                 ("Epsilon", 149.58, 151.0), ("zeta", 151.1, 155.0), ("eta", 155.1, 159.0), ("theta.", 159.1, 163.0)]
        .map { Word(text: $0.0, start: $0.1, end: $0.2) }
    let me = Utterance(speaker: .me, start: 100, end: 101, text: "jeden dwa", words: [], approximateTiming: true, languageMismatch: nil)
    let them = Utterance(speaker: .them, start: 143.08, end: 163, text: words.map(\.text).joined(separator: " "), words: words,
                         approximateTiming: false, languageMismatch: nil)
    let raw = Transcript(utterances: [me, them], failedChunks: [])
    let d = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                               audioFingerprint: nil, createdAt: nil,
                               segments: [.init(speaker: "A", start: 133.28, end: 149.13), .init(speaker: "B", start: 149.80, end: 162.84)])
    let edits = hiddenFirst ? TranscriptEdits(hidden: [.init(me)]) : nil
    // Widok bierze pełny transkrypt (`includeHidden: true`): indeks części to indeks `edits.json` także za ukrytą wypowiedzią.
    return MeetingArchive.displayTranscript(raw: raw, corrected: nil, edits: edits, useCorrected: false,
                                            rules: ReplacementRules(UserDictionary()), speakers: d, includeHidden: true)!
}

@Test @MainActor func editTargetIsWholeSourceInFirstPartOnly() throws {
    let t = shown(hiddenFirst: true)
    #expect(t.utterances.count == 3)
    let first = try #require(TranscriptTab.editTarget(1, t.utterances[1]))
    #expect(first.index == 1)
    #expect(first.start == 143.08)
    #expect(first.text == "alfa beta gamma delta. Epsilon zeta eta theta.")
    #expect(TranscriptTab.editTarget(2, t.utterances[2]) == nil)
    #expect(TranscriptTab.editTarget(0, t.utterances[0])?.index == 0)
}

@Test @MainActor func hidingAndCountingGoBySource() {
    let t = shown()
    #expect(TranscriptTab.hiddenKeys([1, 2], in: t) == [TranscriptEdits.Hidden(speaker: .them, start: 143.08)])
    #expect(TranscriptTab.hiddenKeys([2, 0, 9], in: t).count == 2)
    #expect(TranscriptTab.sourceCount([1, 2], in: t) == 1)
    #expect(TranscriptTab.sourceCount(Set([0, 1, 2]), in: t) == 2)
    var hidden = t
    for i in hidden.utterances.indices { hidden.utterances[i].hidden = true }
    #expect(TranscriptTab.hiddenSourceCount(hidden) == 2)
}
