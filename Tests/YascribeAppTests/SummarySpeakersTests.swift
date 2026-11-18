import Foundation
import Testing
@testable import YascribeApp
import YascribeNotes
@testable import YascribeTranscription

private func speakerItem(markdown: String, speakers: [String: String]?, names: [String: String]?, digest: String? = "current") -> SessionItem {
    let spoken = Transcript(utterances: [Utterance(speaker: .them, start: 1, end: 5, text: "hej", words: [], approximateTiming: false)], failedChunks: [])
    var item = SessionItem(url: URL(fileURLWithPath: "/tmp/summary-speakers"), startedAt: Date(timeIntervalSince1970: 1_700_000_000), transcript: spoken, runID: "run")
    var diarization = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                                         audioFingerprint: nil, createdAt: nil, segments: [.init(speaker: "a", start: 0, end: 20)])
    diarization.names = names
    item.speakers = diarization
    item.notes.summary = NoteSummary(title: "T", markdown: markdown, templateID: "standard", model: "m", context: "",
                                     generatedAt: Date(timeIntervalSince1970: 0), speakers: speakers)
    item.notes.summary?.speakersDigest = digest == "current" ? diarization.segmentsDigest : digest
    return item
}

@Test func summaryCopyResolvesSpeakerNames() {
    #expect(speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: ["a": "Ala"]).notesText == "- Ala ok")
    #expect(speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: nil).notesText == "- Speaker 1 ok")
}

@Test func oldSummaryIsCopiedVerbatim() {
    #expect(speakerItem(markdown: "- Ala ok [[S1]]", speakers: nil, names: ["a": "Ala"]).notesText == "- Ala ok [[S1]]")
}

@Test func archiveSourceUsesSpeakerNames() {
    let item = speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: ["a": "Ala"])
    let source = ArchiveIndex.Source(sessionID: item.id, title: item.title, myNotes: "", summary: item.notesText, transcript: nil)
    let renamed = speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: ["a": "Ola"])
    let other = ArchiveIndex.Source(sessionID: item.id, title: item.title, myNotes: "", summary: renamed.notesText, transcript: nil)
    #expect(source.fingerprint != other.fingerprint)
}

@Test func renamingASpeakerChangesTheLinkedNote() {
    let blocks = MarkdownBlocks.group("- [[S1]] ok")
    let ala = speakerItem(markdown: "", speakers: ["1": "a"], names: ["a": "Ala"]).speakerMarkers.linked(blocks)
    let ola = speakerItem(markdown: "", speakers: ["1": "a"], names: ["a": "Ola"]).speakerMarkers.linked(blocks)
    #expect(ala != ola)
}

@Test func redetectedSpeakersNeverGetANameFromTheNewDetection() {
    #expect(speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: ["a": "Ala"], digest: "older").notesText == "- Speaker 1 ok")
    #expect(speakerItem(markdown: "- [[S1]] ok", speakers: ["1": "a"], names: ["a": "Ala"], digest: nil).notesText == "- Speaker 1 ok")
}

@Test func speakerColorToleratesAnyNumber() {
    _ = UtteranceRow.color(number: 0)
    _ = UtteranceRow.color(number: -3)
}
