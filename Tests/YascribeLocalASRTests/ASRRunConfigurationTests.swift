import Foundation
import Testing
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeLocalASR

private let localProvider = Provider(name: "Local", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)

private func runSnapshot(_ model: String, language: LanguageCode? = .polish) throws -> RunSnapshot {
    try RunSnapshot(preset: Preset(name: "Test", language: language,
                                  asr: RoleAssignment(providerID: localProvider.id, model: model), languageAuto: language == nil ? true : nil),
                    provider: localProvider, probe: nil)
}

private func fixtureStore(_ model: LocalASRModel = .cohereTranscribe6bit, free: Int64 = 100_000_000_000) throws -> ModelStore {
    let store = ModelStore(model: model, directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)"),
                           diskSpace: { _ in ModelDiskLocation(volume: "fixture", freeBytes: free) })
    for (name, size) in model.manifest.files {
        let url = store.modelDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let f = try FileHandle(forWritingTo: url)
        try f.truncate(atOffset: UInt64(size)); try f.close()
    }
    return store
}

private actor FailingEngine: LocalASREngine {
    var unloads = 0
    func load() throws { throw ModelStoreError(message: "fixture load failed") }
    func transcribe(samples: [Float], language: LanguageCode?) -> (text: String, words: [TranscribedWord]) { ("", []) }
    func unload() { unloads += 1 }
}

@Suite struct ASRRunConfigurationTests {
    @Test func unknownModelRefusedByConfigurationAndFactory() throws {
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(snapshot: runSnapshot("unknown-local")) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        let store = ModelStore(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: RunGateRefusal.self) { try LocalASRFactory.client(provider: localProvider, model: "unknown-local", store: store).get() }
    }

