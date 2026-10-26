import Foundation
import Testing
import YascribeProviders
import YascribeTranscription
@testable import YascribeLocalASR

/// Atrapa silnika: liczy wywołania, nic nie wymaga modelu. `gated` zawiesza `load()` na kontynuacji sterowanej przez test;
/// `failure` sprawia, że `load()` rzuca. `isLoaded` odpowiada „model w pamięci".
private actor FakeEngine: LocalASREngine {
    private(set) var loads = 0
    private(set) var unloads = 0
    private(set) var transcribed: [Int] = []
    private(set) var isLoaded = false
    private(set) var unloadedWhileLoading = false
    private var loadInFlight = false
    private var gate: CheckedContinuation<Void, Never>?
    private let gated: Bool
    private let failure: (any Error)?
    let result = (text: "dzień dobry", words: [TranscribedWord(word: "dzień", start: 0.1, end: 0.4), TranscribedWord(word: "dobry", start: 0.5, end: 0.9)])

    init(gated: Bool = false, failure: (any Error)? = nil) {
        self.gated = gated
        self.failure = failure
    }

    func isSuspended(atLoad n: Int) -> Bool { gate != nil && loads == n }
    func openGate() { gate?.resume(); gate = nil }

    func load() async throws {
        loads += 1
        loadInFlight = true
        defer { loadInFlight = false }
        if gated { await withCheckedContinuation { gate = $0 } } else { try await Task.sleep(nanoseconds: 20_000_000) }
        if let failure { throw failure }
        isLoaded = true
    }
    func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]) { transcribed.append(samples.count); return result }
    func unload() async {
        unloads += 1
        if loadInFlight { unloadedWhileLoading = true }
        isLoaded = false
    }
}

private struct LoadBoom: Error, LocalizedError { var errorDescription: String? { "boom" } }

private func waitUntilSuspended(_ engine: FakeEngine, atLoad n: Int = 1) async {
    while true {
        if await engine.isSuspended(atLoad: n) { return }
        await Task.yield()
    }
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
    #expect(phases.all == [.preparing, .ready, .idle, .preparing, .ready])
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

@Test func releaseDuringLoadWaitsForItAndLeavesNothingInMemory() async throws {
    let engine = FakeEngine(gated: true)
    let phases = Phases()
    let c = client(engine, store: try readyStore(), phases: phases)
    let request = Task { try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    await waitUntilSuspended(engine)
    let release = Task { await c.release() }
    try await Task.sleep(nanoseconds: 50_000_000) // release zdąży ruszyć i (przed poprawką) zwolnić silnik w trakcie ładowania
    await engine.openGate()
    await release.value
    #expect(await !engine.unloadedWhileLoading, "release() must not unload before the pending load finishes")
    #expect(await !engine.isLoaded, "the model must not stay in memory after release()")
    #expect(await engine.unloads == 1)
    do { _ = try await request.value } catch is CancellationError {} // żądanie z tej generacji kończy się anulowaniem (albo zdążyło przed release)
    #expect(phases.all.last == .idle)
    // klient działa dalej: następne żądanie ładuje od nowa (brama silnika jest już zużyta, więc otwieramy ją drugi raz)
    let next = Task { try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    await waitUntilSuspended(engine, atLoad: 2)
    await engine.openGate()
    _ = try await next.value
    #expect(await engine.loads == 2)
}

@Test func failedLoadIsRememberedAndNotRetriedUntilRelease() async throws {
    let engine = FakeEngine(failure: LoadBoom())
    let phases = Phases()
    let c = client(engine, store: try readyStore(), phases: phases)
    for _ in 0..<3 {
        await #expect(throws: LoadBoom.self) { _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    }
    #expect(await engine.loads == 1, "later windows must rethrow the first failure instead of loading again")
    #expect(phases.all == [.preparing, .failed("boom")])
    await c.release()
    #expect(phases.all.last == .idle)
    await #expect(throws: LoadBoom.self) { _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    #expect(await engine.loads == 2, "release() clears the remembered failure")
}

@Test func concurrentRequestsShareOneFailedLoad() async throws {
    let engine = FakeEngine(failure: LoadBoom())
    let phases = Phases()
    let c = client(engine, store: try readyStore(), phases: phases)
    let tasks = (0..<3).map { _ in Task { try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) } }
    for t in tasks { await #expect(throws: LoadBoom.self) { _ = try await t.value } }
    #expect(await engine.loads == 1)
    #expect(phases.all == [.preparing, .failed("boom")])
}

@Test func cancelledRequestDoesNotTranscribeAfterTheLoad() async throws {
    let engine = FakeEngine(gated: true)
    let c = client(engine, store: try readyStore())
    let request = Task { try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions) }
    await waitUntilSuspended(engine)
    request.cancel()
    await engine.openGate()
    await #expect(throws: CancellationError.self) { _ = try await request.value }
    #expect(await engine.transcribed.isEmpty)
    // załadowany model zostaje: następne żądanie nie ładuje drugi raz
    _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    #expect(await engine.loads == 1)
}

@Test func cancelledRequestOnAnAlreadyLoadedModelDoesNotTranscribe() async throws {
    let engine = FakeEngine()
    let c = client(engine, store: try readyStore())
    _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    let request = Task {
        while !Task.isCancelled { await Task.yield() }
        return try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
    }
    request.cancel()
    await #expect(throws: CancellationError.self) { _ = try await request.value }
    #expect(await engine.transcribed.count == 1)
}

private func refusal(_ c: LocalASRClient) async -> String? {
    do {
        _ = try await c.transcribe(wav: wav(seconds: 1), model: "m", language: nil, shape: .audioTranscriptions)
        return nil
    } catch let ProviderError.badResponse(reason) {
        return reason
    } catch {
        return "unexpected \(error)"
    }
}

@Test func refusesWhenTheStoreIsInvalid() async throws {
    let store = try readyStore()
    let target = store.modelDirectory.appendingPathComponent("Decoder.mlmodelc/model.mil")
    let h = try FileHandle(forWritingTo: target)
    try h.truncate(atOffset: 3)
    try h.close()
    let engine = FakeEngine()
    let reason = await refusal(client(engine, store: store))
    #expect(reason?.contains("failed its check") == true)
    #expect(reason?.contains("Decoder.mlmodelc/model.mil") == true)
    #expect(await engine.loads == 0)
}

@Test func refusesWhenTheStoreHoldsAnotherVariant() async throws {
    let store = try readyStore()
    let fm = FileManager.default
    try fm.removeItem(at: store.modelDirectory.appendingPathComponent("Encoder.mlmodelc"))
    let other = store.modelDirectory.appendingPathComponent("Encoder_v2.mlmodelc/weights", isDirectory: true)
    try fm.createDirectory(at: other, withIntermediateDirectories: true)
    fm.createFile(atPath: other.appendingPathComponent("weight.bin").path, contents: Data([1]))
    let engine = FakeEngine()
    let reason = await refusal(client(engine, store: store))
    #expect(reason?.contains("different variant") == true)
    #expect(await engine.loads == 0)
}
