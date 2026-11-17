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
        do { try await store.download(progress: report) } catch { self.error = error.localizedDescription }
        progress = nil
        status = store.status()
    }

    func remove() {
        guard progress == nil else { return }
        error = nil
        do { try store.remove() } catch { self.error = error.localizedDescription }
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
    static let missingHint = "Download the speaker model in Settings"

    static func title(status: DiarizerModelStatus, progress: Double?) -> String {
        if let progress { return "Downloading \(Int((progress * 100).rounded()))%" }
        switch status {
        case .missing: return "Not downloaded"
        case .incomplete: return "Incomplete"
        case .ready: return "Ready"
        }
    }

    static func primaryLabel(status: DiarizerModelStatus) -> String { status == .ready ? "Remove" : "Download" }
}

/// Sama prezentacja: stan z zewnątrz, więc migawki pokazują wymyślone stany, a nie magazyn tego komputera.
struct SpeakerModelCardContent: View {
    let status: DiarizerModelStatus
    let progress: Double?
    var error: String?
    @Binding var detect: Bool
    @Binding var sensitivity: SpeakerSensitivity
    @Binding var source: SpeakerSource
    var providerName: String? = nil
    var onAdd: () -> Void = {}
    var onPrimary: () -> Void = {}
    var onLicense: () -> Void = {}

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Source", selection: $source) {
                    Text("On this Mac").tag(SpeakerSource.local)
                    Text("Mistral").tag(SpeakerSource.mistral)
                }.pickerStyle(.segmented)
                if source == .local {
                    HStack(spacing: 12) {
                        ProviderLogo(preset: .onThisMac)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speaker detection").font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                            Text("Call audio · \(SpeakerModelCardText.size)").font(.system(size: 11)).foregroundStyle(.mnText2)
                        }
                        Spacer(minLength: 8)
                        stateLabel
                        if progress == nil {
                            Button(SpeakerModelCardText.primaryLabel(status: status), action: onPrimary).buttonStyle(.pillSmall)
                        }
                    }
                    if let progress { bar(progress) }
                    Text("Labels the voices on the other side of a call as Them A, Them B… after transcription. Runs on this Mac; the audio never leaves it. Download is on request only.")
                        .font(.callout).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.mnRec).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onLicense) {
                        Text("License (CC BY 4.0)").font(.system(size: 11)).foregroundStyle(.mnText2).underline(color: .mnText3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Speaker detection").font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                    HStack {
                        if let providerName { Text(providerName) }
                        else { Button("Add Mistral…", action: onAdd).buttonStyle(.pillSmall) }
                    }
                    Text("Audio of the other participants is sent to Mistral (about $0.21 per hour of call).")
                        .font(.callout).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            RowDivider()
            FormRow(label: "Detect speakers after transcription",
                    caption: source == .mistral ? "Sends the other participants' audio to Mistral after each transcription." : "After transcription, when the model is downloaded. The meeting menu ⋯ can run it again with another sensitivity.") {
                Toggle("Detect speakers after transcription", isOn: $detect).labelsHidden().toggleStyle(.switch)
            }
            if source == .local {
                RowDivider()
                FormRow(label: "Sensitivity",
                        caption: "Higher separates more voices, but may split one person into two.") {
                    Picker("Sensitivity", selection: $sensitivity) {
                        ForEach(SpeakerSensitivity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        }
    }

    @ViewBuilder private var stateLabel: some View {
        let title = SpeakerModelCardText.title(status: status, progress: progress)
        if progress != nil { StateLabel(.neutral, title) }
        else if status == .ready { StateLabel(.ok, title) }
        else if status == .incomplete { WarnLabel(title) }
        else { StateLabel(.neutral, title) }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.mnLine)
                Capsule().fill(.mnText2).frame(width: g.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Karta w Settings obok karty modelu Yascribe. Przełącznik i czułość to szkic ustawień (zapis przyciskiem Save).
struct SpeakerModelCardSection: View {
    @ObservedObject var support: SpeakerModelSupport
    @Binding var source: SpeakerSource
    @Binding var detect: Bool
    @Binding var sensitivity: SpeakerSensitivity
    var providerName: String?
    var onAdd: () -> Void

    var body: some View {
        SpeakerModelCardContent(status: support.status, progress: support.progress, error: support.error,
                                detect: $detect, sensitivity: $sensitivity, source: $source, providerName: providerName, onAdd: onAdd,
                                onPrimary: { if support.status == .ready { support.remove() } else { Task { await support.download() } } },
                                onLicense: support.openLicense)
            .padding(.bottom, 10)
            .onAppear { support.refresh() }
    }
}

/// „Detect speakers…" w menu ⋯ Transcript: podmenu Low / Medium / High; bez modelu wyszarzone z podpowiedzią.
struct DetectSpeakersMenu: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var support: SpeakerModelSupport
    let item: SessionItem

    var body: some View {
        Menu("Detect speakers…") {
            if model.settings.speakerSourceOrDefault == .mistral {
                Button("With Mistral") { model.detectSpeakersAgain(item: item, sensitivity: model.settings.speakerSensitivityOrDefault) }
            } else {
                ForEach(SpeakerSensitivity.allCases, id: \.self) { level in
                    Button(level.rawValue.capitalized) { model.detectSpeakersAgain(item: item, sensitivity: level) }
                }
            }
        }
        .disabled(!model.speakerSourceReady)
        .help(model.speakerSourceReady ? "Label the voices on the other side again" : (model.settings.speakerSourceOrDefault == .local ? SpeakerModelCardText.missingHint : "Add a Mistral provider with an API key in Settings"))
        .onAppear { support.refresh() }
    }
}
