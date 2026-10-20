import Foundation
import MeetNotesLocalASR

/// Stan lokalnego ASR dla UI (karta modelu, T7): magazyn, jego status oraz faza pobierania/przygotowania.
/// Logika bramek jest w `MeetNotesLocalASR` (`RunGate`) i tam testowana — tu tylko stan do pokazania.
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

    init(store: ModelStore = ModelStore()) {
        self.store = store
        status = store.status()
    }

    func refresh() { status = store.status() }

    /// Teksty i akcja karty modelu (czysta logika w `ModelCardState`).
    var card: ModelCardState { ModelCardState(status: status, activity: phase) }

    /// Pobranie po kliknięciu. `force` (naprawa uszkodzonego) liczy sam `ModelStore.download` — wołający nie dostaje argumentu.
    func download() async {
        guard phase == .idle else { return }
        downloadError = nil
        phase = .downloading(nil)
        highest = 0
        let report: @Sendable (Double?) -> Void = { [weak self] p in
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

    /// Z `onPhase` klienta (`.preparing` przy pierwszym ładowaniu, `.ready` po nim). Nie nadpisuje pobierania.
    func apply(_ p: LocalASRPhase) {
        guard phase == .idle || phase == .preparing else { return }
        phase = p == .preparing ? .preparing : .idle
    }

    /// Po przebiegu: nieudane ładowanie nie wysyła `.ready`, więc „Preparing…" nie może zostać.
    func endRun() {
        if phase == .preparing { phase = .idle }
    }
}
