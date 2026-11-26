import AppKit
import Foundation
import Testing
import YascribeMeetings
import YascribeProviders
@testable import YascribeApp

@Test @MainActor func autoPresetMatchesEventAndManualChoiceWins() throws {
    _ = NSApplication.shared
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", data.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    defer { try? FileManager.default.removeItem(at: data) }

    let asr = RoleAssignment(providerID: UUID(), model: "m")
    let first = Preset(name: "Default", language: .polish, asr: asr)
    let second = Preset(name: "Standup", language: .polish, asr: asr,
                        rules: PresetRules(titleContains: ["Standup"]))
    model.presets.presets = [first, second]
    model.settings.defaultPresetID = first.id
    #expect(model.activePreset?.id == first.id)

    model.applyAutoPreset(key: "k1", event: CalendarEventInfo(title: "Daily standup", start: .now,
                                                             end: .now.addingTimeInterval(1800)), app: nil)
    #expect(model.activePreset?.id == second.id)
    #expect(model.activePresetID == nil)
    #expect(model.selectedPreset?.id == first.id)  // dyktowanie i słownik nie widzą auto-wyboru

    model.chooseManually(first.id, key: "k1")
    #expect(model.activePreset?.id == first.id)
}
