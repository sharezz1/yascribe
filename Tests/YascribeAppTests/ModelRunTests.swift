import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

/// Zapisuje model każdego żądania; odpowiedź „ok", opcjonalnie z opóźnieniem 300 ms.
private final class RecordingHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var models: [String] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        lock.withLock { seen.append(body["model"] as? String ?? "") }
        try await Task.sleep(for: .milliseconds(300))
        let data = Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class Reports { var messages: [String] = [] }

@Suite("ModelRun") @MainActor struct ModelRunTests {
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    fileprivate let http = RecordingHTTP()
    fileprivate let reports = Reports()
    let text = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])

    var preset: Preset {
        Preset(name: "Test", language: .polish, asr: nil, correction: RoleAssignment(providerID: provider.id, model: "preset-corr"),
               summary: RoleAssignment(providerID: provider.id, model: "preset-sum"))
    }

    func makeModel() -> NotesModel {
        let model = NotesModel()
        let preset = preset, provider = provider, http = http, reports = reports
        model.presetFor = { _ in preset }
        model.presetsInfo = { ([preset], preset.id) }
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        model.report = { reports.messages.append($0) }
        return model
    }

    func item(runID: String? = "run", transcript: Transcript? = nil, corrected: CorrectedTranscript? = nil) -> SessionItem {
        SessionItem(url: session, startedAt: Date(), transcript: transcript ?? text, runID: runID, corrected: corrected)
    }

    func draft(_ model: String, thinking: Bool? = nil) -> ModelDraft { .custom(RoleOverride(providerID: provider.id, model: model, thinking: thinking)) }
    func createSession() throws { try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true) }
    var saved: ModelOverrides? { NotesStore(session: session).readMeta().modelOverrides }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func setOverrideReturnsFalseAndReportsWhenSessionMissing() {
        let model = makeModel()
        #expect(!model.setOverride(.correction, RoleOverride(providerID: provider.id, model: "a"), item: item()))
        #expect(!reports.messages.isEmpty)
    }

    @Test func setOverridePersistsAndReturnsTrue() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        #expect(makeModel().setOverride(.correction, RoleOverride(providerID: provider.id, model: "a"), item: item()))
        #expect(saved?.correction?.model == "a")
    }

    @Test func improveTranscriptSaveFailureStartsNothingThenRetrySucceeds() async throws {
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(!model.improveTranscript(item(), draft: draft("A")))
        #expect(!model.isCorrecting(item().id))
        try createSession()
        #expect(model.improveTranscript(item(), draft: draft("A")))
        try await waitUntil { !model.isCorrecting(item().id) }
        #expect(http.models == ["A"])
    }

    @Test func improveTranscriptUsesDraftModelNotStaleItemOverride() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(model.improveTranscript(item(), draft: draft("draft")))
        try await waitUntil { !model.isCorrecting(item().id) }
        #expect(http.models == ["draft"])
        #expect(saved?.correction?.model == "draft")
    }

    @Test func improveTranscriptPresetDraftClearsOverrideAndUsesPresetModel() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let old = RoleOverride(providerID: provider.id, model: "old")
        try NotesStore(session: session).updateMeta { $0.setOverride(.correction, old) }
        var it = item()
        it.notes.meta.setOverride(.correction, old)
        let model = makeModel()
        #expect(model.improveTranscript(it, draft: .preset))
        try await waitUntil { !model.isCorrecting(it.id) }
        #expect(http.models == ["preset-corr"])
        #expect(saved?.correction == nil)
    }

    @Test func improveTranscriptRejectsUnknownProviderAndEmptyModel() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(!model.improveTranscript(item(), draft: .custom(RoleOverride(providerID: UUID(), model: "x"))))
        #expect(!model.improveTranscript(item(), draft: draft("  ")))
        #expect(saved == nil)
        #expect(!model.isCorrecting(item().id))
    }

    @Test func improveTranscriptTwoConsecutiveCallsWithoutYieldingSaveOnceAndRequestOnce() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(model.improveTranscript(item(), draft: draft("A")))
        #expect(!model.improveTranscript(item(), draft: draft("B")))
        try await waitUntil { !model.isCorrecting(item().id) }
        #expect(saved?.correction?.model == "A")
        #expect(http.models == ["A"])
    }

    @Test func improveTranscriptRejectedWhenMovingTranscribingGeneratingOrNotReady() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        let it = item()
        model.isMoving = { true }
        #expect(!model.canCorrectNow(it))
        #expect(!model.improveTranscript(it, draft: draft("A")))
        model.isMoving = { false }
        model.isTranscribing = { _ in true }
        #expect(!model.canCorrectNow(it))
        #expect(!model.improveTranscript(it, draft: draft("A")))
        model.isTranscribing = { _ in false }
        model.generation[it.id] = .generating
        #expect(!model.canCorrectNow(it))
        #expect(!model.improveTranscript(it, draft: draft("A")))
        model.generation[it.id] = nil
        #expect(!model.canCorrectNow(item(runID: nil)))
        #expect(!model.improveTranscript(item(runID: nil), draft: draft("A")))
        let empty = item(transcript: Transcript(utterances: [], failedChunks: []))
        #expect(!model.canCorrectNow(empty))
        #expect(!model.improveTranscript(empty, draft: draft("A")))
        #expect(saved == nil)
        #expect(model.canCorrectNow(it)) // kontrola: bez blokad wolno
    }

    @Test func canCorrectNowAllowsRepeatAfterSuccessfulCorrectionWithoutOverride() {
        let done = CorrectedTranscript(transcript: text, model: "preset-corr", batches: 1, failedBatches: 0, rejectedLines: 0)
        #expect(makeModel().canCorrectNow(item(corrected: done)))
    }

    @Test func canRetryCorrectionStillRequiresOverrideOrFailureAfterSuccess() {
        let done = CorrectedTranscript(transcript: text, model: "preset-corr", batches: 1, failedBatches: 0, rejectedLines: 0)
        #expect(!makeModel().canRetryCorrection(item(corrected: done)))
    }

    @Test func canRetryCorrectionFalseWhileTranscribing() {
        let model = makeModel()
        #expect(model.canRetryCorrection(item()))
        model.isTranscribing = { _ in true }
        #expect(!model.canRetryCorrection(item()))
    }

    func generate(_ model: NotesModel, _ it: SessionItem, _ draft: ModelDraft?) -> Bool {
        model.generate(item: it, useCorrected: false, template: Template.builtIns[0], context: "", draft: draft)
    }

    @Test func generateWithDraftUsesDraftModelAndSavesOverride() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(generate(model, item(), draft("draft-sum", thinking: false)))
        try await waitUntil { model.state(item().id) != .generating }
        #expect(http.models == ["draft-sum"])
        #expect(saved?.summary == RoleOverride(providerID: provider.id, model: "draft-sum", thinking: false))
    }

    @Test func generateWithDraftSaveFailureDoesNotStart() async throws {
        let model = makeModel()
        #expect(!generate(model, item(), draft("draft-sum")))
        #expect(model.state(item().id) != .generating)
        try await Task.sleep(for: .milliseconds(50))
        #expect(http.models.isEmpty)
    }

    @Test func generatePresetDraftClearsSummaryOverrideIncludingThinking() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let old = RoleOverride(providerID: provider.id, model: "old", thinking: true)
        try NotesStore(session: session).updateMeta { $0.setOverride(.summary, old) }
        var it = item()
        it.notes.meta.setOverride(.summary, old)
        let model = makeModel()
        #expect(generate(model, it, .preset))
        try await waitUntil { model.state(it.id) != .generating }
        #expect(http.models == ["preset-sum"])
        #expect(saved?.summary == nil)
    }

    @Test func generateTwoConsecutiveCallsStartOnce() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(generate(model, item(), draft("A")))
        #expect(!generate(model, item(), draft("B")))
        try await waitUntil { model.state(item().id) != .generating }
        #expect(http.models == ["A"])
        #expect(saved?.summary?.model == "A")
    }

    @Test func generateRejectedWhileCorrectingOrTranscribing() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let correcting = makeModel()
        correcting.setPreview(item().id, correcting: true)
        #expect(!generate(correcting, item(), draft("A")))
        let transcribing = makeModel()
        transcribing.isTranscribing = { _ in true }
        #expect(!generate(transcribing, item(), draft("A")))
        #expect(transcribing.state(item().id) == .failed("This meeting is being transcribed."))
        #expect(saved == nil)
    }

    @Test func generateWithoutDraftStillUsesSavedOverride() async throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        var it = item()
        it.notes.meta.setOverride(.summary, RoleOverride(providerID: provider.id, model: "saved"))
        let model = makeModel()
        #expect(generate(model, it, nil))
        try await waitUntil { model.state(it.id) != .generating }
        #expect(http.models == ["saved"])
    }

    @Test func transcriptionGateRefusesWhileCorrecting() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        try Data().write(to: session.appendingPathComponent("mic.caf"))
        #expect(TranscriptionStartGate.refusal(sessionURL: session, transcribing: false, correcting: false, moving: false) == nil)
        #expect(TranscriptionStartGate.refusal(sessionURL: session, transcribing: false, correcting: true, moving: false)
                == "This transcript is being corrected. Try again when that finishes.")
    }

    @Test func transcriptionGateRefusesWhenAudioDeleted() throws {
        try createSession()
        defer { try? FileManager.default.removeItem(at: session) }
        let refusal = TranscriptionStartGate.refusal(sessionURL: session, transcribing: false, correcting: false, moving: false)
        #expect(refusal?.contains("audio was deleted") == true)
    }
}
