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
        func r(_ b: String? = nil, c: Bool = false, g: Bool = false, p: Bool = true, pc: Bool = true, me: Bool = false, l: Bool = true) -> String? {
            ModelsSheetRules.transcribeReason(blocker: b, correcting: c, generating: g, hasPreset: p, providerChosen: pc, modelEmpty: me,
                                              languageChosen: l)
        }
        #expect(r() == nil)
        #expect(r("B", c: true, g: true, p: false, pc: false, l: false) == "B")
        #expect(r(c: true, g: true, p: false, pc: false, l: false) == "Correction is running.")
        #expect(r(g: true, p: false, pc: false, l: false) == "Notes are being generated.")
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

    @Test func summaryReasonEachReasonAndNil() {
        func r(g: Bool = false, t: Bool = true, c: Bool = true, m: Bool = false, k: Bool = false, tr: Bool = false) -> String? {
            ModelsSheetRules.summaryReason(generating: g, hasText: t, hasChoice: c, moving: m, correcting: k, transcribing: tr)
        }
        #expect(r() == nil)
        #expect(r(g: true, t: false, c: false, m: true, k: true, tr: true) == "Notes are being generated.")
        #expect(r(t: false, c: false, m: true, k: true, tr: true) == "Nothing to summarize.")
        #expect(r(c: false, m: true, k: true, tr: true) == "Choose a model.")
        #expect(r(m: true, k: true, tr: true) == "Meetings are being moved.")
        #expect(r(k: true, tr: true) == "Correction is running.")
        #expect(r(tr: true) == "Transcription is running.")
    }

    @Test @MainActor func summaryReasonUsesDraftSourceText() {
        let empty = Transcript(utterances: [], failedChunks: [])
        let text = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])
        let item = SessionItem(url: URL(fileURLWithPath: "/tmp/mn-x"), startedAt: Date(), transcript: text, runID: "run",
                               corrected: CorrectedTranscript(transcript: empty, model: "c", batches: 1, failedBatches: 0, rejectedLines: 0))
        let draft = SummaryModelsDraft(item: item, state: MeetingViewState())
        #expect(!draft.hasText(item))
        draft.useCorrected = false
        #expect(draft.hasText(item))
    }

    private func snapshot(provider: Provider, asrModel: String) throws -> RunSnapshot {
        let preset = Preset(name: "P", language: .polish, asr: RoleAssignment(providerID: provider.id, model: asrModel))
        return try RunSnapshot(preset: preset, provider: provider, probe: nil)
    }

    @Test func asrPrefillTakesCurrentRunNotPreset() throws {
        let used = Provider(name: "Used", baseURL: URL(string: "https://used.test/v1")!)
        let presetAsr = RoleAssignment(providerID: pid, model: "preset-asr")
        let run = try snapshot(provider: used, asrModel: "voxtral")
        let known: Set<UUID> = [used.id, pid]
        #expect(ModelsSheetRules.asrPrefill(run: run, preset: presetAsr, knownProviders: known) == RoleAssignment(providerID: used.id, model: "voxtral"))
        #expect(ModelsSheetRules.asrPrefill(run: nil, preset: presetAsr, knownProviders: known) == presetAsr)
        // Dostawca przebiegu usunięty: preset (o ile jego dostawca istnieje), a gdy też usunięty: nic.
        #expect(ModelsSheetRules.asrPrefill(run: run, preset: presetAsr, knownProviders: [pid]) == presetAsr)
        #expect(ModelsSheetRules.asrPrefill(run: run, preset: presetAsr, knownProviders: []) == nil)
    }

    @Test func correctionPrefillTakesCorrectedFileEvenWhenEqualToPreset() {
        let empty = Transcript(utterances: [], failedChunks: [])
        func c(_ p: UUID?, _ m: String) -> CorrectedTranscript {
            CorrectedTranscript(transcript: empty, model: m, batches: 1, failedBatches: 0, rejectedLines: 0, providerID: p)
        }
        let other = UUID()
        // Zapisany dostawca i model wygrywają z obowiązującym wyborem, także gdy równe presetowi.
        #expect(ModelsSheetRules.correctionPrefill(corrected: c(pid, "m"), assigned: RoleAssignment(providerID: other, model: "x"), knownProviders: [pid, other])
                == RoleAssignment(providerID: pid, model: "m"))
        // Stary plik bez dostawcy, brak pliku albo dostawca usunięty: obowiązujący wybór, bez zgadywania.
        let assigned = RoleAssignment(providerID: other, model: "x")
        #expect(ModelsSheetRules.correctionPrefill(corrected: c(nil, "m"), assigned: assigned, knownProviders: [pid, other]) == assigned)
        #expect(ModelsSheetRules.correctionPrefill(corrected: nil, assigned: assigned, knownProviders: [pid, other]) == assigned)
        #expect(ModelsSheetRules.correctionPrefill(corrected: c(pid, "m"), assigned: assigned, knownProviders: [other]) == assigned)
    }

    @Test func prefilledChoiceEqualToPresetStillFollowsPreset() {
        // „Podążaj za presetem" bez zmian: pokazany ostatni model równy presetowi nie przypina nadpisania.
        #expect(ModelsSheetRules.draft(providerID: pid, model: "m", thinking: nil, preset: preset, hasOverride: false, usePreset: false) == .preset)
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

    @Test func staleOverrideUnchangedRunUsesPresetAndPinsNothing() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        // Dostawca nadpisania usunięty: wypełnienie okna to model presetu; niezmienione uruchomienie czyści nadpisanie.
        try NotesStore(session: session).updateMeta { $0.setOverride(.correction, RoleOverride(providerID: UUID(), model: "gone")) }
        let model = makeModel()
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "preset-corr"
        #expect(draft.submitCorrection(item: item(), notes: model, preset: preset.correction))
        try await waitIdle(model)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
        #expect(http.models == ["preset-corr"])
    }

    /// Przebieg po Transcribe: ta sama ścieżka, którą woła AppModel.run po ASR (migawka z presetem, nadpisanie z dysku).
    func afterRun(_ model: NotesModel) async throws {
        let id = "2026-10-23T09-00-00Z-bbbb"
        let run = RunDirectory(session: session, runID: id)
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        try JSONFile.save(text, to: run.transcript)
        let withASR = preset.withASR(RoleAssignment(providerID: provider.id, model: "asr"), language: .polish)
        let snapshot = try RunSnapshot(preset: withASR, provider: provider, probe: nil)
        await model.afterTranscription(sessionURL: session, runID: id, snapshot: snapshot, transcript: text)
    }

    @Test func transcribeSavesChosenCorrectionAndPostRunCorrectionUsesIt() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "picked"
        var started = false
        #expect(draft.startTranscribe(item: item(), notes: model, preset: preset.correction) { started = true; return true })
        #expect(started)
        try await afterRun(model)
        #expect(http.models == ["picked"])
    }

    @Test func transcribeWithPresetChoiceWritesNoOverrideAndKeepsPresetModel() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "preset-corr"
        #expect(draft.startTranscribe(item: item(), notes: model, preset: preset.correction) { true })
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
        try await afterRun(model)
        #expect(http.models == ["preset-corr"])
    }

    @Test func transcribeRefusesIncompleteOrUnsavableCorrectionAndStartsNothing() throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        let draft = TranscriptModelsDraft()
        var started = false
        draft.correctProviderID = provider.id; draft.correctModel = "  " // po zmianie dostawcy model jest pusty
        #expect(draft.correctionIncomplete)
        #expect(!draft.startTranscribe(item: item(), notes: model, preset: preset.correction) { started = true; return true })
        draft.correctProviderID = UUID(); draft.correctModel = "x" // dostawca zniknął
        #expect(!draft.startTranscribe(item: item(), notes: model, preset: preset.correction) { started = true; return true })
        #expect(!started)
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
    }

    @Test func transcribeWithNothingChosenStartsWithoutTouchingOverrides() throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel()
        #expect(TranscriptModelsDraft().startTranscribe(item: item(), notes: model, preset: nil) { true })
        #expect(NotesStore(session: session).readMeta().modelOverrides == nil)
    }

    @Test func clearOverrideRefusedWhileTranscribing() throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        try NotesStore(session: session).updateMeta { $0.setOverride(.correction, RoleOverride(providerID: provider.id, model: "mine")) }
        let model = makeModel()
        model.transcribing.insert(session.lastPathComponent)
        #expect(!TranscriptModelsDraft().clearOverride(item: item(), notes: model))
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction?.model == "mine")
    }

    @Test func clearOverrideWithoutPresetModelRemovesPersistedOverrideAndRunsNothing() throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        try NotesStore(session: session).updateMeta { $0.setOverride(.correction, RoleOverride(providerID: provider.id, model: "mine")) }
        let model = makeModel()
        let none = Preset(name: "None", language: .polish, asr: nil)
        model.presetFor = { _ in none }
        let draft = TranscriptModelsDraft()
        draft.correctProviderID = provider.id; draft.correctModel = "mine"
        #expect(draft.clearOverride(item: item(), notes: model))
        #expect(NotesStore(session: session).readMeta().modelOverrides?.correction == nil)
        #expect(!model.isCorrecting(item().id))
        // Szkic bez modelu: Improve wyłączone („Choose a model."), nie przypnie z powrotem starego wyboru.
        #expect(ModelsSheetRules.draft(providerID: draft.correctProviderID, model: draft.correctModel, thinking: nil, preset: nil,
                                       hasOverride: false, usePreset: draft.usePreset) == nil)
        #expect(http.models.isEmpty)
    }

    @Test func manualEditAfterResetDropsUsePreset() {
        let draft = TranscriptModelsDraft()
        draft.resetToPreset(preset.correction)
        #expect(draft.usePreset)
        draft.correctModel = "other"
        #expect(!draft.usePreset)
    }
}
