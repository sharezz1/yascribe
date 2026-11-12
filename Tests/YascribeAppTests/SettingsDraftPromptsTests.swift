import Testing
import YascribeNotes
@testable import YascribeApp

@MainActor @Suite("SettingsDraftPrompts") struct SettingsDraftPromptsTests {
    @Test func freshDraftShowsDefaultsAndIsNotDirty() {
        let d = SettingsDraft()
        d.loadPrompts(PromptOverrides())
        #expect(d.promptTexts[.correction] == CorrectionPrompt.defaultBody && d.promptTexts[.summary] == SummaryPrompt.defaultBody)
        #expect(d.promptsApplied(to: PromptOverrides()) == PromptOverrides())
    }

    @Test func editingResetAndKeepMineProduceTheRightOverrides() throws {
        let d = SettingsDraft()
        d.loadPrompts(PromptOverrides())
        d.promptTexts[.summary] = "- Be brief."
        let edited = try #require(d.promptsApplied(to: PromptOverrides()))
        #expect(edited.body(.summary) == "- Be brief." && edited.correction == nil)
        // Reset = domyślny tekst w polu.
        d.loadPrompts(edited)
        d.promptTexts[.summary] = SummaryPrompt.defaultBody
        #expect(d.promptsApplied(to: edited)?.summary == nil)
        // Keep mine na nieaktualnym wpisie.
        let stale = PromptOverrides(correction: PromptEntry(text: "mine", basedOn: "000000000000"))
        d.loadPrompts(stale)
        #expect(d.promptsApplied(to: stale) == stale) // nie jest „dirty" bez decyzji
        d.keepMine.insert(.correction)
        #expect(d.promptsApplied(to: stale)?.isStale(.correction) == false)
        d.loadPrompts(stale) // Cancel czyści decyzję
        #expect(d.keepMine.isEmpty)
    }

    @Test func overLimitBlocksSave() {
        let d = SettingsDraft()
        d.loadPrompts(PromptOverrides())
        d.promptTexts[.correction] = String(repeating: "x", count: 1_501)
        #expect(d.promptsApplied(to: PromptOverrides()) == nil)
    }

    @Test func customMeansTheTextDiffersFromTheDefault() {
        let d = SettingsDraft()
        d.loadPrompts(PromptOverrides())
        #expect(!d.isCustom(.summary))
        d.promptTexts[.summary] = "  " + SummaryPrompt.defaultBody + "\n" // białe znaki na brzegach nie robią z niego własnego
        #expect(!d.isCustom(.summary))
        d.promptTexts[.summary] = "- Be brief."
        #expect(d.isCustom(.summary) && !d.isCustom(.correction))
    }

    @Test func promptSheetEditsTheDraftOnlyOnSave() {
        let d = SettingsDraft()
        d.loadPrompts(PromptOverrides())
        d.openPromptEditor(.correction)
        #expect(d.editingPrompt == .correction && d.promptSheetText == CorrectionPrompt.defaultBody)
        #expect(!d.promptSheetChanged && d.promptSheetIsDefault) // bez zmiany Save jest wyłączony
        d.promptSheetText = "Only fix commas."
        #expect(d.promptSheetChanged && !d.promptSheetIsDefault)
        #expect(d.promptTexts[.correction] == CorrectionPrompt.defaultBody) // szkic bez zmian do Save okna
        d.savePromptSheet()
        #expect(d.editingPrompt == nil && d.promptTexts[.correction] == "Only fix commas." && d.isCustom(.correction))
    }

    @Test func cancelingTheSheetLeavesTheDraftAndDefaultClearsKeepMine() {
        let d = SettingsDraft()
        let stale = PromptOverrides(summary: PromptEntry(text: "mine", basedOn: "000000000000"))
        d.loadPrompts(stale)
        d.keepMine.insert(.summary)
        d.openPromptEditor(.summary)
        d.promptSheetText = "changed"
        d.editingPrompt = nil // Cancel / Esc / klik poza oknem
        #expect(d.promptTexts[.summary] == "mine")
        d.useDefaultPrompt(.summary)
        #expect(!d.isCustom(.summary) && !d.keepMine.contains(.summary))
    }
}
