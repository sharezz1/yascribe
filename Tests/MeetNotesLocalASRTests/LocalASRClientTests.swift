import Foundation
import Testing
import MeetNotesProviders
import MeetNotesTranscription
@testable import MeetNotesLocalASR

/// Atrapa silnika: liczy wywołania, nic nie wymaga modelu.
private actor FakeEngine: LocalASREngine {
    private(set) var loads = 0
    private(set) var unloads = 0
    private(set) var transcribed: [Int] = []
    let result = (text: "dzień dobry", words: [TranscribedWord(word: "dzień", start: 0.1, end: 0.4), TranscribedWord(word: "dobry", start: 0.5, end: 0.9)])
    func load() async throws { loads += 1; try await Task.sleep(nanoseconds: 20_000_000) }
    func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]) { transcribed.append(samples.count); return result }
    func unload() async { unloads += 1 }
}

private final class Phases: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [LocalASRPhase] = []
    func add(_ p: LocalASRPhase) { lock.lock(); seen.append(p); lock.unlock() }
    var all: [LocalASRPhase] { lock.lock(); defer { lock.unlock() }; return seen }
}

/// Pełny model z manifestu (pliki rzadkie o dokładnych rozmiarach) w `mn-<UUID>`, żeby `status() == .ready`.
private func readyStore() throws -> ModelStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let store = ModelStore(directory: root, download: { _, _, _ in })
    for (file, size) in ModelManifest.parakeetV3.files {
        let url = store.modelDirectory.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: UInt64(size))
        try h.close()
    }
    return store
}

private func emptyStore() -> ModelStore {
    ModelStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true),
               download: { _, _, _ in })
}

private let provider = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)

private func wav(seconds: Double) -> Data { WAVEncoder.wav([Int16](repeating: 1_000, count: Int(seconds * 16_000)), rate: 16_000) }

private func client(_ engine: FakeEngine, store: ModelStore, phases: Phases = Phases()) -> LocalASRClient {
    LocalASRClient(provider: provider, engine: engine, store: store, onPhase: { phases.add($0) })
}

@Test func returnsTextAndWordTimings() async throws {
    let c = client(FakeEngine(), store: try readyStore())
    let r = try await c.transcribe(wav: wav(seconds: 1), model: "parakeet-tdt-0.6b-v3", language: .polish, shape: .audioTranscriptions)
    #expect(r.text == "dzień dobry")
    #expect(r.words == [TranscribedWord(word: "dzień", start: 0.1, end: 0.4), TranscribedWord(word: "dobry", start: 0.5, end: 0.9)])
}

@Test func loadsLazilyOnceAcrossRequests() async throws {
    let engine = FakeEngine()
    let c = client(engine, store: try readyStore())
    #expect(await engine.loads == 0)
    // trzy równoległe żądania + jedno po nich: jedno ładowanie
    try await withThrowingTaskGroup(of: Void.self) { g in
        for _ in 0..<3 { g.addTask { _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) } }
        try await g.waitForAll()
    }
    _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(await engine.loads == 1)
}

@Test func reportsPreparingAroundTheFirstLoadOnly() async throws {
    let phases = Phases()
    let c = client(FakeEngine(), store: try readyStore(), phases: phases)
    for _ in 0..<2 { _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    #expect(phases.all == [.preparing, .ready])
}

@Test func releaseUnloadsAndNextRequestLoadsAgain() async throws {
    let engine = FakeEngine()
    let phases = Phases()
    let c = client(engine, store: try readyStore(), phases: phases)
    _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    await c.release()
    #expect(await engine.unloads == 1)
    _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(await engine.loads == 2)
    #expect(phases.all == [.preparing, .ready, .preparing, .ready])
}

@Test func ignoresTheLanguageParameter() async throws {
    let c = client(FakeEngine(), store: try readyStore())
    let pl = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: .polish, shape: .audioTranscriptions)
    let en = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: .english, shape: .audioTranscriptions)
    let none = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(pl == en && en == none)
}

@Test func chatShapeIsRejected() async throws {
    let engine = FakeEngine()
    let c = client(engine, store: try readyStore())
    await #expect(throws: ProviderError.self) { _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .chatAudio) }
    #expect(await engine.loads == 0)
}

@Test func refusesToTranscribeWhenStoreIsNotReady() async throws {
    let engine = FakeEngine()
    let c = client(engine, store: emptyStore())
    do {
        _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
        Issue.record("expected a refusal")
    } catch let ProviderError.badResponse(reason) {
        #expect(reason.contains("isn't downloaded"))
    }
    #expect(await engine.loads == 0)
    #expect(await engine.transcribed.isEmpty)
}

@Test func windowShorterThan300msIsEmptyNotAnError() async throws {
    let engine = FakeEngine()
    let c = client(engine, store: try readyStore())
    let r = try await c.transcribe(wav: wav(seconds: 0.29), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(r == TranscriptionResult(text: "", words: []))
    #expect(await engine.loads == 0)
    #expect(await engine.transcribed.isEmpty)
    // dokładnie 300 ms idzie już do silnika
    _ = try await c.transcribe(wav: wav(seconds: 0.3), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(await engine.transcribed == [4_800])
}
