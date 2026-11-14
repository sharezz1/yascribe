import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeApp

@MainActor private final class LocalFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let provider = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    let model: AppModel

    init(ready: Set<LocalASRVariant> = Set(LocalASRVariant.allCases), engine: (any LocalASREngine)? = nil) throws {
        let root = self.root
        let supports = try LocalASRVariant.allCases.reversed().map { variant in
            let store = ModelStore(directory: root.appendingPathComponent("models"), variant: variant,
                                   download: { _, _, _ in Issue.record("unexpected download") })
            if ready.contains(variant) {
                for (file, size) in variant.manifest.files {
                    let url = store.modelDirectory.appendingPathComponent(file)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let h = try FileHandle(forWritingTo: url)
                    try h.truncate(atOffset: UInt64(size))
                    try h.close()
                }
            }
            return LocalASRSupport(store: store)
        }
        let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
        setenv("YASCRIBE_DATA_DIR", root.appendingPathComponent("data").path, 1)
        var factory: (@Sendable (ModelStore) -> any LocalASREngine)?
        if let engine { factory = { _ in engine } }
        model = AppModel(localASRModels: supports, localASREngine: factory)
        if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
        model.providers = ProvidersFile(providers: [provider])
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
    func preset(_ id: String) -> Preset {
        Preset(name: "Local", language: .polish, asr: RoleAssignment(providerID: provider.id, model: id))
    }

    /// `loud` = prostokąt powyżej bramki energii, więc runner naprawdę wysyła okno do klienta.
    func session(loud: Bool = false) throws -> URL {
        let url = model.paths.sessions.appendingPathComponent(AppModel.sessionName(Date()))
        let ns = Timebase(numer: 1, denom: 1)
        let samples: [Int16] = loud ? (0..<32_000).map { ($0 / 40) % 2 == 0 ? 8_000 : -8_000 } : [Int16](repeating: 0, count: 16_000)
        let source = FileSource(trackID: "system", samples: samples,
                                sampleRate: 16_000, channels: 1, startHostTime: 1_000_000_000, timebase: ns)
        try SessionRecorder(directory: url, sources: [source], conditions: [], clock: ManualHostClock(), timebase: ns, zeroWatch: [:]).start()
        return url
    }

    func finish(_ session: URL, expectNoError: Bool = true) async throws -> RunDirectory {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.transcribing.contains(session.lastPathComponent), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(!model.transcribing.contains(session.lastPathComponent))
        if expectNoError { #expect(model.lastError == nil) }
        let id = try #require(RunDirectory.latestRunID(in: session))
        return RunDirectory(session: session, runID: id)
    }
}

@Test @MainActor func appRoutesClientSnapshotAndRunOwnershipByVariant() async throws {
    for variant in LocalASRVariant.allCases {
        let f = try LocalFixture()
        defer { f.clean() }
        let selected = try #require(f.model.localASR(variant.rawValue))
        let other = try #require(f.model.localASRModels.first { $0 !== selected })
        let expectedFingerprint = try #require(selected.store.fingerprint())
        #expect(expectedFingerprint != other.store.fingerprint())
        // Krótkie WAV nie ładuje modelu; bramka klienta dowodzi, jaki magazyn naprawdę dostał.
        let c = try #require(f.model.transcriptionClient(for: f.provider.id, model: variant.rawValue))
        let wav = WAVEncoder.wav([Int16](repeating: 0, count: 160), rate: 16_000)
        _ = try await c.transcribe(wav: wav, model: variant.rawValue, language: .polish, shape: .audioTranscriptions)
        await #expect(throws: ProviderError.self) {
            _ = try await c.transcribe(wav: wav, model: other.store.variant.rawValue, language: .polish, shape: .audioTranscriptions)
        }
        await (c as? any ReleasableClient)?.release()
        let session = try f.session()
        #expect(f.model.transcribe(sessionURL: session, preset: f.preset(variant.rawValue)))
        selected.remove()
        #expect(selected.downloadError?.contains("in use") == true)
        #expect(selected.store.status() == .ready)
        other.remove()
        #expect(other.store.status() == .missing)
        let dir = try await f.finish(session)
        let input = try JSONFile.load(RunInput?.self, from: dir.input, default: nil)
        #expect(input?.snapshot.model == variant.rawValue)
        #expect(input?.snapshot.modelFingerprint == expectedFingerprint)
        selected.remove()
        #expect(selected.store.status() == .missing)
    }
}

