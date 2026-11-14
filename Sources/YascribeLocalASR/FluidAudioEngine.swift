import FluidAudio
import Foundation
import YascribeProviders

/// Silnik Parakeet (wariant z `store`; FluidAudio 0.17.7, API wg S0 §8). Ładuje WYŁĄCZNIE przez `loadLocal` — pozostałe warianty ładowania
/// idą przez centrum pobierań FluidAudio i potrafią dociągać pliki z HF bez zgody użytkownika (decyzja 7a; pilnuje tego `LocalASRNetworkGuardTests`).
/// Brak pliku = lokalny `modelNotFound`.
public actor FluidAudioEngine: LocalASREngine {
    private let store: ModelStore
    private var manager: AsrManager?
    /// Szew dla testu: sprawdza, z jaką wersją FluidAudio silnik naprawdę ładuje wariant magazynu.
    typealias Loader = @Sendable (URL, AsrModelVersion) throws -> AsrModels
    private let loadModels: Loader

    public init(store: ModelStore) { self.init(store: store, loadModels: { try AsrModels.loadLocal(from: $0, version: $1, encoderPrecision: .int8) }) }

    init(store: ModelStore, loadModels: @escaping Loader) {
        self.store = store
        self.loadModels = loadModels
    }

    /// Ładowanie (~19 s na zimno) idzie na aktorze silnika, nigdy na MainActor. `loadLocal` jest synchroniczne i NIE da się go
    /// anulować; między jego początkiem a zapisem `manager` nie ma żadnego `await`, więc aktor nie wpuści drugiego `load()` ani
    /// `unload()` w środku (bez okna reentrancji). `AsrModels` nie wychodzi poza to wyrażenie — inaczej `cleanup()` nie zwolni pamięci.
    public func load() async throws {
        if manager != nil { return }
        manager = AsrManager(config: .default, models: try loadModels(store.modelDirectory, store.variant.asrVersion))
    }

    public func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]) {
        guard let manager else { throw ProviderError.badResponse("The on-device model isn't loaded.") }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let r = try await manager.transcribe(samples, decoderState: &state, language: nil)
        let words = buildWordTimings(from: r.tokenTimings ?? []).map { TranscribedWord(word: $0.word, start: $0.startTime, end: $0.endTime) }
        return (r.text, words)
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}
