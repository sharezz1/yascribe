import CoreML
import Foundation
import Testing
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeLocalASR

private actor RuntimeStub: CohereRuntime {
    var loads = 0, unloads = 0
    var inputs: [[Float]] = []
    var languages: [String] = []
    let responses: [CohereTranscriptionResult]
    let failsLoading: Bool
    var configuration: CohereTranscribeComputeConfiguration?
    var fingerprint: String?
    init(_ responses: [CohereTranscriptionResult] = [.init(text: "gotowe", chunkEOS: [true])], failsLoading: Bool = false) {
        self.responses = responses; self.failsLoading = failsLoading
    }
    func loadModels(from directory: URL, compiledDirectory: URL, fingerprint: String,
                    computeConfiguration: CohereTranscribeComputeConfiguration, lock: ModelStoreLock) throws {
        loads += 1; configuration = computeConfiguration; self.fingerprint = fingerprint
        if failsLoading { throw ModelStoreError(message: "load failed") }
    }
    func transcribe(audioSamples: [Float], decoderMode: CohereTranscribeDecoderMode, maxNewTokens: Int?,
                    language: String, promptIDs: [Int]?) -> CohereTranscriptionResult {
        inputs.append(audioSamples); languages.append(language)
        return responses[min(inputs.count - 1, responses.count - 1)]
    }
    func unload() { unloads += 1 }
}

private final class DiskStub: @unchecked Sendable {
    private let lock = NSLock()
    private var free: Int64 = 100_000_000_000
    private var mustBeAbsent: [URL] = []
    func requireAbsent(_ urls: [URL]) { lock.withLock { mustBeAbsent = urls } }
    func set(_ n: Int64) { lock.withLock { free = n } }
    func inspect(_ url: URL) -> ModelDiskLocation {
        lock.withLock {
            for item in mustBeAbsent { #expect(!FileManager.default.fileExists(atPath: item.path)) }
            return ModelDiskLocation(volume: "test", freeBytes: free)
        }
    }
}

private func engineStore(_ disk: DiskStub = DiskStub()) throws -> ModelStore {
    let store = isolatedModelStore(model: .cohereTranscribe6bit,
                          directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)"),
                          diskSpace: { disk.inspect($0) })
    for (name, size) in store.model.manifest.files {
        let url = store.modelDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(size)); try file.close()
    }
    try writeCohereManifestFixture(store)
    return store
}

