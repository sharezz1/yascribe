import Foundation
import MeetNotesProviders

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
        let r = try await engine.transcribe(samples: samples)
        return TranscriptionResult(text: r.text, words: r.words)
    }

    public func release() async {
        loading?.cancel()
        loading = nil
        loaded = false
        await engine.unload()
    }

    // Współbieżne żądania czekają na to samo ładowanie (aktor jest reentrantny na `await`).
    private func ensureLoaded() async throws {
        if loaded { return }
        if let loading { return try await loading.value }
        onPhase(.preparing)
        let engine = engine
        let task = Task { try await engine.load() }
        loading = task
        do { try await task.value } catch { loading = nil; throw error }
        loading = nil
        loaded = true
        onPhase(.ready)
    }
}
