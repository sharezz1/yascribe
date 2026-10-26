import Testing
import YascribeSessionFormat

@Test func sameDeviceIgnoresTheInputOutputSuffix() {
    #expect(DeviceUID.same("00-02-3C-8D-E0-50:input", "00-02-3C-8D-E0-50:output"))
    #expect(DeviceUID.same("BuiltInMicrophoneDevice", "BuiltInMicrophoneDevice"))
    #expect(!DeviceUID.same("device:input:extra", "device:output:extra"))
}

@Test func differentDevicesAreNotTheSame() {
    #expect(!DeviceUID.same("BuiltInMicrophoneDevice", "BuiltInSpeakerDevice"))
}

@Test func emptyUIDsAreNeverTheSame() {
    #expect(!DeviceUID.same("", ""))
    #expect(!DeviceUID.same("", "00-02-3C-8D-E0-50:output"))
    #expect(!DeviceUID.same("00-02-3C-8D-E0-50:input", ""))
}