@Suite struct CohereEngineTests {
    @Test func keepsLockUntilUnloadAndLoadsWithMeasuredUnits() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: RuntimeStub())
        // Osobny silnik dla sprawdzenia przekazanej konfiguracji i odcisku.
        let configured = CohereEngine(store: store, runtime: runtime)
        try await configured.load()
        #expect(await runtime.loads == 1)
        #expect(await runtime.fingerprint == store.fingerprint())
        let units = try #require(await runtime.configuration)
        #expect(units.encoder == .cpuOnly)
        #expect(units.frontend == .cpuAndNeuralEngine && units.decoder == .cpuAndNeuralEngine && units.crossKV == .cpuAndNeuralEngine)
        #expect(throws: ModelStoreError.self) { try store.acquireLock() }
        #expect(throws: ModelStoreError.self) { try store.remove() }
        await #expect(throws: ModelStoreError.self) { try await engine.load() }
        await configured.unload()
        try await engine.load()
        await engine.unload()
        let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
    }

    @Test func diskIsCheckedOnEveryRealLoadIncludingCompleteCompiledCache() async throws {
        let disk = DiskStub(), store = try engineStore(disk)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let fingerprint = try #require(store.fingerprint())
        let key = CohereModelCompilation.key(fingerprint: fingerprint, configuration: .yascribe)
        for package in try CohereTranscribeAsrModels.loadManifest(from: store.modelDirectory).packages {
            _ = try CohereModelCompilation.compile(package: store.modelDirectory.appendingPathComponent(package), root: store.compiledDirectory, key: key, compiler: { _ in
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                for name in ["coremldata.bin", "model.mil"] { try Data([1]).write(to: tmp.appendingPathComponent(name)) }
                return tmp
            })
        }
        #expect(store.compiledModelsReady())
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
        disk.set(7_000_000_000)
        try await engine.load(); await engine.unload()
        disk.set(1)
        await #expect(throws: ModelStoreError.self) { try await engine.load() }
        #expect(await runtime.loads == 1)
        let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
    }

    @Test func emptyOrPartialCompiledCacheStillNeedsCompilationBudget() async throws {
        let disk = DiskStub(), store = try engineStore(disk)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let key = CohereModelCompilation.key(fingerprint: try #require(store.fingerprint()), configuration: .yascribe)
        for name in ["", key + "/cohere_frontend.mlmodelc"] {
            try FileManager.default.createDirectory(at: store.compiledDirectory.appendingPathComponent(name), withIntermediateDirectories: true)
            disk.set(7_000_000_000) // E5RT + zapas mieści się; kompilacja + TMP już nie.
            let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
            await #expect(throws: ModelStoreError.self) { try await engine.load() }
            #expect(await runtime.loads == 0)
        }
    }

    @Test func failedLoadingReleasesLockAndUnloadsRuntime() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub(failsLoading: true), engine = CohereEngine(store: store, runtime: runtime)
        await #expect(throws: ModelStoreError.self) { try await engine.load() }
        #expect(await runtime.unloads == 1)
        let owner = try store.acquireLock(); withExtendedLifetime(owner) {}
    }

    @Test func energyUsesFramesBeforePaddingAndDoesNotDiluteShortQuietSpeech() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
        try await engine.load()
        let silent = try await engine.transcribe(samples: [Float](repeating: 0, count: 192_000), language: .polish)
        #expect(silent.text.isEmpty && silent.words.isEmpty)
        #expect(await runtime.inputs.isEmpty)
        var samples = [Float](repeating: 0, count: 192_000)
        samples.replaceSubrange(80_000..<83_200, with: repeatElement(Float(0.008), count: 3_200))
        let speech = try await engine.transcribe(samples: samples, language: .polish)
        #expect(speech.text == "gotowe" && speech.words.isEmpty)
        #expect(await runtime.inputs == [samples])
        #expect(await runtime.languages == ["pl"])
        await engine.unload()
    }

    @Test func echoAfterAECProducesCompletedEmptyWindowsAndResumeNeverCallsModelAgain() async throws {
        try await exerciseAEC(nearSpeech: false)
    }

    @Test func quietRealSpeechAfterAECStillReachesRuntime() async throws {
        try await exerciseAEC(nearSpeech: true)
    }

    private func exerciseAEC(nearSpeech: Bool) async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = store.directory.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let rate = 16_000, n = 12 * rate
        var state: UInt64 = 100
        var memory: Float = 0
        let far: [Float] = (0..<n).map { i in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let random = Float(Int((state >> 32) % 65536) - 32768) / 32768
            memory = 0.8 * memory + 0.2 * random
            return memory * Float(0.1 + 0.1 * sin(Double(i)/16_000*2))
        }
        var mic = far.indices.map { $0 >= 333 ? 0.5 * far[$0 - 333] : 0 }
        if nearSpeech {
            // Prawdziwa mowa z polskiego klipu, 250 ms przy RMS -40 dBFS po ustaleniu AEC.
            let clip = try WAVDecoder.samples(ProbeClips.polish.wav)
            let start = try #require(clip.indices.first { abs(clip[$0]) > 0.05 })
            let speech = Array(clip.dropFirst(start).prefix(4_000))
            try #require(speech.count == 4_000)
            let rms = sqrt(speech.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(speech.count))
            for i in speech.indices { mic[9 * rate + i] += speech[i] * Float(0.01 / rms) }
        }
        let journal = try SessionJournal(url: session.appendingPathComponent("journal.jsonl"))
        try journal.append(.sessionStarted(hostTime: 1_000_000_000, timebase: .init(numer: 1, denom: 1), wallClock: Date(timeIntervalSince1970: 0)))
        for (id, signal) in [("system", far), ("mic_raw", mic)] {
            // Stały nagłówek CAF: PCM Int16 LE, mono 16 kHz, data do EOF.
            var data = Data(base64Encoded: "Y2FmZgABAABkZXNjAAAAAAAAACBAz0AAAAAAAGxwY20AAAACAAAAAgAAAAEAAAABAAAAEGRhdGH//////////wAAAAA=")!
            let pcm = signal.map { Int16(($0 * 32_767).rounded()) }
            pcm.withUnsafeBufferPointer { data.append(UnsafeRawBufferPointer($0).bindMemory(to: UInt8.self)) }
            try data.write(to: session.appendingPathComponent("\(id).caf"))
            try journal.append(.trackOpened(id, hostTime: 1_000_000_000, sampleRate: 16_000, channels: 1, deviceUID: id))
            try journal.append(.trackFirstSample(id, hostTime: 1_000_000_000))
            try journal.append(.trackClock(id, frameIndex: n, hostTime: 13_000_000_000))
            try journal.append(.trackClosed(id, frames: n, hostTime: 13_000_000_000))
        }
        try journal.append(.sessionEnded(reason: "test", hostTime: 13_000_000_000))
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
        let provider = Provider(name: "local test", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
        let client = LocalASRClient(provider: provider, engine: engine, store: store)
        let preset = Preset(name: "test", language: .polish, asr: RoleAssignment(providerID: provider.id, model: store.model.id))
        let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil, modelFingerprint: store.fingerprint())
        var crosstalk = CrosstalkFilter(); crosstalk.correlationThreshold = 2
        let first = try await TranscriptionRunner(session: session, runID: "aec", snapshot: snapshot, client: client,
                                                  maxChunkSeconds: 3, crosstalk: crosstalk).run()
        #expect(first.failedChunks.isEmpty)
        let run = RunDirectory(session: session, runID: "aec")
        let files = try FileManager.default.contentsOfDirectory(at: run.url.appendingPathComponent("chunks"), includingPropertiesForKeys: nil)
        let results = try files.map { try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: $0)) }
        let quiet = results.filter { $0.track == "mic_raw" && $0.chunk.sourceStartSeconds >= 3 }
        #expect(!quiet.isEmpty)
        if nearSpeech {
            let spoken = quiet.filter { $0.chunk.sourceEndSeconds > 9 && $0.chunk.sourceStartSeconds < 9.25 }
            #expect(!spoken.isEmpty && spoken.allSatisfy { !$0.result.text.isEmpty })
        } else {
            #expect(quiet.allSatisfy { $0.result.text.isEmpty && $0.result.words == [] })
        }
        let before = await runtime.inputs.count
        #expect(before > 0 && before < results.count)
        let second = try await TranscriptionRunner(session: session, runID: "aec", snapshot: snapshot, client: client).run()
        #expect(second == first)
        #expect(await runtime.inputs.count == before)
        let metadata = try #require(try JSONFile.load(RunMetadata?.self, from: run.metadata, default: nil))
        #expect(metadata.requestCount == 0 && metadata.offlineAEC?.disposition == .applied)
        await client.release()
    }

    @Test func splitSearchUses100msFramesInLastThreeSecondsOfHalf() {
        var samples = [Float](repeating: 0.2, count: 192_000)
        samples.replaceSubrange(16_000..<17_600, with: repeatElement(0, count: 1_600)) // poza obszarem szukania
        samples.replaceSubrange(64_000..<65_600, with: repeatElement(0.001, count: 1_600))
        #expect(CohereEngine.retrySplit(samples) == 64_800)
        #expect(CohereEngine.retrySplit([0]) == nil)
    }

    @Test func missingEOSRetriesOnlyOnceWithNoSampleLossAndPreservesLanguage() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub([.init(text: "ucięte", chunkEOS: [false]), .init(text: "pierwsza", chunkEOS: [true]), .init(text: "druga", chunkEOS: [true])])
        let engine = CohereEngine(store: store, runtime: runtime)
        try await engine.load()
        let samples = [Float](repeating: 0.1, count: 192_000)
        let result = try await engine.transcribe(samples: samples, language: .english)
        #expect(result.text == "pierwsza druga" && result.words.isEmpty)
        let inputs = await runtime.inputs
        try #require(inputs.count == 3)
        #expect(inputs[1] + inputs[2] == samples)
        #expect(await runtime.languages == ["en", "en", "en"])
        await engine.unload()
    }

    @Test func emptyEOSAndRepeatedTruncationAreErrors() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        for eos: [Bool] in [[], [false]] {
            let runtime = RuntimeStub([.init(text: "ucięte", chunkEOS: eos)])
            let engine = CohereEngine(store: store, runtime: runtime)
            try await engine.load()
            do {
                _ = try await engine.transcribe(samples: [Float](repeating: 0.1, count: 32_000), language: .polish)
                Issue.record("Expected text was cut")
            } catch let ProviderError.badResponse(message) { #expect(message.contains("text was cut")) }
            #expect(await runtime.inputs.count == 2)
            await engine.unload()
        }
    }
}

