import YascribeNotes
import YascribeProviders
import SwiftUI

/// Stan okna poza szkicem: komunikat odmowy i jednorazowe wypełnienie pól (bez `@State`: CLT nie ma SwiftUIMacros).
private final class SummarySheetUIState: ObservableObject {
    @Published var error: String?
    var prefilled = false
}

/// Okno „Improve summary": model, Thinking i Source notatki, jedno uruchomienie. Zamyka się tylko, gdy notatka wystartowała.
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
    /// Tylko działające nadpisanie (także dla Thinking): nieaktualne nie może zostać przypięte niezmienionym Regenerate.
    private var override: RoleOverride? { model.notes.usableOverride(.summary, for: item) }
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
        EditorSheet(title: "Improve summary", dirty: false, error: ui.error, onCancel: onClose, footer: .closeOnly, idealHeight: nil) {
            VStack(alignment: .leading, spacing: 12) {
                templateRow
                contextRow
                Divider().padding(.vertical, 4)
                providerAndModel
                sourceMenu
                SheetNote(caption)
                SheetAction(title: item.notes.summary == nil ? "Generate notes" : "Regenerate", reason: reason) { run() }
            }
            .padding(.top, 8) // odstęp tytułu od pierwszego wiersza
            .disabled(moving) // przenoszenie nagrań: okno tylko do odczytu
        }
        .onAppear { prefill() }
    }

    private var templateRow: some View {
        SheetRow(label: "Template") {
            FieldMenu(label: "Template", value: template.name, width: 300) {
                Picker("Template", selection: $state.templateID) {
                    ForEach(model.notes.templates.all()) { t in Text(t.name).tag(t.id) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
        }
    }

    private var contextRow: some View {
        SheetRow(label: "Context") {
            TextField("Optional: names, topics, what matters", text: $state.context, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(width: 300, alignment: .leading)
                .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
        }
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
        SheetRow(label: "Provider") {
            FieldMenu(label: "Provider", value: provider(draft.providerID)?.roleLabel ?? "None", width: 300) {
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
        }
        if let pid = draft.providerID {
            SheetRow(label: "Model") {
                ModelPicker(providerID: pid, role: .summary, selection: $draft.model, showProvider: false).frame(width: 300)
                if provider(pid)?.isLocal == true { OnThisMacTag() }
            }
            if provider(pid)?.isLocal != true {
                SheetRow(label: "Thinking") {
                    Toggle("Thinking", isOn: Binding(get: { draft.thinking ?? model.settings.summaryThinkingEnabled },
                                                     set: { draft.thinking = $0 }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .help("Let the model think before it writes the notes")
                }
            }
        }
        if override != nil || stale {
            SheetRow(label: "") {
                if let p = preset {
                    Button("Use preset (\(model.modelDisplayName(p.model)))") { draft.resetToPreset(p) }.buttonStyle(.pillSmall)
                } else {
                    Button("Use preset (none)") { clearOverride() }.buttonStyle(.pillSmall)
                }
            }
        }
    }

    private var sourceMenu: some View {
        SheetRow(label: "Source") {
            FieldMenu(label: "Source", value: draft.sourceLabel(item), width: 300) {
                Picker("Source", selection: $draft.useCorrected) {
                    Text("Corrected").tag(true).disabled(item.corrected == nil)
                    Text("Original").tag(false)
                }
                .pickerStyle(.inline).labelsHidden()
            }
        }
    }

    /// Jedna zwarta linia: skąd wybór, czym zrobiono obecną notatkę.
    private var caption: String {
        var parts = [ModelsSheetRules.correctionOrigin(hasOverride: override != nil, stale: stale,
                                                       presetName: model.notes.presetSummaryChoice(for: item)?.presetName)]
        if let made = item.notes.summary?.model { parts.append("Current notes: \(model.modelDisplayName(made))") }
        if let n = item.notes.summary?.condensedParts { parts.append("condensed in \(n) parts") }
        return parts.joined(separator: " · ")
    }

    private func run() {
        ui.error = nil
        model.lastError = nil // komunikat odmowy ma być z tego kliknięcia, nie z wcześniejszego
        if draft.submit(item: item, state: state, notes: model.notes, template: template, context: state.context, preset: preset) {
            onClose()
        } else {
            ui.error = model.lastError ?? "Couldn't start the notes."
            model.lastError = nil // odmowa widoczna w oknie, bez drugiego, globalnego alertu
        }
    }

    private func clearOverride() {
        ui.error = nil
        model.lastError = nil
        if !draft.clearOverride(item: item, notes: model.notes) {
            ui.error = model.lastError
            model.lastError = nil
        }
    }
}
