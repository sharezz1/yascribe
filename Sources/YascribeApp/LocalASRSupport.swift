import Foundation
import YascribeLocalASR

/// Stan lokalnego ASR dla UI (karta modelu, T7): magazyn, jego status oraz faza pobierania/przygotowania.
/// Logika bramek jest w `YascribeLocalASR` (`RunGate`) i tam testowana — tu tylko stan do pokazania.
/// Model pobiera się wyłącznie przez `download()` (akcja użytkownika), nigdy w tle.
@MainActor
final class LocalASRSupport: ObservableObject {
    /// `.idle` / `.downloading(Double?)` (nil = nieokreślony, wartość nie maleje) / `.preparing` (pierwsze ładowanie, kompilacja ANE).
    typealias Phase = ModelActivity

    let store: ModelStore
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status: ModelStatus
    /// Powód ostatniego nieudanego pobrania; czyszczony przy starcie następnego.
    @Published private(set) var downloadError: String?
    private var highest = 0.0
    /// Przebiegi trzymające model (`beginRun()`…`endRun()`); póki nie zero, `remove()` odmawia.
    private var runs = ModelRunCount()

    init(store: ModelStore = ModelStore()) {
        self.store = store
        status = store.status()
    }

    func refresh() { status = store.status() }

    /// Teksty i akcja karty modelu (czysta logika w `ModelCardState`).
    var card: ModelCardState { ModelCardState(status: status, activity: phase, variant: store.variant) }

    /// Pobranie po kliknięciu. `force` (naprawa uszkodzonego) liczy sam `ModelStore.download` — wołający nie dostaje argumentu.
    func download() async {
        guard phase == .idle, runs.isIdle else {
            downloadError = "Can't download the on-device model while it is downloading or in use."
            return
        }
        downloadError = nil
        phase = .downloading(nil)
        highest = 0
        let throttle = ProgressThrottle() // ~7,5 tys. zdarzeń na pobranie; UI dostaje najwyżej ~10/s
        let report: @Sendable (Double?) -> Void = { [weak self] p in
            guard throttle.admit() else { return }
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                // Store daje postęp monotoniczny, ale skoki na MainActor nie muszą dotrzeć po kolei — pilnujemy też tutaj.
                if let p { self.highest = max(self.highest, p); self.phase = .downloading(self.highest) } else { self.phase = .downloading(nil) }
            }
        }
        do { try await store.download(progress: report) } catch { downloadError = "\(error.localizedDescription)" }
        phase = .idle
        refresh()
    }

    /// Usunięcie modelu po kliknięciu. Wyklucza się z pobieraniem (`phase` ≠ `.idle`) i z przebiegiem, który trzyma klienta
    /// (`runs`: od `beginRun()` do `endRun()` każdego przebiegu).
    func remove() {
        guard phase == .idle, runs.isIdle else {
            downloadError = "Can't remove the on-device model while it is downloading or in use."
            return
        }
        downloadError = nil
        do { try store.remove() } catch { downloadError = "\(error.localizedDescription)" }
        refresh()
    }

    /// Z `onPhase` klienta. Nie nadpisuje pobierania. `.failed` wraca do `.idle` z komunikatem w `downloadError`.
    func apply(_ p: LocalASRPhase) {
        guard phase == .idle || phase == .preparing else { return }
        switch p {
        case .preparing:
            downloadError = nil
            phase = .preparing
        case .ready:
            phase = .idle
        case .idle:
            // `release()` jednego przebiegu nie gasi „Preparing…” innego; własny przebieg zgasi je w `endRun()`.
            if runs.isIdle { phase = .idle }
        case .failed(let reason):
            phase = .idle
            downloadError = "Couldn't load the on-device model: \(reason)"
        }
    }

    /// Przed przebiegiem lokalnego klienta (spotkanie, dyktowanie, sonda); para z `endRun()` w tym samym zakresie.
    func beginRun() { runs.begin() }

    /// Po przebiegu: nieudane ładowanie nie wysyła `.ready`, więc „Preparing…" nie może zostać — gdy żaden inny przebieg nie trwa.
    func endRun() {
        runs.end()
        if runs.isIdle, phase == .preparing { phase = .idle }
    }
}
