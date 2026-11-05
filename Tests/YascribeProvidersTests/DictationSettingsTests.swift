import Foundation
import Testing
@testable import YascribeProviders

@Test func defaultsAreHoldFnCorrectionOffLauncherOn() {
    let s = DictationSettings()
    #expect(s.hotkeyOrDefault == .fn)
    #expect(s.triggerModeOrDefault == .hold)
    #expect(s.correctionEnabled == false)
    #expect(s.showLauncherOrDefault == true)
}

@Test func oldSettingsJSONDecodesWithoutDictation() throws {
    // Lekcja E6: stary settings.json nie ma klucza `dictation`.
    let g = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    #expect(g.dictation == nil)
    #expect(g.dictationOrDefault.hotkeyOrDefault == .fn)
}

@Test func roundTripKeepsHotkeyAndModels() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dict-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let asr = RoleAssignment(providerID: UUID(), model: "asr-model")
    let fix = RoleAssignment(providerID: UUID(), model: "fix-model")
    let hotkey = DictationHotkey(keyCode: 49, flags: 0x100000, isModifierOnly: false)
    let settings = GlobalSettings(dictation: DictationSettings(
        hotkey: hotkey, triggerMode: .toggle, asr: asr, language: .polish,
        correction: DictationCorrectionSettings(enabled: true, model: fix)))
    try JSONFile.save(settings, to: url)
    let loaded = try JSONFile.load(GlobalSettings.self, from: url, default: GlobalSettings())
    #expect(loaded.dictation?.hotkey == hotkey)
    #expect(loaded.dictation?.triggerMode == .toggle)
    #expect(loaded.dictation?.asr == asr)
    #expect(loaded.dictation?.correction?.model == fix)
    #expect(loaded.dictation?.language == .polish)
}

@Test func dictationHistoryPathIsInDataRoot() {
    #expect(YascribePaths(root: URL(fileURLWithPath: "/x")).dictationHistory.path == "/x/dictation-history.json")
}