@Test @MainActor func ultraSnapshotHasFingerprintWhenV3IsMissing() async throws {
    let f = try LocalFixture(ready: [.parakeetUltra])
    defer { f.clean() }
    let session = try f.session()
    #expect(f.model.transcribe(sessionURL: session, preset: f.preset(LocalASRModels.parakeetUltra)))
    let dir = try await f.finish(session)
    let original = try #require(try JSONFile.load(RunInput?.self, from: dir.input, default: nil))
    #expect(original.snapshot.modelFingerprint == f.model.localASR(LocalASRModels.parakeetUltra)?.store.fingerprint())
    #expect(original.snapshot.modelFingerprint != nil)
    f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
    #expect(f.model.transcribing.contains(session.lastPathComponent))
    _ = try await f.finish(session)
    // Zmiana małego pliku przy zachowanym rozmiarze musi zatrzymać rzeczywiste AppModel.resume.
    let store = try #require(f.model.localASR(LocalASRModels.parakeetUltra)?.store)
    let config = store.modelDirectory.appendingPathComponent("config.json")
    var bytes = try Data(contentsOf: config)
    bytes[0] = 1
    try bytes.write(to: config)
    f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
    #expect(f.model.lastError?.contains("changed since this run") == true)
    #expect(!f.model.transcribing.contains(session.lastPathComponent))
}

@Test @MainActor func legacyPresetDictationAndSnapshotResolveExplicitlyToV3() async throws {
    let f = try LocalFixture()
    defer { f.clean() }
    let legacy = f.preset("legacy-asr-id")
    f.model.presets = PresetsFile(presets: [legacy])
    f.model.settings.dictation = DictationSettings(asr: legacy.asr, language: .polish)
    f.model.save()
    let presetBytes = try Data(contentsOf: f.model.paths.presets)
    let settingsBytes = try Data(contentsOf: f.model.paths.settings)
    f.model.load()
    #expect(try Data(contentsOf: f.model.paths.presets) == presetBytes)
    #expect(try Data(contentsOf: f.model.paths.settings) == settingsBytes)
    let dictation = try #require(f.model.dictation.buildInput([]))
    #expect(dictation.input.asrModel == LocalASRModels.parakeetV3)
    #expect(dictation.meta.asrModel == LocalASRModels.parakeetV3)
    let c = try #require(f.model.transcriptionClient(for: f.provider.id, model: legacy.asr!.model))
    _ = try await c.transcribe(wav: WAVEncoder.wav([0], rate: 16_000), model: legacy.asr!.model, language: .polish, shape: .audioTranscriptions)
    await #expect(throws: ProviderError.self) {
        _ = try await c.transcribe(wav: WAVEncoder.wav([0], rate: 16_000), model: LocalASRModels.parakeetUltra, language: .polish, shape: .audioTranscriptions)
    }
    await (c as? any ReleasableClient)?.release()
    let session = try f.session()
    #expect(f.model.transcribe(sessionURL: session, preset: legacy))
    let dir = try await f.finish(session)
    var input = try #require(try JSONFile.load(RunInput?.self, from: dir.input, default: nil))
    #expect(input.snapshot.model == LocalASRModels.parakeetV3)
    #expect(input.snapshot.preset.asr?.model == LocalASRModels.parakeetV3)
    #expect(f.model.presets.presets.first?.asr?.model == legacy.asr?.model)
    input.snapshot.model = legacy.asr!.model
    input.snapshot.preset = legacy
    try JSONFile.save(input, to: dir.input)
    let saved = try Data(contentsOf: dir.input)
    f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
    #expect(f.model.transcribing.contains(session.lastPathComponent))
    _ = try await f.finish(session)
    #expect(try Data(contentsOf: dir.input) == saved)
    for fingerprint in [nil, "different", f.model.localASR(LocalASRModels.parakeetUltra)?.store.fingerprint()] {
        input.snapshot.modelFingerprint = fingerprint
        try JSONFile.save(input, to: dir.input)
        f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
        #expect(f.model.lastError?.contains("Unknown on-device model") == true)
        #expect(!f.model.transcribing.contains(session.lastPathComponent))
    }
    f.model.localASR("")!.remove()
    input.snapshot.modelFingerprint = nil
    try JSONFile.save(input, to: dir.input)
    f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
    #expect(f.model.lastError?.contains("Unknown on-device model") == true)
    #expect(!f.model.transcribing.contains(session.lastPathComponent))
}

