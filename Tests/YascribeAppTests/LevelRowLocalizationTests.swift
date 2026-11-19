import Foundation
import Testing
@testable import YascribeApp

@Test @MainActor func levelRowTrackKindDoesNotDependOnDisplayedText() {
    let microphone = LevelRow(kind: .microphone, detail: "Mikrofon: urządzenie", db: -20)
    let system = LevelRow(kind: .system, detail: "Microphone: device", db: -20)
    #expect(microphone.iconName == "mic")
    #expect(system.iconName == "speaker.wave.2")
    #expect(microphone.kind.muteLabel(muted: false) == "Mute microphone")
    #expect(microphone.kind.muteHelp(muted: true) == "Record microphone again")
    #expect(system.kind.muteLabel(muted: false) == "Mute system audio")
    #expect(system.kind.muteHelp(muted: true) == "Record system audio again")
}

@Test func polishRecordingLabelsExist() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/pl.lproj/Localizable.strings"))
    let strings = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    #expect(strings["Microphone"] == "Mikrofon")
    #expect(strings["Mute microphone"] == "Wycisz mikrofon")
    #expect(strings["Record microphone again"] == "Wznów nagrywanie mikrofonu")
}
