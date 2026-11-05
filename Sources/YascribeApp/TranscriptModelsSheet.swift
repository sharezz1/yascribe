import YascribeNotes
import YascribeProviders
import SwiftUI

/// Stan okna poza szkicem: komunikat odmowy i jednorazowe wypełnienie pól (bez `@State`: CLT nie ma SwiftUIMacros).
private final class SheetUIState: ObservableObject {
    @Published var error: String?
    var prefilled = false
}

/// Okno „Improve transcript" (zakładka Transcript): ponowna transkrypcja i korekta wybranym modelem.
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
            generating: model.notes.state(item.id) == .generating, hasPreset: preset != nil, providerChosen: draft.asrProviderID != nil,
            modelEmpty: draft.asrModel.trimmingCharacters(in: .whitespaces).isEmpty, languageChosen: chosenLanguage != nil,
            correctionIncomplete: draft.correctionIncomplete)
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
        EditorSheet(title: "Improve", dirty: false, error: ui.error, onCancel: onClose, footer: .closeOnly, idealHeight: nil) {
            VStack(alignment: .leading, spacing: 18) {
                transcribeSection
                Divider()
                correctSection
                Divider()
                actionRow
            }
            .padding(.top, 8) // odstęp tytułu od pierwszej sekcji
            .disabled(moving) // przenoszenie nagrań: okno tylko do odczytu
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard !ui.prefilled else { return }
        ui.prefilled = true
        let known = Set(model.providers.providers.map(\.id))
        let asr = ModelsSheetRules.asrPrefill(run: item.runSnapshot, preset: preset?.asr, knownProviders: known)
        draft.asrProviderID = asr?.providerID
        draft.asrModel = asr?.model ?? ""
        let run = model.runLanguage(item)
        draft.language = ModelsSheetRules.languageChoice(isAuto: run.isAuto, language: run.language)
        let c = ModelsSheetRules.correctionPrefill(corrected: item.corrected, assigned: model.notes.correctionAssignment(for: item), knownProviders: known)
        draft.correctProviderID = c?.providerID
        draft.correctModel = c?.model ?? ""
        draft.usePreset = false
    }

    // MARK: Speech to text

    private var transcribeSection: some View {
        let providers = RoleProviders.choices(model.providers.providers, role: .asr, current: draft.asrProviderID)
        return SheetSection(title: "Speech to text") {
            SheetRow(label: "Provider") {
                FieldMenu(label: "Provider", value: provider(draft.asrProviderID)?.roleLabel ?? "None", width: nil, flexible: true) {
                    Picker("Provider", selection: Binding(get: { draft.asrProviderID }, set: { id in
                        guard id != draft.asrProviderID else { return }
                        draft.asrProviderID = id
                        draft.asrModel = "" // model innego dostawcy nie pasuje
                    })) {
                        ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
            if let pid = draft.asrProviderID {
                SheetRow(label: "Model") {
                    ModelPicker(providerID: pid, role: .asr, selection: $draft.asrModel, showProvider: false).frame(maxWidth: .infinity)
                    if provider(pid)?.isLocal == true { OnThisMacTag() }
                }
            }
            SheetRow(label: "Language") {
                FieldMenu(label: "Language", value: languageName(draft.language), width: nil, flexible: true) {
                    Picker("Language", selection: $draft.language) {
                        Text("Choose…").tag(LanguageChoice.unset)
                        ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(LanguageChoice.code(l.code)) }
                        Divider()
                        Text("Auto (mixed languages)").tag(LanguageChoice.auto)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
            if draft.language == .auto {
                WarnLabel("Lower quality, risk of invented text. Use Auto only for meetings that mix languages.")
            }
        }
    }

    /// Dwa przyciski na dole: „Improve" poprawia obecny transkrypt, „Transcribe + improve" robi nową transkrypcję i potem poprawę.
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetNote("Improve keeps the current transcription. Transcribe + improve replaces it with a new one, then improves it.")
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Improve") { improve() }.buttonStyle(.pillSmall).disabled(correctReason != nil)
                    .help(correctReason ?? "Improve the current transcript with the model above")
                Button("Transcribe + improve") { transcribe() }.buttonStyle(.pillPrimary).disabled(transcribeReason != nil)
                    .help(transcribeReason ?? "Transcribe again, then improve the result")
            }
            if let r = transcribeReason ?? correctReason {
                Text(r).font(.subheadline).foregroundStyle(.mnText2).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func transcribe() {
        guard let pid = draft.asrProviderID, let language = chosenLanguage, let preset else { return }
        ui.error = nil
        model.lastError = nil // komunikat odmowy ma być z tego kliknięcia, nie z wcześniejszego
        let asr = RoleAssignment(providerID: pid, model: draft.asrModel)
        if draft.startTranscribe(item: item, notes: model.notes, preset: presetCorrection, start: {
            model.transcribe(sessionURL: item.url, preset: preset, asr: asr, language: language)
        }) {
            onClose()
        } else {
            ui.error = model.lastError
            model.lastError = nil // odmowa widoczna w oknie, bez drugiego, globalnego alertu
        }
    }

    // MARK: Text improvement

    private var correctSection: some View {
        let providers = RoleProviders.choices(model.providers.providers, role: .correction, current: draft.correctProviderID)
        return SheetSection(title: "Text improvement") {
            SheetRow(label: "Provider") {
                FieldMenu(label: "Provider", value: provider(draft.correctProviderID)?.roleLabel ?? "None", width: nil, flexible: true) {
                    Picker("Provider", selection: Binding(get: { draft.correctProviderID }, set: { id in
                        guard id != draft.correctProviderID else { return }
                        draft.correctProviderID = id
                        draft.correctModel = ""
                    })) {
                        ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
            if let pid = draft.correctProviderID {
                SheetRow(label: "Model") {
                    ModelPicker(providerID: pid, role: .correction, selection: $draft.correctModel, showProvider: false).frame(maxWidth: .infinity)
                    if provider(pid)?.isLocal == true { OnThisMacTag() }
                }
            }
            if hasCorrectionOverride || stale {
                SheetRow(label: "") {
                    if let p = presetCorrection {
                        Button("Use preset (\(model.modelDisplayName(p.model)))") { draft.resetToPreset(p) }.buttonStyle(.pillSmall)
                    } else {
                        Button("Use preset (none)") { clearOverride() }.buttonStyle(.pillSmall)
                    }
                }
            }
            SheetNote(correctCaption)
            if model.notes.isCorrecting(item.id) { StateLabel(.progress(nil), "Improving the transcript…") }
        }
    }

    /// Jedna zwarta linia: skąd wybór, co jest teraz, że zastąpi obecną wersję.
    private var correctCaption: String {
        var parts = [ModelsSheetRules.correctionOrigin(hasOverride: hasCorrectionOverride, stale: stale, presetName: preset?.name)]
        if let c = item.corrected {
            parts.append("Current: \(model.modelDisplayName(c.model))")
            let kept = c.failedBatches + c.rejectedLines
            if kept > 0 { parts.append("\(kept) parts kept as heard") }
        }
        return parts.joined(separator: " · ") + (item.corrected == nil ? "" : ". Replaces the current corrected version.")
    }

    private func improve() {
        ui.error = nil
        model.lastError = nil
        if draft.submitCorrection(item: item, notes: model.notes, preset: presetCorrection) {
            onClose()
        } else {
            ui.error = model.lastError
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
