import FluidAudio
import Foundation
import MeetNotesProviders

/// Silnik Parakeet v3 (FluidAudio 0.17.7, API wg S0 §8). Ładuje WYŁĄCZNIE przez `loadLocal` — pozostałe warianty ładowania
/// idą przez ModelHub i potrafią dociągać pliki z HF bez zgody użytkownika (decyzja 7a; pilnuje tego `LocalASRNetworkGuardTests`).
/// Brak pliku = lokalny `modelNotFound`.
public actor FluidAudioEngine: LocalASREngine {
    private let store: ModelStore
    private var manager: AsrManager?

    public init(store: ModelStore) { self.store = store }

    /// Synchroniczne ładowanie (~19 s na zimno) idzie na aktorze silnika, nigdy na MainActor.
    public func load() async throws {
        if manager != nil { return }
        let m = AsrManager(config: .default)
        // `AsrModels` nie wychodzi poza to wyrażenie — inaczej `cleanup()` nie zwolni pamięci.
        try await m.loadModels(try AsrModels.loadLocal(from: store.modelDirectory, version: .v3, encoderPrecision: .int8))
        manager = m
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
