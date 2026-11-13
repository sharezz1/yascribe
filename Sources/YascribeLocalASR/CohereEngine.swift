import Foundation
import YascribeProviders
import YascribeTranscription

/// Szew testowy potoku Core ML; modele i bufory pozostają własnością aktora managera.
protocol CohereRuntime: Sendable {
    func loadModels(from directory: URL, compiledDirectory: URL, fingerprint: String,
                    computeConfiguration: CohereTranscribeComputeConfiguration) async throws
    func transcribe(audioSamples: [Float], decoderMode: CohereTranscribeDecoderMode, maxNewTokens: Int?,
                    language: String, promptIDs: [Int]?) async throws -> CohereTranscriptionResult
    func unload() async
}

extension CohereTranscribeAsrManager: CohereRuntime {}

public actor CohereEngine: LocalASREngine {
    private let store: ModelStore
    private let runtime: any CohereRuntime
    private var owner: ModelStoreLock?
    private var loading: Task<ModelStoreLock, Error>?
    private var generation = 0

    public init(store: ModelStore) {
        self.store = store
        self.runtime = CohereTranscribeAsrManager()
    }

    init(store: ModelStore, runtime: any CohereRuntime) {
        self.store = store
        self.runtime = runtime
    }

    public func load() async throws {
        if owner != nil { return }
        let currentGeneration = generation
        let task: Task<ModelStoreLock, Error>
        if let loading { task = loading }
        else {
            let store = store, runtime = runtime
            task = Task {
                guard store.model == .cohereTranscribe6bit else {
                    throw ModelStoreError(message: "Cohere requires its own model store.")
                }
                let lock = try store.acquireLock()
                // Od statusu i odcisku do unload() nikt nie może naprawić ani usunąć źródeł.
                guard let fingerprint = store.fingerprint() else {
                    throw ModelStoreError(message: "The Cohere model is missing or failed its check.")
                }
                let budget = try store.diskNeed(operation: .load)
                if let insufficient = budget.first(where: { !$0.fits }) {
                    throw ModelStoreError(message: "Not enough disk space: need \(insufficient.bytes) bytes, available \(insufficient.freeBytes) bytes on volume \(insufficient.volume).")
                }
                do {
                    try Task.checkCancellation()
                    try await runtime.loadModels(from: store.modelDirectory, compiledDirectory: store.compiledDirectory,
                                                 fingerprint: fingerprint, computeConfiguration: .yascribe)
                    try Task.checkCancellation()
                    return lock
                } catch {
                    await runtime.unload()
                    withExtendedLifetime(lock) {}
                    throw error
                }
            }
            loading = task
        }
        do {
            let lock = try await task.value
            guard currentGeneration == generation else { throw CancellationError() }
            owner = lock
            loading = nil
        } catch {
            if currentGeneration == generation { loading = nil }
            throw error
        }
    }

    public func unload() async {
        generation += 1
        let pending = loading
        pending?.cancel()
        let pendingOwner = await pending?.result
        await runtime.unload()
        owner = nil
        loading = nil
        withExtendedLifetime(pendingOwner) {}
    }

    public func transcribe(samples: [Float], language: LanguageCode?) async throws -> (text: String, words: [TranscribedWord]) {
        guard owner != nil else { throw ProviderError.badResponse("The on-device model isn't loaded.") }
        guard let language else { throw ProviderError.badResponse("Cohere requires an explicit language.") }
        // Faktyczne próbki po AEC, przed dopełnieniem managera do 35 s. Średnia całego okna rozcieńcza krótką mowę.
        guard Self.hasSpeech(samples) else { return ("", []) }
        let first = try await decode(samples, language: language)
        if Self.completed(first) { return (first.text, []) }
        guard let cut = Self.retrySplit(samples) else {
            throw ProviderError.badResponse("Cohere text was cut.")
        }
        var texts: [String] = []
        // Tylko jeden poziom podziału; cicha połówka nie może ponownie wywołać modelu.
        for half in [Array(samples[..<cut]), Array(samples[cut...])] {
            guard Self.hasSpeech(half) else { continue }
            let result = try await decode(half, language: language)
            guard Self.completed(result) else { throw ProviderError.badResponse("Cohere text was cut.") }
            texts.append(result.text)
        }
        return (texts.filter { !$0.isEmpty }.joined(separator: " "), [])
    }

    private func decode(_ samples: [Float], language: LanguageCode) async throws -> CohereTranscriptionResult {
        try Task.checkCancellation()
        return try await runtime.transcribe(audioSamples: samples, decoderMode: .cached, maxNewTokens: nil,
                                            language: language.rawValue, promptIDs: nil)
    }

    static func completed(_ result: CohereTranscriptionResult) -> Bool {
        !result.chunkEOS.isEmpty && result.chunkEOS.allSatisfy { $0 }
    }

    static func hasSpeech(_ samples: [Float]) -> Bool {
        !EnergyGate().speechRegions(samples, rate: Resampler.asrRate).isEmpty
    }

    /// Najcichsza ramka 100 ms w ostatnich 3 s pierwszej połowy. Bez utraty i powielenia próbek.
    static func retrySplit(_ samples: [Float], rate: Int = 16_000) -> Int? {
        let frame = max(1, rate / 10), half = samples.count / 2
        guard half >= frame else { return nil }
        let start = max(0, half - 3 * rate)
        var cut = half, quietest = Double.infinity
        for offset in stride(from: start, through: half - frame, by: frame) {
            let energy = samples[offset..<(offset + frame)].reduce(0.0) { $0 + Double($1) * Double($1) }
            // Przy remisie wybieramy ramkę bliżej połowy.
            if energy <= quietest { quietest = energy; cut = offset + frame / 2 }
        }
        return cut
    }
}
