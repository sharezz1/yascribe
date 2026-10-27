import AppKit
import YascribeLocalASR
import YascribeProviders
import SwiftUI

/// Karta modelu lokalnego ASR (F20 T7; język wizualny B z macos.md §11).
/// Pobranie startuje wyłącznie z kliknięcia „Download" — nigdy automatycznie.

final class ModelCardUI: ObservableObject {
    /// Akcja czekająca na potwierdzenie („Remove…", „Download again").
    @Published var confirming: ModelCardState.Action?
    /// Błąd usunięcia (błąd pobrania trzyma `LocalASRSupport.downloadError`).
    @Published var removeError: String?
}

/// Sama prezentacja: stan podany z zewnątrz, więc migawki pokazują wymyślone stany, a nie magazyn tego komputera.
struct ModelCardContent: View {
    let card: ModelCardState
    /// Lokalizacja modelu, już ze skróconym katalogiem domowym („~/Library/…").
    let location: String
    var error: String?
    var onPrimary: (ModelCardState.Action) -> Void = { _ in }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ProviderLogo(preset: .onThisMac)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ModelCardState.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                        Text(card.meta).font(.system(size: 11)).foregroundStyle(.mnText2)
                    }
                    Spacer(minLength: 8)
                    stateLabel
                    if let action = card.primary, let label = card.primaryLabel {
                        Button(label) { onPrimary(action) }.buttonStyle(.pillSmall)
                    }
                }
                if case .progress(let fraction?) = card.tone { bar(fraction) }
                Text(card.description).font(.callout).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                if let note = card.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.mnRec).fixedSize(horizontal: false, vertical: true)
                }
                Text("Shared FluidAudio folder: \(location)")
                    .font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    @ViewBuilder private var stateLabel: some View {
        switch card.tone {
        case .ready: StateLabel(.ok, card.title)
        case .neutral: StateLabel(.neutral, card.title)
        case .warning: WarnLabel(card.title)
        case .progress(let f): StateLabel(f == nil ? .progress(nil) : .neutral, card.title)
        }
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

/// Karta w Settings → Providers: czyta `LocalASRSupport`, pobiera i usuwa po kliknięciu (usunięcie i naprawa po potwierdzeniu).
struct ModelCardSection: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var support: LocalASRSupport
    @StateObject private var ui = ModelCardUI()

    private var location: String { (support.store.modelDirectory.path as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Yascribe model")
            ModelCardContent(card: support.card, location: location, error: ui.removeError ?? support.downloadError) { action in
                if action.needsConfirmation { ui.confirming = action } else { run(action) }
            }
        }
        .confirmationDialog("Remove \(ModelCardState.name)?", isPresented: confirming(.remove)) {
            Button("Remove", role: .destructive) { run(.remove) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(ModelCardState.name) from the shared FluidAudio folder? Other apps that use FluidAudio may use this copy too.")
        }
        .confirmationDialog("Download \(ModelCardState.name) again?", isPresented: confirming(.downloadAgain)) {
            Button("Delete and Download", role: .destructive) { run(.downloadAgain) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The damaged copy in the shared FluidAudio folder is deleted first, then \(support.card.size) is downloaded.")
        }
    }

    private func confirming(_ action: ModelCardState.Action) -> Binding<Bool> {
        Binding(get: { ui.confirming == action }, set: { if !$0, ui.confirming == action { ui.confirming = nil } })
    }

    private func run(_ action: ModelCardState.Action) {
        ui.removeError = nil
        ui.confirming = nil
        switch action {
        case .download, .downloadAgain:
            Task { await support.download(); model.reverifyOnDeviceProviders() }
        case .remove:
            do { try support.store.remove() } catch { ui.removeError = "Couldn't remove the model: \(error.localizedDescription)" }
            support.refresh()
            model.reverifyOnDeviceProviders()
        }
    }
}

extension AppModel {
    /// Po pobraniu albo usunięciu modelu wiersz dostawcy „On this Mac" pokazuje aktualny stan (bez sieci: tylko status magazynu).
    func reverifyOnDeviceProviders() {
        for p in providers.providers where p.api == .fluidAudio { Task { await verifyProvider(p.id) } }
    }
}

/// Edytor presetu, rola ASR z dostawcą „On this Mac": znacznik + ostrzeżenie „Model not downloaded" z przyciskiem Download.
struct OnThisMacRoleContent: View {
    let card: ModelCardState
    var onDownload: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            OnThisMacTag()
            if let warning = card.roleWarning { WarnLabel(warning) }
            if case .progress(let f) = card.tone { StateLabel(f == nil ? .progress(nil) : .neutral, card.title) }
            Spacer(minLength: 0)
            if card.roleWarning != nil {
                if card.primary == .download {
                    Button("Download (\(card.size))", action: onDownload).buttonStyle(.pillSmall)
                } else {
                    Button("Open Settings", action: onOpenSettings).buttonStyle(.pillSmall)
                }
            }
        }
        .padding(.leading, 158).padding(.trailing, 16).padding(.bottom, 10)
    }
}

struct OnThisMacRoleRow: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var support: LocalASRSupport

    var body: some View {
        OnThisMacRoleContent(card: support.card,
                             onDownload: { Task { await support.download(); model.reverifyOnDeviceProviders() } },
                             onOpenSettings: { model.section = .settings })
    }
}
