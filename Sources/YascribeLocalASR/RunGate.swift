import Foundation
import YascribeProviders
import YascribeTranscription

/// Odmowa startu lokalnego przebiegu. Nie ma ścieżki „zamiast tego do API" — wołający pokazuje `message` i na tym koniec.
public struct RunGateRefusal: Error, Equatable, Sendable {
    public var message: String
    /// `true` = przycisk „Download" naprawia sprawę (brak modelu albo uszkodzony).
    public var canDownload: Bool

    public init(message: String, canDownload: Bool) {
        self.message = message
        self.canDownload = canDownload
    }
}

/// Bramki lokalnego ASR (spec 2.0a §4.2): czy wolno ruszyć i czy wolno wznowić. Czyste funkcje — logika poza aplikacją, bo ta nie ma testów.
public enum RunGate {
    /// `nil` = wolno.
    public static func check(status: ModelStatus) -> RunGateRefusal? {
        switch status {
        case .ready: nil
        case .missing: RunGateRefusal(message: "The on-device speech model isn't downloaded yet. Download it in Settings.", canDownload: true)
        case .invalid(let reason): RunGateRefusal(message: "The on-device speech model failed its check: \(reason). Download it again.", canDownload: true)
        case .unknownVariant(let reason): RunGateRefusal(message: "Another app stored a different variant of this model: \(reason).", canDownload: false)
        }
    }

    /// `AppModel.resume` podaje do runnera ZAPISANĄ migawkę, więc `RunError.inputMismatch` nie złapie zmiany modelu — ta bramka tak.
    /// Dotyczy tylko `.fluidAudio` z zapisanym odciskiem; przebiegi API ignorują odcisk.
    public static func checkResume(snapshot: RunSnapshot, provider: Provider, currentFingerprint: String?) -> RunGateRefusal? {
        guard provider.api == .fluidAudio, let saved = snapshot.modelFingerprint, saved != currentFingerprint else { return nil }
        return RunGateRefusal(message: "The on-device model changed since this run. Start a new transcription.", canDownload: false)
    }

    /// Odcisk do migawki nowego przebiegu: tylko dla `.fluidAudio`.
    public static func fingerprintForSnapshot(provider: Provider, store: ModelStore) -> String? {
        provider.api == .fluidAudio ? store.fingerprint() : nil
    }
}

public enum LocalASRFactory {
    /// Klient lokalnego ASR albo odmowa. Przy odmowie nie powstaje żaden klient — nie ma czym wysłać do API.
    /// `engine == nil` = prawdziwy `FluidAudioEngine`; testy podają atrapę.
    public static func client(provider: Provider, store: ModelStore, engine: (any LocalASREngine)? = nil,
                              onPhase: @escaping @Sendable (LocalASRPhase) -> Void = { _ in }) -> Result<any TranscriptionClient, RunGateRefusal> {
        if let refusal = RunGate.check(status: store.status()) { return .failure(refusal) }
        return .success(LocalASRClient(provider: provider, engine: engine ?? FluidAudioEngine(store: store), store: store, onPhase: onPhase))
    }
}
