import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
import YascribeTranscription
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeApp

@Suite @MainActor struct LocalASRReservationTests {
    @Test func applicationKeepsOneReservationPoolAcrossBothStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = LocalASRSupport(store: ModelStore(directory: root), cohereStore: ModelStore(model: .cohereTranscribe6bit, directory: root))
        #expect(support.store(for: .parakeetV3).model == .parakeetV3)
        #expect(support.store(for: .cohereTranscribe6bit).model == .cohereTranscribe6bit)
        let dictation = try support.reservations.acquire(model: .parakeetV3)
        #expect(throws: RunGateRefusal.self) { try support.reservations.acquire(model: .cohereTranscribe6bit) }
        support.remove()
        #expect(support.downloadError?.contains("in use") == true)
        withExtendedLifetime(dictation) {}
    }

    @Test func savedUsableCohereDictationSettingAlwaysBecomesParakeet() throws {
        let provider = Provider(name: "Local", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
        let settings = DictationSettings(asr: RoleAssignment(providerID: provider.id, model: LocalASRModels.cohereTranscribe6bit))
        let restored = try JSONDecoder().decode(DictationSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.usableASR?.model == LocalASRModels.cohereTranscribe6bit)
        #expect(restored.asrForDictation(provider: provider)?.model == LocalASRModels.parakeetV3)
        let empty = DictationSettings(asr: RoleAssignment(providerID: provider.id, model: ""))
        #expect(empty.asrForDictation(provider: provider)?.model == LocalASRModels.parakeetV3)
        let remote = Provider(name: "Remote", baseURL: URL(string: "https://example.test/v1")!)
        let remoteSettings = DictationSettings(asr: RoleAssignment(providerID: remote.id, model: "remote-model"))
        #expect(remoteSettings.asrForDictation(provider: remote)?.model == "remote-model")
    }
}

private actor PipelineEngine: LocalASREngine {
    enum Mode { case success, failure, cancellation }
    let mode: Mode
    var calls = 0
    init(_ mode: Mode) { self.mode = mode }
    func load() throws {
        if case .failure = mode { throw ProviderError.badResponse("fixture load failed") }
    }
    func transcribe(samples: [Float], language: LanguageCode?) throws -> (text: String, words: [TranscribedWord]) {
        calls += 1
        if case .cancellation = mode { throw CancellationError() }
        return ("gotowe", [])
    }
    func unload() {}
}

@MainActor private func pipelineFixture() throws -> (LocalASRSupport, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let store = ModelStore(directory: root)
    for (name, size) in store.model.manifest.files {
        let url = store.modelDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let f = try FileHandle(forWritingTo: url)
        try f.truncate(atOffset: UInt64(size)); try f.close()
    }
    return (LocalASRSupport(store: store), root)
}

extension LocalASRReservationTests {
    @Test func probeAndDictationReleaseAfterErrorOrCancellation() async throws {
        for mode in [PipelineEngine.Mode.failure, .cancellation, .success] {
            let (support, root) = try pipelineFixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let provider = Provider(name: "Local", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
            func client() throws -> any TranscriptionClient {
                try support.client(provider: provider, model: LocalASRModels.parakeetV3, language: .polish, engine: PipelineEngine(mode))
            }
            let probe = try client()
            #expect(!support.reservations.isIdle)
            _ = await support.probe(client: probe, model: LocalASRModels.parakeetV3, role: .asr, language: .polish)
            #expect(support.reservations.isIdle)
            let dictation = ReleasingTranscriber(inner: try client(), support: support)
            #expect(!support.reservations.isIdle)
            _ = try? await dictation.transcribe(wav: WAVEncoder.wav([Int16](repeating: 1000, count: 16000), rate: 16000),
                                               model: LocalASRModels.parakeetV3, language: .polish, shape: .audioTranscriptions)
            #expect(support.reservations.isIdle)
            let owner = try support.store.acquireLock(); withExtendedLifetime(owner) {}
        }
    }
}


extension LocalASRReservationTests {
    @Test func runScopeReleasesAfterFailedChunkAndCancellationAndResumesCache() async throws {
        for mode in [PipelineEngine.Mode.failure, .cancellation, .success] {
            let (support, root) = try pipelineFixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let session = root.appendingPathComponent("session"), ns = Timebase(numer: 1, denom: 1)
            let source = FileSource(trackID: "system", samples: [Int16](repeating: 1000, count: 32000), sampleRate: 16000,
                                    channels: 1, startHostTime: 1000000000, timebase: ns, chunkFrames: 1600)
            try SessionRecorder(directory: session, sources: [source], conditions: [], clock: ManualHostClock(), timebase: ns, zeroWatch: [:]).start()
            let provider = Provider(name: "Local", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
            let config = try ASRRunConfiguration.build(provider: provider, model: LocalASRModels.parakeetV3, language: .polish)
            let engine = PipelineEngine(mode)
            let client = try support.client(provider: provider, model: config.snapshot.model, language: .polish, engine: engine)
            do {
                let transcript = try await config.run(session: session, runID: "scope", client: client)
                if case .failure = mode { #expect(transcript.failedChunks.count == 1) }
                if case .cancellation = mode { Issue.record("cancelled transcription completed") }
                if case .success = mode {
                    let saved = try JSONFile.load(RunInput?.self, from: RunDirectory(session: session, runID: "scope").input, default: nil)
                    let input = try #require(saved)
                    let resumed = try ASRRunConfiguration.build(snapshot: input.snapshot, savedInput: input)
                    let cached = try await resumed.run(session: session, runID: "scope", client: client)
                    #expect(cached == transcript)
                    #expect(await engine.calls == 1)
                }
            } catch is CancellationError {
                if case .cancellation = mode {} else { Issue.record("unexpected cancellation") }
            }
            #expect(support.reservations.isIdle)
            let owner = try support.store.acquireLock(); withExtendedLifetime(owner) {}
        }
    }
}
