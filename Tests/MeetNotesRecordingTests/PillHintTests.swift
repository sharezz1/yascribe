import Testing
@testable import MeetNotesRecording

private let hint = "Headset in call mode may block system audio."

@Test func hintAppearsForAStalledTrackOnTheSameBluetoothHeadset() {
    #expect(PillHint.systemStalled(stalled: true, micUID: "00-02-3C-8D-E0-50:input", outputUID: "00-02-3C-8D-E0-50:output",
                                   isBluetooth: true) == hint)
}

@Test func hintIsAbsentWithoutAStall() {
    #expect(PillHint.systemStalled(stalled: false, micUID: "00-02-3C-8D-E0-50:input", outputUID: "00-02-3C-8D-E0-50:output",
                                   isBluetooth: true) == nil)
}

@Test func hintIsAbsentForADifferentOrWiredDevice() {
    #expect(PillHint.systemStalled(stalled: true, micUID: "BuiltInMicrophoneDevice", outputUID: "BuiltInSpeakerDevice",
                                   isBluetooth: false) == nil)
    #expect(PillHint.systemStalled(stalled: true, micUID: "usb-mic:input", outputUID: "usb-mic:output", isBluetooth: false) == nil)
}
