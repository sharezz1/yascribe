import YascribeNotes
import YascribeProviders
import SwiftUI

/// Stan okna poza szkicem: komunikat odmowy i jednorazowe wypełnienie pól (bez `@State`: CLT nie ma SwiftUIMacros).
private final class SummarySheetUIState: ObservableObject {
    @Published var error: String?
    var prefilled = false
}

/// Okno „Summary model": model, Thinking i Source notatki, jedno uruchomienie. Zamyka się tylko, gdy notatka wystartowała.
/// `item` pochodzi z żywego widoku spotkania, więc podpisy nie starzeją się po przeładowaniu.
struct SummaryModelsSheet: View {
    @Environment(AppModel.self) private var model
    @StateObject private var draft: SummaryModelsDraft
    @StateObject private var ui = SummarySheetUIState()
    let item: SessionItem
    @ObservedObject var state: MeetingViewState
    let onClose: () -> Void

    init(item: SessionItem, state: MeetingViewState, onClose: @escaping () -> Void) {
        self.item = item; self.state = state; self.onClose = onClose
        _draft = StateObject(wrappedValue: SummaryModelsDraft(item: item, state: state))
    }

    private var preset: RoleAssignment? { model.notes.presetSummaryChoice(for: item)?.assignment }
    private func provider(_ id: UUID?) -> Provider? { model.providers.providers.first { $0.id == id } }
    private var moving: Bool { model.recordingsMove != nil }
    private var override: RoleOverride? { model.notes.overrides(for: item).summary }
    private var stale: Bool {
        model.notes.overrides(for: item).isStale(.summary, knownProviders: Set(model.providers.providers.map(\.id)))
    }
    private var template: Template { model.notes.templates.all().first { $0.id == state.templateID } ?? .standard }

    private var reason: String? {
        let hasChoice = ModelsSheetRules.draft(providerID: draft.providerID, model: draft.model, thinking: draft.thinking, preset: preset,
                                               hasOverride: override != nil, usePreset: draft.usePreset) != nil
        return ModelsSheetRules.summaryReason(
            generating: model.notes.state(item.id) == .generating, hasText: draft.hasText(item), hasChoice: hasChoice,
            moving: moving, correcting: model.notes.isCorrecting(item.id), transcribing: model.isTranscribing(item))
    }

    var body: some View {
        EditorSheet(title: "Summary model", dirty: false, error: ui.error, onCancel: onClose, footer: .closeOnly, idealHeight: nil) {
            VStack(alignment: .leading, spacing: 10) {
                let context = state.context.trimmingCharacters(in: .whitespacesAndNewlines)
                note("Template \(template.name) · context: \(context.isEmpty ? "none" : context.replacingOccurrences(of: "\n", with: " "))")
                    .lineLimit(2)
                providerAndModel
                sourceMenu
                captions
                HStack(spacing: 10) {
                    Button(item.notes.summary == nil ? "Generate notes" : "Regenerate") { run() }
                        .buttonStyle(.pillPrimary).disabled(reason != nil)
                    if let reason { Text(reason).font(.subheadline).foregroundStyle(.mnText2) }
                }
            }
            .padding(.top, 8) // odstęp tytułu od pierwszego wiersza
            .disabled(moving) // przenoszenie nagrań: okno tylko do odczytu
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard !ui.prefilled else { return }
        ui.prefilled = true
        let c = model.notes.summaryChoice(for: item)?.assignment
        draft.providerID = c?.providerID
        draft.model = c?.model ?? ""
        draft.thinking = override?.thinking // nadpisanie z „Thinking: off" nie może zginąć przy niezmienionym Regenerate
        draft.usePreset = false
    }

    @ViewBuilder private var providerAndModel: some View {
        let providers = RoleProviders.choices(model.providers.providers, role: .summary, current: draft.providerID)
        FieldMenu(label: "Provider", value: provider(draft.providerID)?.roleLabel ?? "None", width: 280) {
            Picker("Provider", selection: Binding(get: { draft.providerID }, set: { id in
                guard id != draft.providerID else { return }
                draft.providerID = id
                draft.model = "" // model innego dostawcy nie pasuje
                if provider(id)?.isLocal == true { draft.thinking = nil } // lokalni zawsze bez myślenia
            })) {
                ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
            }
            .pickerStyle(.inline).labelsHidden()
        }
        if let pid = draft.providerID {
            ModelPicker(providerID: pid, role: .summary, selection: $draft.model).frame(width: 280)
            if provider(pid)?.isLocal == true {
                OnThisMacTag()
            } else {
                Toggle("Thinking", isOn: Binding(get: { draft.thinking ?? model.settings.summaryThinkingEnabled },
                                                 set: { draft.thinking = $0 }))
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Let the model think before it writes the notes")
            }
        }
        if let p = preset, override != nil || stale {
            Button("Use preset (\(model.modelDisplayName(p.model)))") { draft.resetToPreset(p) }.buttonStyle(.pill)
        }
    }

    private var sourceMenu: some View {
        FieldMenu(label: "Source", value: draft.sourceLabel, width: 280) {
            Button("Corrected") { draft.useCorrected = true }.disabled(item.corrected == nil)
            Button("Original") { draft.useCorrected = false }
        }
    }

    @ViewBuilder private var captions: some View {
        note(ModelsSheetRules.correctionOrigin(hasOverride: override != nil, stale: stale,
                                               presetName: model.notes.presetSummaryChoice(for: item)?.presetName))
        if let made = item.notes.summary?.model { note("Current notes made with \(model.modelDisplayName(made)) (\(made))") }
        if let parts = item.notes.summary?.condensedParts { note("Long meeting: condensed in \(parts) parts before summarizing.") }
        note("Used for future runs in this meeting. Presets stay unchanged.")
    }

    private func run() {
        ui.error = nil
        model.lastError = nil // komunikat odmowy ma być z tego kliknięcia, nie z wcześniejszego
        if draft.submit(item: item, state: state, notes: model.notes, template: template, context: state.context, preset: preset) {
            onClose()
        } else if let error = model.lastError {
            ui.error = error
        } else if case .failed(let message) = model.notes.state(item.id) {
            ui.error = message
        } else {
            ui.error = "Couldn't start the notes."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
    }
}
