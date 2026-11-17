import Foundation
import Testing
import YascribeLocalASR
@testable import YascribeTranscription
@testable import YascribeApp

private func utterance(_ speaker: Speaker, label: String? = nil) -> Utterance {
    var u = Utterance(speaker: speaker, start: 0, end: 1, text: "x", words: [], approximateTiming: false)
    u.speakerLabel = label
    return u
}

/// Kolumna mówcy i kopiowanie mają ten sam tekst (§4.4); „Me" nie dostaje etykiety.
@Test func speakerColumnNameFollowsLabel() {
    #expect(utterance(.them).speakerName == "Them")
    #expect(utterance(.them, label: "A").speakerName == "Them A")
    #expect(utterance(.them, label: "AA").speakerName == "Them AA")
    #expect(utterance(.me, label: "A").speakerName == "Me")
    #expect(TranscriptActions.copyLine(utterance(.them, label: "A")) == "[0:00:00] Them A: x")
}

@Test func speakerModelCardTitleAndAction() {
    #expect(SpeakerModelCardText.title(status: .missing, progress: nil) == "Not downloaded")
    #expect(SpeakerModelCardText.title(status: .incomplete, progress: nil) == "Incomplete")
    #expect(SpeakerModelCardText.title(status: .ready, progress: nil) == "Ready")
    #expect(SpeakerModelCardText.title(status: .missing, progress: 0.414) == "Downloading 41%")
    #expect(SpeakerModelCardText.primaryLabel(status: .ready) == "Remove")
    #expect(SpeakerModelCardText.primaryLabel(status: .missing) == "Download")
    #expect(SpeakerModelCardText.primaryLabel(status: .incomplete) == "Download")
}

/// Link „License" z karty otwiera notę z paczki: nazwa w kodzie musi odpowiadać plikowi w `Resources/ThirdPartyNotices` (R14).
@Test func speakerNoticeFileExistsUnderTheNameTheCardOpens() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let note = root.appendingPathComponent("Resources/ThirdPartyNotices/\(SpeakerModelCardText.noticeName).txt")
    let text = try String(contentsOf: note, encoding: .utf8)
    for needle in [DiarizerManifest.revision, "https://creativecommons.org/licenses/by/4.0/", "pyannote", "WeSpeaker", "BUT Speech@FIT", "Fluid Inference", "Core ML"] {
        #expect(text.contains(needle), "nota nie zawiera: \(needle)")
    }
}
