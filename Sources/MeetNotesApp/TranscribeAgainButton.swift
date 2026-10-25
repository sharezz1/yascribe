import MeetNotesNotes
import MeetNotesProviders
import SwiftUI

/// Stan popovera „Transcribe again…" (bez `@State`: CLT nie ma SwiftUIMacros).
final class TranscribeAgainState: ObservableObject {
    @Published var showing = false
    @Published var providerID: UUID?
    @Published var model = ""
    @Published var language = LanguageChoice.unset
}

/// „Transcribe again…" na karcie Transcript (D13): to samo nagranie innym modelem ASR i językiem.
/// Jednorazowa akcja, nie ustawienie — nic nie trafia do `meta.json` ani do presetu; powstaje nowy przebieg.
struct TranscribeAgainButton: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = TranscribeAgainState()
    let item: SessionItem
    /// Tylko migawki: popover rysowany w miejscu (ImageRenderer/NSHostingView nie łapie okna popovera).
    var inlinePopover = false

    private var preset: Preset? { model.presetFor(sessionURL: item.url) }
    private var blocker: String? {
        TranscribeAgain.blocker(audioDeletedAfterDays: item.audioDeletedAfterDays, transcribing: model.isTranscribing(item),
                                moving: model.recordingsMove != nil)
    }
    private func provider(_ id: UUID?) -> Provider? { model.providers.providers.first { $0.id == id } }
    private var providers: [Provider] {
        RoleProviders.choices(model.providers.providers, role: .asr, current: state.providerID)
    }
    /// `nil` = jeszcze nie wybrano (przycisk wyłączony); `.some(nil)` = Auto.
    private var chosenLanguage: LanguageCode?? {
        switch state.language {
        case .unset: nil
        case .auto: .some(nil)
        case .code(let c): .some(c)
        }
    }
    private var canSubmit: Bool {
        state.providerID != nil && !state.model.trimmingCharacters(in: .whitespaces).isEmpty && chosenLanguage != nil && preset != nil
    }

    var body: some View {
        if inlinePopover { content.onAppear { open() } } else { button }
    }

    private var button: some View {
        Button("Transcribe again…") { open() }
            .buttonStyle(.pill)
            .layoutPriority(2) // w ciasnym nagłówku skraca się chip modelu, nie przycisk
            .disabled(blocker != nil)
            .popover(isPresented: $state.showing, arrowEdge: .bottom) { content }
            .help(blocker ?? "Transcribe this recording again with another model or language")
    }

    /// Domyślnie to, czego użyto przy nagraniu — zmienia się jedno pole, nie wszystkie.
    private func open() {
        state.providerID = preset?.asr?.providerID
        state.model = preset?.asr?.model ?? ""
        state.language = preset?.languageChoice ?? .unset
        state.showing = true
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcribe this recording again").font(.system(size: 13, weight: .medium))
            FieldMenu(label: "Provider", value: provider(state.providerID)?.roleLabel ?? "None", width: 280) {
                Picker("Provider", selection: Binding(get: { state.providerID }, set: { id in
                    guard id != state.providerID else { return }
                    state.providerID = id
                    state.model = "" // model innego dostawcy nie pasuje
                })) {
                    ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if let pid = state.providerID {
                ModelPicker(providerID: pid, role: .asr, selection: $state.model).frame(width: 280)
                if provider(pid)?.isLocal == true { OnThisMacTag() }
            }
            FieldMenu(label: "Language", value: languageName(state.language), width: 280) {
                Picker("Language", selection: $state.language) {
                    Text("Choose…").tag(LanguageChoice.unset)
                    ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                    Divider()
                    Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if state.language == .auto {
                WarnLabel("Lower quality, risk of invented text. Use Auto only for meetings that mix languages.")
            }
            Text("Adds a new transcript. The earlier one stays on disk, and the preset stays as it is.")
                .font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button("Transcribe") { submit() }
                    .buttonStyle(.pillPrimary)
                    .disabled(!canSubmit || blocker != nil)
            }
        }
        .padding(14)
        .frame(width: 308)
    }

    private func submit() {
        guard let pid = state.providerID, let language = chosenLanguage, let preset else { return }
        state.showing = false
        model.transcribe(sessionURL: item.url, preset: preset, asr: RoleAssignment(providerID: pid, model: state.model), language: language)
    }
}
