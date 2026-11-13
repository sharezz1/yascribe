import Foundation
import YascribeProviders
import YascribeTranscription

/// Czysty szew aplikacji i CLI: wejściem jest migawka presetu/argumentów lub zapisany RunInput.
/// Budowa magazynu nie czyta plików. Bramki dysku/statusu/blokady wykonuje dopiero fabryka.
public struct ASRRunConfiguration: Sendable {
    public let snapshot: RunSnapshot
    public let store: ModelStore?
    public let maxChunkSeconds: Double
    public let maxSourceSpan: Double?
    public let repetitionFilterEnabled: Bool
    public let gate: EnergyGate
    public let crosstalk: CrosstalkFilter
    public let offlineAEC: OfflineAEC.Configuration?

    public static func build(preset: Preset, provider: Provider, probe: ProbeResult? = nil) throws -> Self {
        try build(snapshot: RunSnapshot(preset: preset, provider: provider, probe: probe))
    }

    /// CLI tworzy nowe UUID. Tożsamość zapisanej migawki zachowujemy tylko przy zgodnych argumentach.
    public static func build(provider: Provider, model: String, language: LanguageCode?,
                             savedInput: RunInput? = nil, storeDirectory: URL? = nil) throws -> Self {
        let preset = Preset(id: provider.id, name: "cli", language: language, asr: RoleAssignment(providerID: provider.id, model: model),
                            languageAuto: language == nil ? true : nil)
        var snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
        if let savedInput {
            guard (savedInput.snapshot.model, savedInput.snapshot.language, savedInput.snapshot.providerBaseURL, savedInput.snapshot.shape)
                    == (snapshot.model, snapshot.language, snapshot.providerBaseURL, snapshot.shape) else { throw RunError.inputMismatch }
            snapshot = savedInput.snapshot
        }
        return try build(snapshot: snapshot, savedInput: savedInput, storeDirectory: storeDirectory)
    }

    public static func build(snapshot: RunSnapshot, savedInput: RunInput? = nil, storeDirectory: URL? = nil) throws -> Self {
        if let savedInput, savedInput.snapshot != snapshot { throw RunError.inputMismatch }
        let model = snapshot.providerBaseURL == Provider.fluidAudioBaseURL ? try LocalASRModel(id: snapshot.model) : nil
        if let model, let refusal = RunGate.checkLanguage(model: model, language: snapshot.language) { throw refusal }
        return Self(snapshot: snapshot, store: model.map { ModelStore(model: $0, directory: storeDirectory) },
                    maxChunkSeconds: savedInput?.maxChunkSeconds ?? model?.maxChunkSeconds ?? 59,
                    maxSourceSpan: savedInput.map { $0.maxSourceSpan } ?? model?.maxSourceSpan,
                    repetitionFilterEnabled: savedInput.map { $0.repetitionFilter == true } ?? (model?.repetitionFilterEnabled ?? false),
                    gate: savedInput.map { EnergyGate($0.gate) } ?? EnergyGate(),
                    crosstalk: savedInput?.crosstalk ?? CrosstalkFilter(),
                    offlineAEC: savedInput.map { $0.offlineAEC } ?? .init())
    }

    /// Wspólny krok aplikacji i CLI po utworzeniu klienta: magazyn wybrany po modelu migawki spośród `stores`, bramka
    /// wznowienia albo odcisk nowego przebiegu. Odmowa zwalnia klienta (rezerwację i blokadę), zanim wróci do wołającego.
    public func prepared(client: any TranscriptionClient, savedInput: RunInput?, stores: [ModelStore]) async throws -> Self {
        do {
            var snapshot = snapshot
            if let model = store?.model {
                guard let selected = stores.first(where: { $0.model == model }) else {
                    throw RunGateRefusal(message: "The on-device model store does not match \(model.id).", canDownload: false)
                }
                if savedInput != nil {
                    if let refusal = RunGate.checkResume(snapshot: snapshot, provider: client.provider,
                                                         currentFingerprint: selected.fingerprint()) { throw refusal }
                } else {
                    snapshot.modelFingerprint = RunGate.fingerprintForSnapshot(provider: client.provider, store: selected)
                }
            }
            return try Self.build(snapshot: snapshot, savedInput: savedInput, storeDirectory: store?.directory)
        } catch {
            await (client as? ReleasableClient)?.release()
            throw error
        }
    }

    /// Wspólny zakres własności dla aplikacji i CLI: także błąd wejścia i anulowanie zwalniają RAM/blokadę.
    public func run(session: URL, runID: String, client: any TranscriptionClient,
                    progress: @Sendable (TranscriptionProgress) -> Void = { _ in }) async throws -> Transcript {
        do {
            let result = try await runner(session: session, runID: runID, client: client).run(progress: progress)
            await (client as? ReleasableClient)?.release()
            return result
        } catch {
            await (client as? ReleasableClient)?.release()
            throw error
        }
    }

    public func runner(session: URL, runID: String, client: any TranscriptionClient) -> TranscriptionRunner {
        TranscriptionRunner(session: session, runID: runID, snapshot: snapshot, client: client,
                            maxChunkSeconds: maxChunkSeconds, maxSourceSpan: maxSourceSpan,
                            repetitionFilterEnabled: repetitionFilterEnabled, gate: gate, crosstalk: crosstalk, offlineAEC: offlineAEC)
    }
}
