import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeApp

/// Zgoda na dostęp agentów (§13.11): szkic, nie zapis od razu — jak embedding i modele.
@Suite("Settings agent access draft")
struct SettingsDraftAgentAccessTests {
    @Test func changingOnlyTheConsentMakesTheDraftDirty() {
        var saved = GlobalSettings()
        let draft = SettingsDraft()
        draft.load(saved)
        #expect(!draft.isDirty(comparedTo: saved, prompts: PromptOverrides()))
        draft.agentAccess = true
        #expect(draft.isDirty(comparedTo: saved, prompts: PromptOverrides()))
    }

    @Test func commitWritesTrueAndAFreshDraftReadsItBack() {
        var saved = GlobalSettings()
        let draft = SettingsDraft()
        draft.load(saved)
        draft.agentAccess = true
        saved.agentAccess = draft.agentAccessValue
        #expect(saved.agentAccess == true)
        #expect(saved.agentAccessEnabled)
        #expect(!draft.isDirty(comparedTo: saved, prompts: PromptOverrides()))
        let fresh = SettingsDraft()
        fresh.load(saved)
        #expect(fresh.agentAccess)
    }

    @Test func turningTheConsentOffWritesNil() {
        var saved = GlobalSettings()
        saved.agentAccess = true
        let draft = SettingsDraft()
        draft.load(saved)
        #expect(draft.agentAccess)
        draft.agentAccess = false
        #expect(draft.isDirty(comparedTo: saved, prompts: PromptOverrides()))
        #expect(draft.agentAccessValue == nil)
        saved.agentAccess = draft.agentAccessValue
        #expect(!saved.agentAccessEnabled)
    }
}
