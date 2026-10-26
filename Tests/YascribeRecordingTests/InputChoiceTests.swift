import Testing
@testable import YascribeRecording

private let devices = [InputDevice(uid: "A", name: "MacBook Air Microphone"), InputDevice(uid: "B", name: "Sound Blaster JAM V2")]

@Test func choiceKeepsThePreferredDeviceWhenPresent() {
    #expect(InputChoice.resolve(preferred: "B", available: devices, defaultUID: "A") == "B")
}

@Test func choiceFallsBackToTheDefaultWhenThePreferredDeviceVanishes() {
    // Słuchawki wyłączone w trakcie nagrania: wybrane wejście znika z listy.
    #expect(InputChoice.resolve(preferred: "C", available: devices, defaultUID: "A") == "A")
}

@Test func choiceWithoutPreferenceUsesTheSystemDefault() {
    #expect(InputChoice.resolve(preferred: nil, available: devices, defaultUID: "A") == "A")
}

@Test func choiceIsNilWhenThereIsNothingToChoose() {
    #expect(InputChoice.resolve(preferred: nil, available: [], defaultUID: nil) == nil)
}

@Test func reopenWhenThePreferredDeviceVanished() {
    #expect(InputChoice.needsReopen(current: "B", preferred: "B", available: [devices[0]], defaultUID: "A"))
}

@Test func noReopenWhenTheChoiceIsUnchanged() {
    #expect(!InputChoice.needsReopen(current: "B", preferred: "B", available: devices, defaultUID: "A"))
}
