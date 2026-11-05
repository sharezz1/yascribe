import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

private final class ModelHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var models: [String] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        lock.withLock { seen.append(body["model"] as? String ?? "") }
        return (Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// TASK-89: „Transcribe" w oknie Improve ma puścić korektę modelem z okna, nie z presetu.
@Suite("TranscribeCorrectionChoice") @MainActor struct TranscribeCorrectionChoiceTests {
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    fileprivate let http = ModelHTTP()
    let runID = "2026-10-23T09-00-00Z-bbbb"

    var preset: Preset {
        Preset(name: "Test", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "asr"),
               correction: RoleAssignment(providerID: provider.id, model: "preset-corr"))
    }

    var transcript: Transcript {
        Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])
    }

    func run(chosen: String) async throws -> (models: [String], override: RoleOverride?) {
        defer { try? FileManager.default.removeItem(at: session) }
        let run = RunDirectory(session: session, runID: runID)
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        try JSONFile.save(transcript, to: run.transcript)
        let preset = preset, provider = provider, http = http
        let model = NotesModel()
        model.presetFor = { _ in preset }
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        let item = SessionItem(url: session, startedAt: Date(), transcript: transcript, runID: runID)
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id
        draft.correctModel = chosen
        #expect(draft.persistCorrectionChoice(item: item, notes: model, preset: preset.correction))
        let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
        await model.afterTranscription(sessionURL: session, runID: runID, snapshot: snapshot, transcript: transcript)
        return (http.models, NotesStore(session: session).readMeta().modelOverrides?.correction)
    }

    @Test func chosenCorrectionModelRunsAfterTranscription() async throws {
        let (models, _) = try await run(chosen: "picked-corr")
        #expect(models.contains("picked-corr"))
        #expect(!models.contains("preset-corr"))
    }

    @Test func choiceEqualToPresetStaysPreset() async throws {
        let (models, override) = try await run(chosen: "preset-corr")
        #expect(models.contains("preset-corr"))
        #expect(override == nil)
    }

    @Test func incompleteChoiceIsFlagged() {
        let draft = TranscriptModelsDraft()
        #expect(!draft.correctionIncomplete)
        draft.correctProviderID = provider.id
        #expect(draft.correctionIncomplete)
        draft.correctModel = "m"
        #expect(!draft.correctionIncomplete)
    }
}
