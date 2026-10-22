import CoreAudio
import Testing
@testable import MeetNotesRecording

@Test func tapOnlyLayoutHasNoSubDevices() {
    let d = SystemTapSource.aggregateDescription(layout: .tapOnly, outputUID: "out-uid", tapUUID: "tap-uuid")
    #expect((d[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]])?.isEmpty == true)
    #expect(d[kAudioAggregateDeviceMainSubDeviceKey] == nil)
}

@Test func outputLayoutKeepsTheOutputAsMainSubDevice() {
    let d = SystemTapSource.aggregateDescription(layout: .withOutputSubdevice, outputUID: "out-uid", tapUUID: "tap-uuid")
    #expect(d[kAudioAggregateDeviceMainSubDeviceKey] as? String == "out-uid")
    let list = d[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
    #expect(list?.count == 1)
    #expect(list?.first?[kAudioSubDeviceUIDKey] as? String == "out-uid")
}

@Test func tapOnlyIsTheDefaultLayout() {
    #expect(SystemTapSource.defaultLayout == .tapOnly)
}
