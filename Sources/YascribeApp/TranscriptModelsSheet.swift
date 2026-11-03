import YascribeNotes
import YascribeProviders
import SwiftUI

/// Stan okna poza szkicem: komunikat odmowy i jednorazowe wypełnienie pól (bez `@State`: CLT nie ma SwiftUIMacros).
private final class SheetUIState: ObservableObject {
    @Published var error: String?
    var prefilled = false
}

/// Okno „Models for this meeting" (zakładka Transcript): ponowna transkrypcja i korekta wybranym modelem.
/// Zamyka się tylko wtedy, gdy uruchomienie zostało przyjęte; odmowa zostawia je otwarte z powodem.
/// `item` pochodzi z żywego widoku spotkania, więc podpisy nie starzeją się po przeładowaniu.
struct TranscriptModelsSheet: View {
    @Environment(AppModel.self) private var model
    @StateObject private var draft = TranscriptModelsDraft()
    @StateObject private var ui = SheetUIState()
    let item: SessionItem
    let onClose: () -> Void

    private var preset: Preset? { model.presetFor(sessionURL: item.url) }
    private func provider(_ id: UUID?) -> Provider? { model.providers.providers.first { $0.id == id } }
    private var moving: Bool { model.recordingsMove != nil }
    // Tylko działające nadpisanie: nieaktualne (dostawca usunięty) przy niezmienionym uruchomieniu nie zostaje przypięte jako własne.
    private var hasCorrectionOverride: Bool { model.notes.usableOverride(.correction, for: item) != nil }
    private var stale: Bool {
        model.notes.overrides(for: item).isStale(.correction, knownProviders: Set(model.providers.providers.map(\.id)))
    }
    private var presetCorrection: RoleAssignment? { model.notes.presetCorrection(for: item) }

    /// `nil` = jeszcze nie wybrano (przycisk wyłączony); `.some(nil)` = Auto.
    private var chosenLanguage: LanguageCode?? {
        switch draft.language {
        case .unset: nil
        case .auto: .some(nil)
        case .code(let c): .some(c)
        }
    }

    private var transcribeReason: String? {
        ModelsSheetRules.transcribeReason(
            blocker: ModelsSheetRules.transcribeBlocker(item: item, model: model), correcting: model.notes.isCorrecting(item.id),
            hasPreset: preset != nil, providerChosen: draft.asrProviderID != nil,
            modelEmpty: draft.asrModel.trimmingCharacters(in: .whitespaces).isEmpty, languageChosen: chosenLanguage != nil)
    }

    private var correctReason: String? {
        let hasDraft = ModelsSheetRules.draft(providerID: draft.correctProviderID, model: draft.correctModel, thinking: nil,
                                              preset: presetCorrection, hasOverride: hasCorrectionOverride, usePreset: draft.usePreset) != nil
        return ModelsSheetRules.correctReason(
            canCorrectNow: model.notes.canCorrectNow(item), moving: moving, transcribing: model.isTranscribing(item),
            correcting: model.notes.isCorrecting(item.id), generating: model.notes.state(item.id) == .generating,
            hasUsableTranscript: item.runID != nil && item.transcript?.utterances.isEmpty == false, hasDraft: hasDraft)
    }

