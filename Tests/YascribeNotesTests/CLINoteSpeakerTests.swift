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
    let raw = transcript([utt("raw words", .them)])
    let corrected = CorrectedTranscript(transcript: transcript([utt("corrected words", .them)]), model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    try JSONFile.save(raw, to: run.transcript)
    try JSONFile.save(corrected, to: run.corrected)
    let speakers = SpeakerDiarization(version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil,
        threshold: nil, minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil,
        segments: [.init(speaker: "voice", start: 0, end: 10)])
    try JSONFile.save(speakers, to: run.speakers)
    let stub = ChatStub { _ in "# Title\nbody" }
    for source in ["raw", "corrected"] {
        let output = session.appendingPathComponent("\(source).json")
        try await CLI.note([run.url.path, "https://example.com/v1", "model", "--language", "pl", "--out", output.path,
                            "--source", source], clientOverride: chatClient(stub))
        let call = try #require(stub.calls.last)
        #expect(call.user.contains("[[S1]]: \(source) words"))
        #expect(call.system.contains("Speakers: [[S1]] = Speaker 1."))
        #expect(call.system.contains("detected automatically"))
    }
}