@Test @MainActor func providerCheckShowsWhichLocalVariantsAreReady() async throws {
    for ready: Set<LocalASRVariant> in [[], [.parakeetV3], [.parakeetUltra], Set(LocalASRVariant.allCases)] {
        let f = try LocalFixture(ready: ready)
        defer { f.clean() }
        await f.model.verifyProvider(f.provider.id)
        let check = f.model.providerChecks[f.provider.id]
        if ready.isEmpty {
            #expect(check == .failed("The on-device speech model isn't downloaded yet. Download it in Settings."))
        } else if ready.count == 2 {
            #expect(check == .verified(models: 2))
        } else {
            #expect(check == .limited(ready.first!.displayName + " only"))
        }
    }
}

@Test func selectingOnDeviceProviderResetsTheModel() {
    let local = Provider(name: "Local", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    let remote = Provider(name: "Remote", baseURL: URL(string: "https://example.test/v1")!)
    #expect(LocalASRModels.modelWhenSelecting(local, previous: "legacy-asr-id") == LocalASRModels.parakeetV3)
    #expect(LocalASRModels.modelWhenSelecting(remote, previous: "existing") == "existing")
    #expect(LocalASRModels.modelWhenSelecting(nil, previous: "existing") == "existing")
}

@Test @MainActor func knownLocalVariantNeverFallsBackToTheOtherModel() throws {
    let f = try LocalFixture(ready: [.parakeetV3])
    defer { f.clean() }
    #expect(f.model.transcriptionClient(for: f.provider.id, model: LocalASRModels.parakeetUltra) == nil)
    #expect(f.model.lastError?.contains("isn't downloaded") == true)
    f.model.settings.dictation = DictationSettings(asr: f.preset(LocalASRModels.parakeetUltra).asr, language: .polish)
    #expect(f.model.dictation.buildInput([]) == nil)
}

/// Atrapa silnika: pierwszy przebieg może się nie udać (luka do wznowienia), potem zwraca tekst ze słowami.
private actor ScriptedEngine: LocalASREngine {
    private var failing: Bool
    init(failing: Bool) { self.failing = failing }
    func setFailing(_ f: Bool) { failing = f }
    func load() async throws {}
    func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]) {
        if failing { throw ProviderError.badResponse("scripted failure") }
        return ("dzień dobry", [TranscribedWord(word: "dzień", start: 0, end: 0.4), TranscribedWord(word: "dobry", start: 0.5, end: 0.9)])
    }
    func unload() async {}
}

/// Stara migawka (obcy identyfikator, odcisk v3): wznowienie musi przejść zaległe okno przez klienta v3, nie odrzucić go bramką wariantu.
@Test @MainActor func legacyResumeTranscribesThePendingWindow() async throws {
    let engine = ScriptedEngine(failing: true)
    let f = try LocalFixture(engine: engine)
    defer { f.clean() }
    let legacy = f.preset("legacy-asr-id")
    let session = try f.session(loud: true)
    #expect(f.model.transcribe(sessionURL: session, preset: legacy))
    let dir = try await f.finish(session, expectNoError: false)
    let gaps = try #require(try JSONFile.load(Transcript?.self, from: dir.transcript, default: nil))
    #expect(!gaps.failedChunks.isEmpty)
    var input = try #require(try JSONFile.load(RunInput?.self, from: dir.input, default: nil))
    input.snapshot.model = legacy.asr!.model
    input.snapshot.preset = legacy
    try JSONFile.save(input, to: dir.input)
    await engine.setFailing(false)
    f.model.lastError = nil
    f.model.resume(SessionItem(url: session, startedAt: Date()), runID: dir.url.lastPathComponent)
    #expect(f.model.transcribing.contains(session.lastPathComponent))
    _ = try await f.finish(session)
    let done = try #require(try JSONFile.load(Transcript?.self, from: dir.transcript, default: nil))
    #expect(done.failedChunks.isEmpty)
    #expect(!done.utterances.isEmpty)
}

/// Dyktowanie Ultra trzyma (blokuje usunięcie) magazyn Ultra, nie v3.
@Test @MainActor func ultraDictationHoldsTheUltraStore() throws {
    let f = try LocalFixture()
    defer { f.clean() }
    f.model.settings.dictation = DictationSettings(asr: f.preset(LocalASRModels.parakeetUltra).asr, language: .polish)
    let built = try #require(f.model.dictation.buildInput([Int16](repeating: 1_000, count: 16_000)))
    let wrapper = try #require(built.input.transcriber as? ReleasingTranscriber)
    #expect(wrapper.support === f.model.localASR(LocalASRModels.parakeetUltra))
    #expect(built.input.asrModel == LocalASRModels.parakeetUltra)
}
