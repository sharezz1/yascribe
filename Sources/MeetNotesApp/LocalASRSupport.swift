import Foundation
import MeetNotesLocalASR

/// Stan lokalnego ASR dla UI (karta modelu, T7): magazyn, jego status oraz faza pobierania/przygotowania.
/// Logika bramek jest w `MeetNotesLocalASR` (`RunGate`) i tam testowana — tu tylko stan do pokazania.
/// Model pobiera się wyłącznie przez `download()` (akcja użytkownika), nigdy w tle.
@MainActor
final class LocalASRSupport: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// `nil` = postęp nieokreślony („Preparing model…" po pobraniu); wartość nie maleje w trakcie jednego pobrania.
        case downloading(Double?)
        /// Pierwsze ładowanie modelu przy starcie przebiegu (kompilacja ANE).
        case preparing
    }

    let store: ModelStore
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status: ModelStatus
    /// Powód ostatniego nieudanego pobrania; czyszczony przy starcie następnego.
    @Published private(set) var downloadError: String?
    private var highest = 0.0
    /// Od `.preparing` (pierwsze ładowanie przebiegu) do `endRun()` — wtedy model jest w użyciu i `remove()` odmawia.
    private var runActive = false

    init(store: ModelStore = ModelStore()) {
        self.store = store
        status = store.status()
    }

    func refresh() { status = store.status() }

    /// Pobranie po kliknięciu. `force` (naprawa uszkodzonego) liczy sam `ModelStore.download` — wołający nie dostaje argumentu.
    func download() async {
        guard phase == .idle else { return }
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
    /// (`runActive`: od pierwszego ładowania do `endRun()`).
    func remove() {
        guard phase == .idle, !runActive else {
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
            runActive = true
            downloadError = nil
            phase = .preparing
        case .ready, .idle:
            phase = .idle
        case .failed(let reason):
            phase = .idle
            downloadError = "Couldn't load the on-device model: \(reason)"
        }
    }

    /// Po przebiegu: nieudane ładowanie nie wysyła `.ready`, więc „Preparing…" nie może zostać.
    func endRun() {
        runActive = false
        if phase == .preparing { phase = .idle }
    }
}
