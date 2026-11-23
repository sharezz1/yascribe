import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
@testable import YascribeTranscription
@testable import yascribe_cli
@testable import YascribeNotes

@Test func cliNoteUsesSpeakerLabelsForRawAndCorrected() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let run = RunDirectory(session: session, runID: "run")
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    let raw = transcript([utt("raw words", .them), utt("my words", .me)])
    let corrected = CorrectedTranscript(transcript: transcript([utt("corrected words", .them), utt("my words.", .me)]), model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    try JSONFile.save(raw, to: run.transcript)
    try JSONFile.save(corrected, to: run.corrected)
    let speakers = SpeakerDiarization(version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil,
        threshold: nil, minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil,
        segments: [.init(speaker: "voice", start: 0, end: 10)])
    try JSONFile.save(speakers, to: run.speakers)
    try TranscriptEdits(edits: [.init(index: 1, speaker: .me, start: 0, text: "edited by hand")]).save(run: run)
    let stub = ChatStub { _ in "# Title\n[[S1]] spoke" }
    for source in ["raw", "corrected"] {
        let output = session.appendingPathComponent("\(source).json")
        try await CLI.note([run.url.path, "https://example.com/v1", "model", "--language", "pl", "--out", output.path,
                            "--source", source], clientOverride: chatClient(stub))
        let call = try #require(stub.calls.last)
        #expect(call.user.contains("[[S1]]: \(source) words"))
        #expect(call.user.contains("edited by hand"))
        #expect(!call.user.contains("my words"))
        #expect(call.system.contains("Speakers: [[S1]] = Speaker 1."))
        #expect(call.system.contains("detected automatically"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let written = try decoder.decode(NoteSummary.self, from: Data(contentsOf: output))
        #expect(written.markdown == "Speaker 1 spoke")
    }
}

// TASK-119: CLI `note` nie wysyła ukrytej wypowiedzi do modelu — w obu wersjach, także gdy korekta ma inną liczbę wypowiedzi.
@Test func cliNoteDropsHiddenUtterances() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let run = RunDirectory(session: session, runID: "run")
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    try JSONFile.save(transcript([utt("hintergrund raw", .me, at: 1), utt("keep raw", .them, at: 3)]), to: run.transcript)
    let corrected = CorrectedTranscript(transcript: transcript([utt("hintergrund fixed", .me, at: 1), utt("keep fixed", .them, at: 3),
                                                                utt("extra", .them, at: 9)]),
                                        model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    try JSONFile.save(corrected, to: run.corrected)
    try TranscriptEdits(hidden: [.init(speaker: .me, start: 1)]).save(run: run)
    let stub = ChatStub { _ in "# Title\nok" }
    for source in ["raw", "corrected"] {
        try await CLI.note([run.url.path, "https://example.com/v1", "model", "--language", "pl", "--out",
                            session.appendingPathComponent("\(source).json").path, "--source", source], clientOverride: chatClient(stub))
        let call = try #require(stub.calls.last)
        #expect(!call.user.contains("hintergrund"))
        #expect(call.user.contains(source == "raw" ? "keep raw" : "keep fixed"))
    }
}
