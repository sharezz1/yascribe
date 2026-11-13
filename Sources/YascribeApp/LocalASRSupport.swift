import Foundation
import YascribeLocalASR
import YascribeProviders

/// Stan lokalnego ASR dla UI (karta modelu, T7): magazyn, jego status oraz faza pobierania/przygotowania.
/// Logika bramek jest w `YascribeLocalASR` (`RunGate`) i tam testowana — tu tylko stan do pokazania.
/// Model pobiera się wyłącznie przez `download()` (akcja użytkownika), nigdy w tle.
@MainActor
final class LocalASRSupport: ObservableObject {
    /// `.idle` / `.downloading(Double?)` (nil = nieokreślony, wartość nie maleje) / `.preparing` (pierwsze ładowanie, kompilacja ANE).
    typealias Phase = ModelActivity

    let store: ModelStore
    let cohereStore: ModelStore
    let reservations = LocalASRReservations()
    /// Stan per model (N4): pobieranie albo „Preparing…” Cohere nie może animować karty Parakeeta.
    @Published private(set) var phases: [LocalASRModel: Phase] = [:]
    @Published private(set) var statuses: [LocalASRModel: ModelStatus] = [:]
    /// Powód ostatniego nieudanego pobrania; czyszczony przy starcie następnego.
    @Published private(set) var downloadErrors: [LocalASRModel: String] = [:]
    private var highest: [LocalASRModel: Double] = [:]
    /// Przebiegi trzymające model (`beginRun()`…`endRun()`); póki nie zero, `remove()` odmawia.
    private var runs = ModelRunCount()

    init(store: ModelStore = ModelStore(), cohereStore: ModelStore = ModelStore(model: .cohereTranscribe6bit)) {
        self.cohereStore = cohereStore
        self.store = store
        refresh()
    }

    /// Parakeet — dotychczasowe pola karty, dyktowania i weryfikacji dostawcy.
    var phase: Phase { phase(for: .parakeetV3) }
    var status: ModelStatus { status(for: .parakeetV3) }
    var downloadError: String? { downloadErrors[.parakeetV3] }
    func phase(for model: LocalASRModel) -> Phase { phases[model] ?? .idle }
    func status(for model: LocalASRModel) -> ModelStatus { statuses[model] ?? .missing }

    func store(for model: LocalASRModel) -> ModelStore { model == .parakeetV3 ? store : cohereStore }

    func client(provider: Provider, model: String, language: LanguageCode?, engine: (any LocalASREngine)? = nil) throws -> any TranscriptionClient {
        let selected = try LocalASRModel(id: model)
        // Aplikacja uruchamia tylko modele udostępnione roli ASR (Cohere do N4 ukryty); CLI i testy wołają fabrykę wprost.
        guard LocalASRModels.models(for: .asr).contains(where: { $0.id == model }) else {
            throw RunGateRefusal(message: "The on-device model \(model) isn't available in this version of Yascribe.", canDownload: false)
        }
        if let refusal = RunGate.checkLanguage(model: selected, language: language) { throw refusal }
        return try LocalASRFactory.client(provider: provider, model: model, store: store(for: selected), engine: engine,
                                          reservations: reservations, onPhase: { [weak self] phase in
            Task { @MainActor in self?.apply(phase, model: selected) }
        }).get()
    }

    func refresh() {
        for model in LocalASRModel.allCases { statuses[model] = store(for: model).status() }
    }

    /// Teksty i akcja karty modelu (czysta logika w `ModelCardState`).
    func card(for model: LocalASRModel = .parakeetV3) -> ModelCardState {
        ModelCardState(status: status(for: model), activity: phase(for: model), model: model)
    }

    /// Wiersz roli ASR w edytorze presetu: magazyn wybranego modelu i bramka języka.
    func roleCard(modelID: String, language: LanguageCode?, autoLanguage: Bool) -> ModelCardState {
        ModelCardState.role(modelID: modelID, language: language, autoLanguage: autoLanguage,
                            status: { self.status(for: $0) }, activity: { self.phase(for: $0) })
    }

    /// Pobranie po kliknięciu. `force` (naprawa uszkodzonego) liczy sam `ModelStore.download` — wołający nie dostaje argumentu.
    func download(_ model: LocalASRModel = .parakeetV3) async {
        guard phase(for: model) == .idle else { return }
        downloadErrors[model] = nil
        phases[model] = .downloading(nil)
        highest[model] = 0
        let throttle = ProgressThrottle() // ~7,5 tys. zdarzeń na pobranie; UI dostaje najwyżej ~10/s
        let report: @Sendable (Double?) -> Void = { [weak self] p in
            guard throttle.admit() else { return }
            Task { @MainActor in
                guard let self, case .downloading = self.phase(for: model) else { return }
                // Store daje postęp monotoniczny, ale skoki na MainActor nie muszą dotrzeć po kolei — pilnujemy też tutaj.
                if let p {
                    let top = max(self.highest[model] ?? 0, p)
                    self.highest[model] = top
                    self.phases[model] = .downloading(top)
                } else { self.phases[model] = .downloading(nil) }
            }
        }
        do { try await store(for: model).download(progress: report) } catch { downloadErrors[model] = "\(error.localizedDescription)" }
        phases[model] = .idle
        refresh()
    }

    /// Usunięcie modelu po kliknięciu. Wyklucza się z pobieraniem (`phase` ≠ `.idle`) i z przebiegiem, który trzyma klienta
    /// (`runs`: od `beginRun()` do `endRun()` każdego przebiegu).
    func remove(_ model: LocalASRModel = .parakeetV3) {
        guard phase(for: model) == .idle, runs.isIdle, reservations.isIdle else {
            downloadErrors[model] = "Can't remove the on-device model while it is downloading or in use."
            return
        }
        downloadErrors[model] = nil
        do { try store(for: model).remove() } catch { downloadErrors[model] = "\(error.localizedDescription)" }
        refresh()
    }

    /// Z `onPhase` klienta. Nie nadpisuje pobierania. `.failed` wraca do `.idle` z komunikatem w `downloadError`.
    func apply(_ p: LocalASRPhase, model: LocalASRModel = .parakeetV3) {
        guard phase(for: model) == .idle || phase(for: model) == .preparing else { return }
        switch p {
        case .preparing:
            downloadErrors[model] = nil
            phases[model] = .preparing
        case .ready:
            phases[model] = .idle
        case .idle:
            // `release()` jednego przebiegu nie gasi „Preparing…” innego; własny przebieg zgasi je w `endRun()`.
            if runs.isIdle { phases[model] = .idle }
        case .failed(let reason):
            phases[model] = .idle
            downloadErrors[model] = "Couldn't load the on-device model: \(reason)"
        }
    }

    func probe(client: any TranscriptionClient, model: String, role: Role, language: LanguageCode?) async -> ProbeResult {
        beginRun()
        let result = await ProbeRunner(client: client).probe(model: model, role: role, language: language)
        await (client as? ReleasableClient)?.release()
        endRun()
        return result
    }

    /// Przed przebiegiem lokalnego klienta (spotkanie, dyktowanie, sonda); para z `endRun()` w tym samym zakresie.
    func beginRun() { runs.begin() }

    /// Po przebiegu: nieudane ładowanie nie wysyła `.ready`, więc „Preparing…" nie może zostać — gdy żaden inny przebieg nie trwa.
    func endRun() {
        runs.end()
        if runs.isIdle { for (model, phase) in phases where phase == .preparing { phases[model] = .idle } }
    }
}
