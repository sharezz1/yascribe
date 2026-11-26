import Foundation
import Testing
import YascribeProviders
@testable import YascribeApp

@Test func reasonDescribesTitleAndDomain() {
    #expect(PresetReasonText.reason(.title("Standup")).contains("Standup"))
    #expect(PresetReasonText.reason(.domain("example.test")).contains("example.test"))
}

@Test func lineAddsWarningForAutoLanguagePreset() {
    let asr = RoleAssignment(providerID: UUID(), model: "m")
    let auto = Preset(name: "A", language: nil, asr: asr, languageAuto: true)
    let match = PresetMatch(presetID: auto.id, reason: .title("Daily"))
    let reason = PresetReasonText.reason(match.reason)
    let line = PresetReasonText.line(match, preset: auto)
    #expect(line.count > reason.count)
    #expect(line.contains("Auto"))
}

@Test func lineForNormalPresetIsJustTheReason() {
    let asr = RoleAssignment(providerID: UUID(), model: "m")
    let normal = Preset(name: "B", language: .polish, asr: asr)
    let match = PresetMatch(presetID: normal.id, reason: .domain("example.test"))
    #expect(PresetReasonText.line(match, preset: normal) == PresetReasonText.reason(match.reason))
}
