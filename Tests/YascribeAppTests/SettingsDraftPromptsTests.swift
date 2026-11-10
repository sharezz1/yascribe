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
}