private actor Signal {
    private var sent = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if sent { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func send() { sent = true; let pending = waiting; waiting = []; for c in pending { c.resume() } }
}

private actor SlowRuntime: CohereRuntime {
    let loadEntered = Signal(), loadRelease = Signal(), cancelled = Signal()
    let unloadEntered = Signal(), unloadRelease = Signal()
    var loads = 0
    var ready = false
    func loadModels(from directory: URL, compiledDirectory: URL, fingerprint: String,
                    computeConfiguration: CohereTranscribeComputeConfiguration, lock: ModelStoreLock) async throws {
        loads += 1
        if loads == 1 {
            await loadEntered.send()
            await withTaskCancellationHandler { await loadRelease.wait() } onCancel: {
                Task { await self.cancelled.send() }
            }
        }
        ready = true
    }
    func unload() async {
        await unloadEntered.send()
        await unloadRelease.wait()
        ready = false
    }
    func transcribe(audioSamples: [Float], decoderMode: CohereTranscribeDecoderMode, maxNewTokens: Int?,
                    language: String, promptIDs: [Int]?) throws -> CohereTranscriptionResult {
        guard ready else { throw ModelStoreError(message: "runtime not loaded") }
        return .init(text: "gotowe", chunkEOS: [true])
    }
}

extension CohereEngineTests {
    @Test func concurrentLoadDuringUnloadWaitsAndReloadsRuntime() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = SlowRuntime(), engine = CohereEngine(store: store, runtime: runtime)
        let first = Task { try await engine.load() }
        await runtime.loadEntered.wait()
        await runtime.loadRelease.send()
        try await first.value
        let unloading = Task { await engine.unload() }
        await runtime.unloadEntered.wait()
        let started = Signal()
        let second = Task { await started.send(); try await engine.load() }
        await started.wait()
        for _ in 0..<100 { await Task.yield() }
        await runtime.unloadRelease.send()
        await unloading.value
        try await second.value
        #expect(await runtime.loads == 2)
        #expect(throws: ModelStoreError.self) { try store.acquireLock() }
        #expect(try await engine.transcribe(samples: [Float](repeating: 0.1, count: 16000), language: .polish).text == "gotowe")
        await engine.unload()
    }

    @Test func unloadDuringPendingLoadInvalidatesItsGenerationAndNextLoadSucceeds() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = SlowRuntime(), engine = CohereEngine(store: store, runtime: runtime)
        let first = Task { try await engine.load() }
        await runtime.loadEntered.wait()
        let unloading = Task { await engine.unload() }
        await runtime.cancelled.wait()
        let second = Task { try await engine.load() }
        await runtime.loadRelease.send()
        await runtime.unloadEntered.wait()
        await runtime.unloadRelease.send()
        await unloading.value
        do { try await first.value; Issue.record("Interrupted load must fail") } catch is CancellationError {}
        try await second.value
        #expect(await runtime.loads == 2)
        #expect(throws: ModelStoreError.self) { try store.acquireLock() }
        await engine.unload()
    }

    @Test func wrongStoreMissingSourceAndMissingLanguageRefuseBeforeDecode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for model in LocalASRModel.allCases {
            let runtime = RuntimeStub()
            let store = isolatedModelStore(model: model, directory: root)
            let engine = CohereEngine(store: store, runtime: runtime)
            do { try await engine.load(); Issue.record("Invalid store must fail") }
            catch let error as ModelStoreError {
                #expect(error.message.contains(model == .parakeetV3 ? "own model store" : "missing"))
            }
            #expect(await runtime.loads == 0)
        }
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
        try await engine.load()
        do { _ = try await engine.transcribe(samples: [0.1], language: nil); Issue.record("Explicit language required") }
        catch let ProviderError.badResponse(message) { #expect(message.contains("explicit language")) }
        #expect(await runtime.inputs.isEmpty)
        await engine.unload()
    }

    @Test func noiseAboveThresholdCallsModelAndSilentRetryHalfDoesNot() async throws {
        let store = try engineStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let runtime = RuntimeStub([.init(text: "ucięte", chunkEOS: [false]), .init(text: "mowa", chunkEOS: [true])])
        let engine = CohereEngine(store: store, runtime: runtime)
        try await engine.load()
        var samples = (0..<8000).map { Float($0 % 17 - 8) * 0.003 }
        samples += [Float](repeating: 0, count: 24000)
        #expect(try await engine.transcribe(samples: samples, language: .polish).text == "mowa")
        #expect(await runtime.inputs.count == 2)
        await engine.unload()
    }

    @Test func loadCleansAbandonedCompilationBeforeDiskInspection() async throws {
        let disk = DiskStub(), store = try engineStore(disk); defer { try? FileManager.default.removeItem(at: store.directory) }
        for name in ["obsolete", ".staging-orphan"] {
            try FileManager.default.createDirectory(at: store.compiledDirectory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        disk.requireAbsent(["obsolete", ".staging-orphan"].map { store.compiledDirectory.appendingPathComponent($0) })
        let runtime = RuntimeStub(), engine = CohereEngine(store: store, runtime: runtime)
        try await engine.load()
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.compiledDirectory.path).isEmpty)
        await engine.unload()
    }
}
