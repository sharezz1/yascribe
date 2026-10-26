import Foundation
import YascribeProviders

/// Szew do atrapy; prawdziwy silnik to `FluidAudioEngine` (jedyny plik z `import FluidAudio` poza `ModelStore`).
public protocol LocalASREngine: Sendable {
    func load() async throws
    func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord])
    func unload() async
}

public enum LocalASRPhase: Equatable, Sendable {
    /// Pierwsze ładowanie modelu (kompilacja ANE bywa długa).
    case preparing
    case ready
    /// Ładowanie się nie udało (tekst dla użytkownika); kolejne okna tego klienta dostają ten sam błąd bez ponownego ładowania.
    case failed(String)
    /// Po `release()` — model zwolniony, nic się nie dzieje.
    case idle
}

/// Klient `TranscriptionClient` w procesie: leniwe, jednorazowe `load()`, `release()` zwalnia pamięć.
/// Nigdy nie sięga do sieci ani do API: brak modelu to błąd, nie fallback.
public actor LocalASRClient: TranscriptionClient, ReleasableClient {
    /// FluidAudio odrzuca okna krótsze niż 300 ms (`invalidAudioData`) — to pusty wynik, nie luka.
    static let minimumSamples = 4_800

    public nonisolated let provider: Provider
    private let engine: any LocalASREngine
    private let store: ModelStore
    private let onPhase: @Sendable (LocalASRPhase) -> Void
    private var loaded = false
    private var loading: Task<Void, Error>?
    /// Pierwszy błąd ładowania: kolejne okna rzucają go od razu (zamiast ~20 s ładowania na każde okno); czyści go `release()`.
    private var loadFailure: Error?
    /// Rośnie przy `release()`; ładowanie rozpoczęte w starej generacji nie ma prawa nic ustawić w nowej.
    private var generation = 0

    public init(provider: Provider, engine: any LocalASREngine, store: ModelStore,
                onPhase: @escaping @Sendable (LocalASRPhase) -> Void = { _ in }) {
        self.provider = provider
        self.engine = engine
        self.store = store
        self.onPhase = onPhase
    }

    public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        // `language` ignorowany: wskazówka FluidAudio jest tylko skryptowa, język pilnuje strażnik runnera.
        guard shape == .audioTranscriptions else {
            throw ProviderError.badResponse("On-device transcription supports only the audio transcriptions shape.")
        }
        switch store.status() {
        case .ready: break
        case .missing: throw ProviderError.badResponse("The on-device speech model isn't downloaded.")
        case .invalid(let reason): throw ProviderError.badResponse("The on-device speech model failed its check: \(reason).")
        case .unknownVariant(let reason): throw ProviderError.badResponse("Another app stored a different variant of this model: \(reason).")
        }
        let samples = try WAVDecoder.samples(wav)
        if samples.count < Self.minimumSamples { return TranscriptionResult(text: "", words: []) }
        try await ensureLoaded()
        try Task.checkCancellation()
        let r = try await engine.transcribe(samples: samples)
        return TranscriptionResult(text: r.text, words: r.words)
    }

    /// Wołać, gdy żaden przebieg nie trwa (tak robi `AppModel`). Czeka na ładowanie w toku i dopiero potem zwalnia silnik, żeby
    /// model nie został w pamięci; żądania, które czekały na to ładowanie, kończą się `CancellationError`.
    public func release() async {
        generation += 1
        let pending = loading
        loading = nil
        loaded = false
        loadFailure = nil
        pending?.cancel() // `loadLocal` jest nieprzerywalne — to tylko prośba, ładowanie i tak się dokończy
        _ = await pending?.result
        await engine.unload()
        onPhase(.idle)
    }

    // Współbieżne żądania czekają na to samo ładowanie (aktor jest reentrantny na `await`).
    private func ensureLoaded() async throws {
        if let loadFailure { throw loadFailure }
        if loaded { return }
        let myGeneration = generation
        let task: Task<Void, Error>
        if let pending = loading {
            task = pending
        } else {
            onPhase(.preparing)
            let engine = engine
            task = Task { try await engine.load() }
            loading = task
        }
        do { try await task.value } catch {
            // Po `release()` wynik starego ładowania nikogo nie obchodzi; pierwszy z oczekujących zapisuje porażkę, reszta ją powtarza.
            guard generation == myGeneration else { throw CancellationError() }
            if loading != nil {
                loading = nil
                loadFailure = error
                onPhase(.failed(error.localizedDescription))
            }
            throw error
        }
        try Task.checkCancellation() // ładowanie zostaje w `loading`; następne żądanie dokończy rejestrację bez czekania
        guard generation == myGeneration else { throw CancellationError() }
        if loading != nil {
            loading = nil
            loaded = true
            onPhase(.ready)
        }
    }
}