    var body: some View {
        EditorSheet(title: "Models for this meeting", dirty: false, error: ui.error, onCancel: onClose, footer: .closeOnly, idealHeight: nil) {
            VStack(alignment: .leading, spacing: 22) {
                transcribeSection
                correctSection
            }
            .padding(.top, 8) // odstęp tytułu od pierwszej sekcji
            .disabled(moving) // przenoszenie nagrań: okno tylko do odczytu
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard !ui.prefilled else { return }
        ui.prefilled = true
        draft.asrProviderID = preset?.asr?.providerID
        draft.asrModel = preset?.asr?.model ?? ""
        let run = model.runLanguage(item)
        draft.language = ModelsSheetRules.languageChoice(isAuto: run.isAuto, language: run.language)
        let c = model.notes.correctionAssignment(for: item)
        draft.correctProviderID = c?.providerID
        draft.correctModel = c?.model ?? ""
        draft.usePreset = false
    }

    // MARK: Transcribe again

    private var transcribeSection: some View {
        let providers = RoleProviders.choices(model.providers.providers, role: .asr, current: draft.asrProviderID)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Transcribe again").font(.system(size: 13, weight: .medium))
            FieldMenu(label: "Provider", value: provider(draft.asrProviderID)?.roleLabel ?? "None", width: 280) {
                Picker("Provider", selection: Binding(get: { draft.asrProviderID }, set: { id in
                    guard id != draft.asrProviderID else { return }
                    draft.asrProviderID = id
                    draft.asrModel = "" // model innego dostawcy nie pasuje
                })) {
                    ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if let pid = draft.asrProviderID {
                ModelPicker(providerID: pid, role: .asr, selection: $draft.asrModel).frame(width: 280)
                if provider(pid)?.isLocal == true { OnThisMacTag() }
            }
            FieldMenu(label: "Language", value: languageName(draft.language), width: 280) {
                Picker("Language", selection: $draft.language) {
                    Text("Choose…").tag(LanguageChoice.unset)
                    ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                    Divider()
                    Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if draft.language == .auto {
                WarnLabel("Lower quality, risk of invented text. Use Auto only for meetings that mix languages.")
            }
            Text("The current transcript stays until the new one is ready.")
                .font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
            action("Transcribe", reason: transcribeReason) { transcribe() }
        }
    }

    private func transcribe() {
        guard let pid = draft.asrProviderID, let language = chosenLanguage, let preset else { return }
        ui.error = nil
        if model.transcribe(sessionURL: item.url, preset: preset, asr: RoleAssignment(providerID: pid, model: draft.asrModel), language: language) {
            onClose()
        } else {
            ui.error = model.lastError
        }
    }

    // MARK: Correct the transcript

    private var correctSection: some View {
        let providers = RoleProviders.choices(model.providers.providers, role: .correction, current: draft.correctProviderID)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Correct the transcript").font(.system(size: 13, weight: .medium))
            FieldMenu(label: "Provider", value: provider(draft.correctProviderID)?.roleLabel ?? "None", width: 280) {
                Picker("Provider", selection: Binding(get: { draft.correctProviderID }, set: { id in
                    guard id != draft.correctProviderID else { return }
                    draft.correctProviderID = id
                    draft.correctModel = ""
                })) {
                    ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if let pid = draft.correctProviderID {
                ModelPicker(providerID: pid, role: .correction, selection: $draft.correctModel).frame(width: 280)
                if provider(pid)?.isLocal == true { OnThisMacTag() }
            }
            if let p = presetCorrection, hasCorrectionOverride || stale {
                Button("Use preset (\(model.modelDisplayName(p.model)))") { draft.resetToPreset(p) }.buttonStyle(.pill)
            }
            note(ModelsSheetRules.correctionOrigin(hasOverride: hasCorrectionOverride, stale: stale, presetName: preset?.name))
            if let c = item.corrected {
                note("Current corrected version: \(model.modelDisplayName(c.model)) (\(c.model))")
                if c.failedBatches + c.rejectedLines > 0 { note("\(c.failedBatches + c.rejectedLines) parts kept as heard (failed a check)") }
                note("Replaces the current corrected version.")
            }
            note("Used for future runs in this meeting. Presets stay unchanged.")
            if model.notes.isCorrecting(item.id) { StateLabel(.progress(nil), "Improving the transcript…") }
            action(item.corrected == nil ? "Improve transcript" : "Improve again", reason: correctReason) { improve() }
        }
    }

    private func improve() {
        ui.error = nil
        if draft.submitCorrection(item: item, notes: model.notes, preset: presetCorrection) {
            onClose()
        } else {
            ui.error = model.lastError
        }
    }

    // MARK: Wspólne

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ title: String, reason: String?, run: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(title, action: run).buttonStyle(.pillPrimary).disabled(reason != nil)
            if let reason { Text(reason).font(.subheadline).foregroundStyle(.mnText2) }
        }
    }
}
