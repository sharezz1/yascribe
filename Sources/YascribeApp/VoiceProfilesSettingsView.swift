import SwiftUI
import YascribeLocalASR
import YascribeTranscription

/// Teksty profili głosów (TASK-117) — czysta logika, sprawdzana testem.
enum VoiceProfilesText {
    static func recognized(similarity: Double) -> String {
        String(localized: "Recognized by voice (\(Int((similarity * 100).rounded()))%)")
    }

    /// „3 samples · 4 min” dla bieżącego modelu; minuty zaokrąglone w górę, żeby 20 s nie było „0 min”.
    static func row(_ profile: VoiceProfile, model: String) -> String {
        let own = profile.samples.filter { $0.model == model }
        let samples = String(format: NSLocalizedString("%lld samples", comment: ""),
                             locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"), Int64(own.count))
        let minutes = Int((profile.seconds(model: model) / 60).rounded(.up))
        return "\(samples) · " + String(localized: "\(minutes) min")
    }

    /// Profil bez próbki bieżącego modelu nie rozpoznaje — trzeba nazwać tę osobę jeszcze raz.
    static func needsSample(_ profile: VoiceProfile, model: String) -> Bool { profile.vector(model: model) == nil }
}

/// Jednorazowe pytanie o zgodę przy pierwszym zapamiętaniu głosu (TASK-117 D3).
struct VoiceConsentAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert("Remember voices?", isPresented: Binding(get: { model.voiceConsentPending != nil }, set: { _ in })) {
            Button("Remember voices") { model.answerVoiceConsent(true) }
            Button("Not now", role: .cancel) { model.answerVoiceConsent(false) }
        } message: {
            Text("Yascribe will keep a voice print of \(model.voiceConsentPending?.name ?? "") on this Mac to recognize them in future meetings. Voice prints never leave this Mac. You can delete them any time in Settings.")
        }
    }
}

final class VoiceProfilesState: ObservableObject {
    @Published var confirmDelete: VoiceProfile?
    @Published var confirmDeleteAll = false
}

/// Sekcja Settings „Voice profiles”: zgoda, model beta, lista profili i usuwanie. Działa od razu (bez Save), jak karty modeli.
struct VoiceProfilesSection: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = VoiceProfilesState()

    var body: some View {
        let current = model.voiceModel.id
        SectionHeader(String(localized: "Voice profiles"))
        Card {
            FormRow(label: String(localized: "Recognition"),
                    caption: String(localized: "When you name a speaker, Yascribe keeps a voice print of that person on this Mac and names them in later meetings. Voice prints are biometric data: they never leave this Mac and agents can't read them.")) {
                Toggle("Recognize people by voice", isOn: Binding(get: { model.settings.voiceProfiles == true }, set: { model.setVoiceConsent($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            FormRow(label: String(localized: "Voice model"),
                    caption: String(localized: "Beta: CAM++ v2 may tell voices apart better but is trained mostly on Mandarin. It needs a separate download (29 MB) and won't name speakers until it is calibrated. Voice prints from one model don't work with the other.")) {
                Toggle("Use CAM++ v2 (beta)", isOn: Binding(get: { model.settings.voiceModelBeta == true }, set: { model.setVoiceBeta($0) }))
                    .labelsHidden().toggleStyle(.switch)
                if model.settings.voiceModelBeta == true { CampPlusModelRow(support: model.campPlusModel) }
            }
            if !model.voiceProfiles.profiles.isEmpty {
                RowDivider()
                ForEach(model.voiceProfiles.profiles) { profile in
                    FormRow(label: profile.name) {
                        HStack(spacing: 8) {
                            if VoiceProfilesText.needsSample(profile, model: current) {
                                WarnLabel(String(localized: "No sample for the current model"))
                            } else {
                                Text(VoiceProfilesText.row(profile, model: current)).foregroundStyle(.mnText2)
                            }
                            Spacer(minLength: 8)
                            Button("Delete…") { state.confirmDelete = profile }.buttonStyle(.pillSmall)
                        }
                    }
                }
                RowDivider()
                FormRow(label: "", caption: String(localized: "Deleting a meeting doesn't remove what its samples added to a profile. Delete the profile to remove it.")) {
                    Button("Delete all voice profiles…", role: .destructive) { state.confirmDeleteAll = true }.buttonStyle(.pillSmall)
                }
            }
        }
        .confirmationDialog(Text("Delete the voice profile of \(state.confirmDelete?.name ?? "")?"),
                            isPresented: Binding(get: { state.confirmDelete != nil }, set: { if !$0 { state.confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = state.confirmDelete?.id { model.deleteVoiceProfile(id) }
                state.confirmDelete = nil
            }
        }
        .confirmationDialog("Delete all voice profiles?", isPresented: $state.confirmDeleteAll) {
            Button("Delete all", role: .destructive) { model.deleteAllVoiceProfiles() }
        }
    }
}

/// Stan i pobieranie/usuwanie CAM++ (tylko przyciskiem).
private struct CampPlusModelRow: View {
    @ObservedObject var support: SpeakerModelSupport

    var body: some View {
        HStack(spacing: 8) {
            Text(SpeakerModelCardText.title(status: support.status, progress: support.progress)).foregroundStyle(.mnText2)
            if support.progress == nil {
                Button(SpeakerModelCardText.primaryLabel(status: support.status)) {
                    if support.status == .ready { support.remove() } else { Task { await support.download() } }
                }.buttonStyle(.pillSmall)
            }
            Link("License", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!).font(.system(size: 12))
        }
        .onAppear { support.refresh() }
        if let error = support.error { Text(error).font(.callout).foregroundStyle(.mnRec) }
    }
}
