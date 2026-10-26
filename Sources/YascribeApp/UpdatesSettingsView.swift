import SwiftUI
import YascribeUpdates

/// Settings → Updates: wersja i ręczne sprawdzenie. Automatyczne sprawdzanie jest włączone w `Info.plist`; instalacja zawsze na kliknięcie.
struct UpdatesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionHeader("Updates")
        Card {
            UpdatesRow(updater: model.updater)
        }
    }
}

private struct UpdatesRow: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        FormRow(label: "Version", caption: "Yascribe checks for updates on its own and asks before installing. An update never interrupts a recording.") {
            HStack(spacing: 8) {
                Text(updater.currentVersion).foregroundStyle(.mnText)
                Spacer(minLength: 8)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .buttonStyle(.pillSmall)
                    .disabled(!updater.canCheck)
            }
        }
    }
}
