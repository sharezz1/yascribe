import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

@Suite("ModelsSheetRules") struct ModelsSheetRulesTests {
    let pid = UUID()
    var preset: RoleAssignment { RoleAssignment(providerID: pid, model: "m") }

    @Test func draftIsPresetWhenUnchangedAndNoOverride() {
        #expect(ModelsSheetRules.draft(providerID: pid, model: "m", thinking: nil, preset: preset, hasOverride: false, usePreset: false) == .preset)
    }

    @Test func draftIsCustomWhenSameAsPresetButOverrideExists() {
        #expect(ModelsSheetRules.draft(providerID: pid, model: "m", thinking: nil, preset: preset, hasOverride: true, usePreset: false)
                == .custom(RoleOverride(providerID: pid, model: "m")))
    }

    @Test func draftIsPresetWhenUsePresetEvenWithOverride() {
        #expect(ModelsSheetRules.draft(providerID: nil, model: "", thinking: true, preset: preset, hasOverride: true, usePreset: true) == .preset)
    }

    @Test func draftNilForEmptyModelOrMissingProvider() {
        #expect(ModelsSheetRules.draft(providerID: pid, model: "  ", thinking: nil, preset: preset, hasOverride: false, usePreset: false) == nil)
        #expect(ModelsSheetRules.draft(providerID: nil, model: "m", thinking: nil, preset: preset, hasOverride: false, usePreset: false) == nil)
    }

    @Test func transcribeReasonOrder() {
        func r(_ b: String? = nil, c: Bool = false, p: Bool = true, pc: Bool = true, me: Bool = false, l: Bool = true) -> String? {
            ModelsSheetRules.transcribeReason(blocker: b, correcting: c, hasPreset: p, providerChosen: pc, modelEmpty: me, languageChosen: l)
        }
        #expect(r() == nil)
        #expect(r("B", c: true, p: false, pc: false, l: false) == "B")
        #expect(r(c: true, p: false, pc: false, l: false) == "Correction is running.")
        #expect(r(p: false, pc: false, l: false) == "This meeting has no preset.")
        #expect(r(pc: false, l: false) == "Choose a model.")
        #expect(r(me: true, l: false) == "Choose a model.")
        #expect(r(l: false) == "Choose a language.")
    }

    @Test func correctReasonHasExplicitReasonForEach() {
        func r(m: Bool = false, t: Bool = false, c: Bool = false, g: Bool = false, u: Bool = true, d: Bool = true) -> String? {
            ModelsSheetRules.correctReason(canCorrectNow: !(m || t || c || g) && u, moving: m, transcribing: t, correcting: c,
                                           generating: g, hasUsableTranscript: u, hasDraft: d)
        }
        #expect(r() == nil)
        #expect(r(m: true) == "Meetings are being moved.")
        #expect(r(t: true) == "Transcription is running.")
        #expect(r(c: true) == "Correction is running.")
        #expect(r(g: true) == "Notes are being generated.")
        #expect(r(u: false) == "No usable transcript.")
        #expect(r(d: false) == "Choose a model.")
    }

    @Test func languageChoiceMapsAutoLanguageAndUnknown() {
        #expect(ModelsSheetRules.languageChoice(isAuto: true, language: nil) == .auto)
        #expect(ModelsSheetRules.languageChoice(isAuto: false, language: .polish) == .code(.polish))
        #expect(ModelsSheetRules.languageChoice(isAuto: false, language: nil) == .unset)
    }

    @Test func correctionOriginCaptions() {
        #expect(ModelsSheetRules.correctionOrigin(hasOverride: true, stale: true, presetName: "P") == "The model you chose is no longer available")
        #expect(ModelsSheetRules.correctionOrigin(hasOverride: true, stale: false, presetName: "P") == "Chosen for this meeting")
        #expect(ModelsSheetRules.correctionOrigin(hasOverride: false, stale: false, presetName: "P") == "From the preset: P")
    }
}

private final class SeenHTTP: HTTPClient, @unchecked Sendable {
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

@Suite("TranscriptModelsDraft") @MainActor struct TranscriptModelsDraftTests {
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    fileprivate let http = SeenHTTP()
    let text = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])

    var preset: Preset {
        Preset(name: "Test", language: .polish, asr: nil, correction: RoleAssignment(providerID: provider.id, model: "preset-corr"))
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

    /// Świeży `item` z dysku: `overrides(for:)` czyta `item.notes.meta`, nie pamięć modelu.
    func item() -> SessionItem {
        var item = SessionItem(url: session, startedAt: Date(), transcript: text, runID: "run")
        item.notes.meta = NotesStore(session: session).readMeta()
        return item
    }

    func waitIdle(_ model: NotesModel) async throws {
        for _ in 0..<400 where model.isCorrecting(session.lastPathComponent) { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func resetToPresetThenSubmitClearsPersistedCorrectionOverride() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(model.setOverride(.correction, RoleOverride(providerID: provider.id, model: "mine"), item: item()))
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "mine"
        draft.resetToPreset(preset.correction)
        #expect(draft.submitCorrection(item: item(), notes: model, preset: preset.correction))
        try await waitIdle(model)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
        #expect(http.models == ["preset-corr"])
    }

    @Test func submitCorrectionUnchangedFromPresetWritesNoOverride() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "preset-corr"
        #expect(draft.submitCorrection(item: item(), notes: model, preset: preset.correction))
        try await waitIdle(model)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
        #expect(http.models == ["preset-corr"])
    }

    @Test func manualEditAfterResetDropsUsePreset() {
        let draft = TranscriptModelsDraft()
        draft.resetToPreset(preset.correction)
        #expect(draft.usePreset)
        draft.correctModel = "other"
        #expect(!draft.usePreset)
    }
}
