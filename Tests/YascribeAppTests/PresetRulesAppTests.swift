import AppKit
import Foundation
import Testing
import YascribeMeetings
import YascribeProviders
@testable import YascribeApp

@MainActor private func makeModel() -> (AppModel, URL) {
    _ = NSApplication.shared
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID().uuidString)")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", data.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    return (model, data)
}

@Test @MainActor func autoPresetMatchesEventAndManualChoiceWins() throws {
    let (model, data) = makeModel()
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

@Test @MainActor func movePresetReordersAndClamps() throws {
    let (model, data) = makeModel()
    defer { try? FileManager.default.removeItem(at: data) }

    let asr = RoleAssignment(providerID: UUID(), model: "m")
    let a = Preset(name: "A", language: .polish, asr: asr)
    let b = Preset(name: "B", language: .polish, asr: asr)
    let c = Preset(name: "C", language: .polish, asr: asr)
    model.presets.presets = [a, b, c]

    model.movePreset(c.id, by: -1)
    #expect(model.presets.presets.map(\.id) == [a.id, c.id, b.id])

    model.movePreset(a.id, by: -1)
    #expect(model.presets.presets.map(\.id) == [a.id, c.id, b.id])

    model.movePreset(c.id, by: 5)
    #expect(model.presets.presets.map(\.id) == [a.id, b.id, c.id])
}
