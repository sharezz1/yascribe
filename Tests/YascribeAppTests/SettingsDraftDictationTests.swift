import Testing
import YascribeProviders
@testable import YascribeApp

@Suite("Settings dictation draft")
struct SettingsDraftDictationTests {
    @Test func cancelReloadsSavedDictation() {
        var saved = GlobalSettings()
        saved.dictation = DictationSettings(triggerMode: .hold, showLauncher: true)
        let draft = SettingsDraft()
        draft.load(saved)
        draft.dictation.triggerMode = .toggle
        #expect(draft.dictationForComparison != SettingsDraft.comparableDictation(saved.dictationOrDefault))
        draft.load(saved)
        #expect(draft.dictationForComparison == SettingsDraft.comparableDictation(saved.dictationOrDefault))
    }

    @Test func movingLauncherDoesNotMakeDraftDirty() {
        let draft = SettingsDraft()
        var saved = GlobalSettings()
        draft.load(saved)
        saved.dictation = DictationSettings(launcherOriginX: 123)
        #expect(draft.dictationForComparison == SettingsDraft.comparableDictation(saved.dictationOrDefault))
    }
}
