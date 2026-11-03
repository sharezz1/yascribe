import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

/// Zapisuje treść każdego żądania (prompt), odpowiedź „ok".
private final class PromptHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var bodies: [String] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { seen.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self)) }
        return (Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("SummaryModelsDraft") @MainActor struct SummaryModelsDraftTests {
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    fileprivate let http = PromptHTTP()

    var preset: Preset {
        Preset(name: "Test", language: .polish, asr: nil, summary: RoleAssignment(providerID: provider.id, model: "preset-sum"))
    }

    func line(_ text: String) -> Transcript {
        Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: text, words: [], approximateTiming: false)], failedChunks: [])
    }

    func makeModel() -> NotesModel {
        let model = NotesModel()
        let preset = preset, provider = provider, http = http
        model.presetFor = { _ in preset }
        model.presetsInfo = { ([preset], preset.id) }
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        return model
    }

    func item(corrected: Bool) -> SessionItem {
        var item = SessionItem(url: session, startedAt: Date(), transcript: line("OriginalWord"), runID: "run",
                               corrected: corrected ? CorrectedTranscript(transcript: line("CorrectedWord"), model: "c", batches: 1,
                                                                          failedBatches: 0, rejectedLines: 0) : nil)
        item.notes.meta = NotesStore(session: session).readMeta()
        return item
    }

    func submit(_ draft: SummaryModelsDraft, _ item: SessionItem, _ state: MeetingViewState, _ model: NotesModel) -> Bool {
        draft.submit(item: item, state: state, notes: model, template: Template.builtIns[0], context: "", preset: preset.summary)
    }

    func waitIdle(_ model: NotesModel) async throws {
        for _ in 0..<400 where model.state(session.lastPathComponent) == .generating { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func sourceStartsOriginalWhenNoCorrectionEvenIfUseCorrectedTrue() {
        let state = MeetingViewState()
        #expect(state.useCorrected)
        let draft = SummaryModelsDraft(item: item(corrected: false), state: state)
        #expect(!draft.useCorrected)
        #expect(draft.sourceLabel == "Original")
        #expect(SummaryModelsDraft(item: item(corrected: true), state: state).sourceLabel == "Corrected")
    }

    @Test func submittedTextIsCorrectedWhenCorrectionExistsAndOriginalWhenChosen() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel(), state = MeetingViewState()
        let draft = SummaryModelsDraft(item: item(corrected: true), state: state)
        draft.resetToPreset(preset.summary)
        #expect(submit(draft, item(corrected: true), state, model))
        try await waitIdle(model)
        draft.useCorrected = false
        #expect(submit(draft, item(corrected: true), state, model))
        try await waitIdle(model)
        let bodies = http.bodies
        #expect(bodies.count == 2)
        #expect(bodies.first?.contains("CorrectedWord") == true && bodies.first?.contains("OriginalWord") == false)
        #expect(bodies.last?.contains("OriginalWord") == true && bodies.last?.contains("CorrectedWord") == false)
    }

    @Test func submitDoesNotChangeTranscriptVersionSelection() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel(), state = MeetingViewState()
        let draft = SummaryModelsDraft(item: item(corrected: true), state: state)
        draft.resetToPreset(preset.summary)
        draft.useCorrected = false
        #expect(submit(draft, item(corrected: true), state, model))
        try await waitIdle(model)
        #expect(state.useCorrected)
        #expect(state.summaryUseCorrected == false)
    }

    @Test func submitSetsRememberedSourceOnlyOnAcceptedRun() {
        // Brak katalogu sesji: zapis szkicu pada, nic nie startuje.
        let model = makeModel(), state = MeetingViewState()
        let draft = SummaryModelsDraft(item: item(corrected: true), state: state)
        draft.providerID = provider.id; draft.model = "mine"
        draft.useCorrected = false
        #expect(!submit(draft, item(corrected: true), state, model))
        #expect(state.summaryUseCorrected == nil)
    }

    @Test func staleOverrideUnchangedRunUsesPresetAndPinsNothing() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        try NotesStore(session: session).updateMeta { $0.setOverride(.summary, RoleOverride(providerID: UUID(), model: "gone", thinking: false)) }
        let model = makeModel(), state = MeetingViewState()
        let draft = SummaryModelsDraft(item: item(corrected: false), state: state)
        draft.providerID = provider.id; draft.model = "preset-sum" // wypełnienie okna: model presetu, Thinking bez nadpisania
        #expect(submit(draft, item(corrected: false), state, model))
        try await waitIdle(model)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.summary == nil)
        #expect(http.bodies.first?.contains("preset-sum") == true)
    }

    @Test func clearOverrideWithoutPresetModelRemovesPersistedOverrideAndRunsNothing() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        try NotesStore(session: session).updateMeta { $0.setOverride(.summary, RoleOverride(providerID: provider.id, model: "mine", thinking: true)) }
        let model = makeModel(), state = MeetingViewState()
        let none = Preset(name: "None", language: .polish, asr: nil)
        model.presetFor = { _ in none }
        model.presetsInfo = { ([none], none.id) }
        #expect(model.presetSummaryChoice(for: item(corrected: false)) == nil)
        let draft = SummaryModelsDraft(item: item(corrected: false), state: state)
        draft.providerID = provider.id; draft.model = "mine"; draft.thinking = true
        #expect(draft.clearOverride(item: item(corrected: false), notes: model))
        #expect(NotesStore(session: session).readMeta().modelOverrides?.summary == nil)
        #expect(model.state(session.lastPathComponent) == .idle)
        #expect(draft.providerID == nil && draft.model.isEmpty && draft.thinking == nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(http.bodies.isEmpty)
    }

    @Test func presetResetClearsThinkingAndOverrideInMeta() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        try NotesStore(session: session).updateMeta { $0.setOverride(.summary, RoleOverride(providerID: provider.id, model: "old", thinking: true)) }
        let model = makeModel(), state = MeetingViewState()
        let draft = SummaryModelsDraft(item: item(corrected: false), state: state)
        draft.providerID = provider.id; draft.model = "old"; draft.thinking = true
        draft.resetToPreset(preset.summary)
        #expect(draft.thinking == nil)
        #expect(draft.usePreset)
        #expect(submit(draft, item(corrected: false), state, model))
        try await waitIdle(model)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.summary == nil)
    }
}
