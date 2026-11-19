import AppKit
import YascribeLocalASR
import YascribeProviders
import SwiftUI

/// Stan modelu wykrywania mówców dla UI (TASK-22 T6): magazyn, jego status i postęp pobierania.
/// Model pobiera się wyłącznie przez `download()` (akcja użytkownika), nigdy w tle.
@MainActor
final class SpeakerModelSupport: ObservableObject {
    let store: DiarizerModelStore
    @Published private(set) var status: DiarizerModelStatus
    /// `nil` = nic się nie pobiera.
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?

    init(store: DiarizerModelStore = DiarizerModelStore()) {
        self.store = store
        status = store.status()
    }

    func refresh() { if progress == nil { status = store.status() } }

    func download() async {
        guard progress == nil else { return }
        error = nil
        progress = 0
        let report: @Sendable (Int64, Int64) -> Void = { [weak self] done, total in
            Task { @MainActor in
                guard let self, let current = self.progress else { return }
                self.progress = max(current, Double(done) / Double(max(total, 1))) // zdarzenia mogą dotrzeć poza kolejnością
            }
        }
        do { try await store.download(progress: report) } catch { self.error = (error as? DiarizerModelStoreError)?.displayMessage ?? error.localizedDescription }
        progress = nil
        status = store.status()
    }

    func remove() {
        guard progress == nil else { return }
        error = nil
        do { try store.remove() } catch { self.error = (error as? DiarizerModelStoreError)?.displayMessage ?? error.localizedDescription }
        status = store.status()
    }

    /// Nota licencyjna z paczki; poza `.app` (uruchomienie z SwiftPM) strona licencji.
    func openLicense() {
        let note = Bundle.main.url(forResource: SpeakerModelCardText.noticeName, withExtension: "txt", subdirectory: "ThirdPartyNotices")
        NSWorkspace.shared.open(note ?? SpeakerModelCardText.licenseURL)
    }
}

/// Teksty karty — czysta logika, żeby dało się ją sprawdzić testem.
enum SpeakerModelCardText {
    static let noticeName = "SpeakerDetection-CC-BY-4.0"
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let size = "22 MB" // DiarizerManifest.offline: 21 599 417 B
    static var missingHint: String { String(localized: "Download the speaker model in Settings") }

    static func title(status: DiarizerModelStatus, progress: Double?) -> String {
        if let progress { return String(localized: "Downloading \(Int((progress * 100).rounded()))%") }
        switch status {
        case .missing: return String(localized: "Not downloaded")
        case .incomplete: return String(localized: "Incomplete")
        case .ready: return String(localized: "Ready")
        }
    }

    static func primaryLabel(status: DiarizerModelStatus) -> String { status == .ready ? String(localized: "Remove") : String(localized: "Download") }
}

enum SpeakerMenuDecision {
    static func needsConfirmation(names: [String: String]?) -> Bool { !(names?.isEmpty ?? true) }
}

final class SpeakerMenuState: ObservableObject {
    @Published var confirmNames = false
    @Published var confirmDownload = false
    @Published var confirmLocalNames = false
}

/// Pozycje menu ⋯. Pytania są w `SpeakerMenuDialogs` na samym `Menu`: dialog podpięty pod pozycję menu się nie pokazuje.
struct DetectSpeakersMenu: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var support: SpeakerModelSupport
    @ObservedObject var state: SpeakerMenuState
    let item: SessionItem

    var body: some View {
        if model.supportsCloudSpeakers(item) {
            Button("Detect speakers again") {
                if SpeakerMenuDecision.needsConfirmation(names: item.speakers?.names) { state.confirmNames = true }
                else { model.detectSpeakersAgain(item: item) }
            }
        } else {
            Button("Detect speakers on this Mac") {
                if SpeakerMenuDecision.needsConfirmation(names: item.speakers?.names) { state.confirmLocalNames = true }
                else { SpeakerMenuDialogs.detectOnThisMac(model: model, support: support, state: state, item: item) }
            }
        }
    }
}

struct SpeakerMenuDialogs: ViewModifier {
    @Environment(AppModel.self) private var model
    @ObservedObject var support: SpeakerModelSupport
    @ObservedObject var state: SpeakerMenuState
    let item: SessionItem

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Names you gave will be removed.", isPresented: $state.confirmNames) {
                Button("Detect speakers again", role: .destructive) { model.detectSpeakersAgain(item: item) }
            }
            .confirmationDialog("Names you gave will be removed.", isPresented: $state.confirmLocalNames) {
                Button("Detect speakers on this Mac", role: .destructive) {
                    Self.detectOnThisMac(model: model, support: support, state: state, item: item)
                }
            }
            .confirmationDialog("Download the speaker model (22 MB)?", isPresented: $state.confirmDownload) {
                Button("Download and detect speakers") {
                    Task {
                        await support.download()
                        if support.status == .ready { model.detectSpeakersOnThisMac(item: item) }
                        else if let error = support.error { model.lastError = error }
                    }
                }
            }
    }

    @MainActor static func detectOnThisMac(model: AppModel, support: SpeakerModelSupport, state: SpeakerMenuState, item: SessionItem) {
        support.refresh()
        if support.status == .ready { model.detectSpeakersOnThisMac(item: item) } else { state.confirmDownload = true }
    }
}