    @Test func cohereAutoAndUnsupportedLanguagesRefused() throws {
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(snapshot: runSnapshot(LocalASRModels.cohereTranscribe6bit, language: nil)) }
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(snapshot: runSnapshot(LocalASRModels.cohereTranscribe6bit, language: LanguageCode("ru"))) }
        #expect(RunGate.checkLanguage(model: .cohereTranscribe6bit, language: .polish) == nil)
        #expect(RunGate.checkLanguage(model: .parakeetV3, language: nil) == nil)
        for code in ["en", "ar", "de", "el", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "vi", "zh"] {
            #expect(RunGate.checkLanguage(model: .cohereTranscribe6bit, language: try LanguageCode(code)) == nil)
        }
    }

    @Test func presetAndCLIModelSelectStoreAndRunnerParameters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        for model in LocalASRModel.allCases {
            let snapshot = try runSnapshot(model.id)
            let config = try ASRRunConfiguration.build(snapshot: snapshot, storeDirectory: root)
            #expect(config.snapshot.model == model.id && config.snapshot.language == .polish)
            #expect(config.store?.model == model && config.store?.directory == root)
            let engine = LocalASRFactory.makeEngine(model: model, store: config.store!)
            switch model {
            case .parakeetV3:
                #expect(engine is FluidAudioEngine)
                #expect(config.maxChunkSeconds == 59 && config.maxSourceSpan == nil && !config.repetitionFilterEnabled)
            case .cohereTranscribe6bit:
                #expect(engine is CohereEngine)
                #expect(config.maxChunkSeconds == 12 && config.maxSourceSpan == 30 && config.repetitionFilterEnabled)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.path), "configuration is pure")
    }

    @Test func cliArgumentsAndPresetUseSharedSeamIncludingResumeRefusals() throws {
        let preset = Preset(name: "Preset", language: .polish,
                            asr: RoleAssignment(providerID: localProvider.id, model: LocalASRModels.cohereTranscribe6bit))
        let app = try ASRRunConfiguration.build(preset: preset, provider: localProvider)
        let cli = try ASRRunConfiguration.build(provider: localProvider, model: LocalASRModels.cohereTranscribe6bit, language: .polish)
        let repeated = try ASRRunConfiguration.build(provider: localProvider, model: LocalASRModels.cohereTranscribe6bit, language: .polish)
        #expect(repeated.snapshot == cli.snapshot, "configuration does not create random preset IDs")
        #expect(app.maxChunkSeconds == cli.maxChunkSeconds && app.maxSourceSpan == cli.maxSourceSpan)
        #expect(app.store?.model == cli.store?.model && app.repetitionFilterEnabled == cli.repetitionFilterEnabled)
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(provider: localProvider, model: "unknown", language: .polish) }
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(provider: localProvider, model: LocalASRModels.cohereTranscribe6bit, language: nil) }
        #expect(throws: RunGateRefusal.self) { try ASRRunConfiguration.build(provider: localProvider, model: LocalASRModels.cohereTranscribe6bit, language: LanguageCode("ru")) }
        var saved = RunInput(snapshot: app.snapshot, gate: .init(), maxChunkSeconds: 12, crosstalk: .init(), trackFrames: [:])
        saved.maxSourceSpan = 30; saved.offlineAEC = nil
        let resumed = try ASRRunConfiguration.build(provider: localProvider, model: saved.snapshot.model, language: .polish, savedInput: saved)
        #expect(resumed.snapshot == saved.snapshot && resumed.offlineAEC == nil)
        #expect(throws: RunError.inputMismatch) { try ASRRunConfiguration.build(provider: localProvider, model: LocalASRModels.parakeetV3, language: .polish, savedInput: saved) }
        #expect(throws: RunError.inputMismatch) { try ASRRunConfiguration.build(provider: localProvider, model: saved.snapshot.model, language: .english, savedInput: saved) }
    }

    @Test func factoryRefusesMismatchedStore() throws {
        let store = try fixtureStore(.parakeetV3)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(throws: RunGateRefusal.self) { try LocalASRFactory.client(provider: localProvider, model: LocalASRModels.cohereTranscribe6bit, store: store, engine: FailingEngine()).get() }
    }

    @Test func noDiskRefusesAndReleasesReservation() throws {
        let store = try fixtureStore(free: 1), pool = LocalASRReservations()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let result = LocalASRFactory.client(provider: localProvider, model: store.model.id, store: store, engine: FailingEngine(), reservations: pool)
        switch result {
        case .success: Issue.record("disk gate allowed a client")
        case .failure(let refusal):
            #expect(refusal.message.contains("need") && refusal.message.contains("available 1 bytes"))
            #expect(!refusal.canDownload)
        }
        #expect(pool.isIdle)
        let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
    }

    @Test func busyFileLockRefusesAndReleasesReservation() throws {
        let store = try fixtureStore(), pool = LocalASRReservations()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let owner = try store.acquireLock()
        let result = LocalASRFactory.client(provider: localProvider, model: store.model.id, store: store, engine: FailingEngine(), reservations: pool)
        switch result {
        case .success: Issue.record("busy lock allowed a client")
        case .failure(let refusal): #expect(refusal.message.contains("busy"))
        }
        #expect(pool.isIdle)
        withExtendedLifetime(owner) {}
    }

    @Test func missingModelRefusalReleasesReservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)"), pool = LocalASRReservations()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModelStore(model: .cohereTranscribe6bit, directory: root)
        #expect(throws: RunGateRefusal.self) { try LocalASRFactory.client(provider: localProvider, model: store.model.id, store: store, reservations: pool).get() }
        #expect(pool.isIdle)
    }

    @Test func cohereExclusiveAgainstMeetingProbeAndDictation() throws {
        for _ in ["meeting", "probe", "dictation"] {
            let pool = LocalASRReservations()
            var first: LocalASRReservation? = try pool.acquire(model: .parakeetV3)
            #expect(throws: RunGateRefusal.self) { try pool.acquire(model: .cohereTranscribe6bit) }
            #expect(!pool.isIdle)
            first = nil
            #expect(pool.isIdle)
            first = try pool.acquire(model: .cohereTranscribe6bit)
            #expect(throws: RunGateRefusal.self) { try pool.acquire(model: .parakeetV3) }
            #expect(throws: RunGateRefusal.self) { try pool.acquire(model: .cohereTranscribe6bit) }
            withExtendedLifetime(first) {}
        }
    }

    @Test func releaseFreesReservationAndFileLockBeforeClientDeinit() async throws {
        let store = try fixtureStore(), pool = LocalASRReservations()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        for realEngine in [false, true] {
            let engine: (any LocalASREngine)? = realEngine ? nil : FailingEngine()
            let c = try LocalASRFactory.client(provider: localProvider, model: store.model.id, store: store, engine: engine, reservations: pool).get()
            #expect(!pool.isIdle)
            #expect(throws: ModelStoreError.self) { try store.acquireLock() }
            await (c as? ReleasableClient)?.release()
            #expect(pool.isIdle)
            let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
        }
    }

    @Test func failedRunReleasesReservationAndFileLock() async throws {
        let store = try fixtureStore(), pool = LocalASRReservations(), engine = FailingEngine()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let config = try ASRRunConfiguration.build(snapshot: runSnapshot(store.model.id))
        let c = try LocalASRFactory.client(provider: localProvider, model: store.model.id, store: store, engine: engine, reservations: pool).get()
        let missingSession = store.directory.appendingPathComponent("no-session")
        await #expect(throws: (any Error).self) { try await config.run(session: missingSession, runID: "error", client: c) }
        #expect(pool.isIdle)
        #expect(await engine.unloads == 1)
        let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
    }

    @Test func savedInputRestoresParakeet59AndCohere12Over30WithGateCrosstalkAndAEC() throws {
        for model in LocalASRModel.allCases {
            let snap = try runSnapshot(model.id, language: .english)
            var gate = EnergyGate.Config(); gate.thresholdDBFS = -53; gate.paddingSeconds = 0.4
            var cross = CrosstalkFilter(); cross.correlationThreshold = 0.42
            var saved = RunInput(snapshot: snap, gate: gate, maxChunkSeconds: model == .parakeetV3 ? 59 : 12,
                                 crosstalk: cross, trackFrames: [:])
            saved.maxSourceSpan = model == .parakeetV3 ? nil : 30
            saved.offlineAEC = nil
            let json = try JSONEncoder().encode(saved)
            let restored = try JSONDecoder().decode(RunInput.self, from: json)
            let config = try ASRRunConfiguration.build(snapshot: restored.snapshot, savedInput: restored)
            let runner = config.runner(session: URL(fileURLWithPath: "/tmp"), runID: "resume", client: StubTranscriber())
            #expect(config.store?.model == model && config.snapshot.language == .english)
            #expect(runner.maxChunkSeconds == saved.maxChunkSeconds && runner.maxSourceSpan == saved.maxSourceSpan)
            #expect(runner.gate.config == gate && runner.crosstalk == cross && runner.offlineAEC == nil)
            #expect(runner.repetitionFilterEnabled == (model == .cohereTranscribe6bit))
            // Zapisane wartości mają pierwszeństwo także po zmianie domyślnych z rejestru.
            saved.maxChunkSeconds = 7; saved.maxSourceSpan = 19; saved.offlineAEC = .init()
            let custom = try ASRRunConfiguration.build(snapshot: snap, savedInput: saved)
            #expect(custom.maxChunkSeconds == 7 && custom.maxSourceSpan == 19 && custom.offlineAEC == .init())
            saved.maxSourceSpan = nil
            #expect(try ASRRunConfiguration.build(snapshot: snap, savedInput: saved).maxSourceSpan == nil)
        }
    }

    @Test func savedSnapshotCannotBeReplacedByCurrentPreset() throws {
        let snap = try runSnapshot(LocalASRModels.parakeetV3)
        let saved = RunInput(snapshot: snap, gate: .init(), maxChunkSeconds: 59, crosstalk: .init(), trackFrames: [:])
        #expect(throws: RunError.inputMismatch) { try ASRRunConfiguration.build(snapshot: runSnapshot(LocalASRModels.cohereTranscribe6bit), savedInput: saved) }
    }
}

private struct StubTranscriber: TranscriptionClient {
    var provider: Provider { localProvider }
    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult { .init(text: "", words: []) }
}
