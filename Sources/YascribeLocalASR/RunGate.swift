import Foundation
import YascribeProviders
import YascribeTranscription

/// Odmowa startu lokalnego przebiegu. Nie ma ścieżki „zamiast tego do API" — wołający pokazuje `message` i na tym koniec.
public struct RunGateRefusal: Error, LocalizedError, CustomStringConvertible, Equatable, Sendable {
    public var errorDescription: String? { message }
    public var description: String { message }
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

    public static func checkLanguage(model: LocalASRModel, language: LanguageCode?) -> RunGateRefusal? {
        guard let supported = model.supportedLanguages else { return nil }
        guard let language else {
            return RunGateRefusal(message: "Cohere requires an explicit language. Auto is not supported.", canDownload: false)
        }
        guard supported.contains(language.rawValue) else {
            return RunGateRefusal(message: "Cohere does not support language \(language.rawValue).", canDownload: false)
        }
        return nil
    }

    public static func checkDisk(need: [ModelDiskNeed]) -> RunGateRefusal? {
        guard let insufficient = need.first(where: { !$0.fits }) else { return nil }
        return RunGateRefusal(message: insufficient.message, canDownload: false)
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
    /// Blokada i rezerwacja są utrzymywane od kontroli źródeł do release(), także przed leniwym load().
    public static func client(provider: Provider, model: String, store: ModelStore? = nil,
                              engine: (any LocalASREngine)? = nil, reservations: LocalASRReservations? = nil,
                              onPhase: @escaping @Sendable (LocalASRPhase) -> Void = { _ in }) -> Result<any TranscriptionClient, RunGateRefusal> {
        do {
            let selected = try LocalASRModel(id: model)
            let store = store ?? ModelStore(model: selected)
            guard store.model == selected else {
                throw RunGateRefusal(message: "The on-device model store does not match \(model).", canDownload: false)
            }
            let reservation = try reservations?.acquire(model: selected)
            // Parakeet tylko czyta: wielu klientów naraz (sesje, dyktowanie, sonda, CLI). Cohere kompiluje do compiled/, więc LOCK_EX.
            let owner = try store.acquireLock(shared: selected == .parakeetV3)
            if let refusal = RunGate.check(status: store.status()) { throw refusal }
            if selected == .cohereTranscribe6bit, let refusal = RunGate.checkDisk(need: try store.diskNeed(operation: .load)) { throw refusal }
            let selectedEngine: any LocalASREngine = engine ?? makeEngine(model: selected, store: store, owner: owner)
            return .success(LocalASRClient(provider: provider, engine: selectedEngine, store: store,
                                           owner: owner, reservation: reservation, onPhase: onPhase))
        } catch let refusal as RunGateRefusal { return .failure(refusal) }
        catch { return .failure(RunGateRefusal(message: error.localizedDescription, canDownload: false)) }
    }

    static func makeEngine(model: LocalASRModel, store: ModelStore, owner: ModelStoreLock? = nil) -> any LocalASREngine {
        switch model.engineKind {
        case .parakeet: FluidAudioEngine(store: store)
        case .cohere: CohereEngine(store: store, owner: owner)
        }
    }
}
