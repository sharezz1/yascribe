import Foundation
import YascribeNotes
import YascribeProviders

/// Czyste reguły okna „Models…" (bez widoków), żeby dało się je testować bez `AppModel`.
enum ModelsSheetRules {
    /// Kolejność ma znaczenie: „Use preset" wygrywa z nadpisaniem; niezmieniony względem presetu wybór bez zapisanego
    /// nadpisania też jest `.preset` (decyzja użytkownika: spotkanie dalej podąża za presetem).
    static func draft(providerID: UUID?, model: String, thinking: Bool?, preset: RoleAssignment?,
                      hasOverride: Bool, usePreset: Bool) -> ModelDraft? {
        if usePreset { return .preset }
        let model = model.trimmingCharacters(in: .whitespaces)
        guard let providerID, !model.isEmpty else { return nil }
        if providerID == preset?.providerID, model == preset?.model, thinking == nil, !hasOverride { return .preset }
        return .custom(RoleOverride(providerID: providerID, model: model, thinking: thinking))
    }

    static func transcribeReason(blocker: String?, correcting: Bool, hasPreset: Bool, providerChosen: Bool,
                                 modelEmpty: Bool, languageChosen: Bool) -> String? {
        if let blocker { return blocker }
        if correcting { return "Correction is running." }
        if !hasPreset { return "This meeting has no preset." }
        if !providerChosen || modelEmpty { return "Choose a model." }
        if !languageChosen { return "Choose a language." }
        return nil
    }

    static func correctReason(canCorrectNow: Bool, moving: Bool, transcribing: Bool, correcting: Bool, generating: Bool,
                              hasUsableTranscript: Bool, hasDraft: Bool) -> String? {
        if moving { return "Meetings are being moved." }
        if transcribing { return "Transcription is running." }
        if correcting { return "Correction is running." }
        if generating { return "Notes are being generated." }
        if !hasUsableTranscript { return "No usable transcript." }
        if !hasDraft { return "Choose a model." }
        // Zapas: `canCorrectNow` zna jeszcze warunki, których nie rozpisano powyżej.
        return canCorrectNow ? nil : "Can't improve the transcript right now."
    }

    static func correctionOrigin(hasOverride: Bool, stale: Bool, presetName: String?) -> String {
        if stale { return "The model you chose is no longer available" }
        if hasOverride { return "Chosen for this meeting" }
        return "From the preset: \(presetName ?? "none")"
    }

    /// Nieznany język nigdy nie staje się Auto: Auto to wyłącznie jawny wybór.
    static func languageChoice(isAuto: Bool, language: LanguageCode?) -> LanguageChoice {
        isAuto ? .auto : (language.map(LanguageChoice.code) ?? .unset)
    }

    @MainActor static func transcribeBlocker(item: SessionItem, model: AppModel) -> String? {
        TranscribeAgain.blocker(audioDeletedAfterDays: item.audioDeletedAfterDays, transcribing: model.isTranscribing(item),
                                moving: model.recordingsMove != nil)
    }
}

/// Szkic okna Transcript (tylko w pamięci). Ręczna zmiana dostawcy lub modelu korekty zdejmuje „Use preset".
final class TranscriptModelsDraft: ObservableObject {
    @Published var asrProviderID: UUID?
    @Published var asrModel = ""
    @Published var language = LanguageChoice.unset
    @Published var correctProviderID: UUID? { didSet { usePreset = false } }
    @Published var correctModel = "" { didSet { usePreset = false } }
    @Published var usePreset = false

    /// `true` = korekta wystartowała (okno wolno zamknąć).
    @MainActor
    func submitCorrection(item: SessionItem, notes: NotesModel, preset: RoleAssignment?) -> Bool {
        guard let draft = ModelsSheetRules.draft(providerID: correctProviderID, model: correctModel, thinking: nil, preset: preset,
                                                 hasOverride: notes.overrides(for: item).correction != nil, usePreset: usePreset)
        else { return false }
        return notes.improveTranscript(item, draft: draft)
    }

    func resetToPreset(_ preset: RoleAssignment?) {
        correctProviderID = preset?.providerID
        correctModel = preset?.model ?? ""
        usePreset = true
    }
}
