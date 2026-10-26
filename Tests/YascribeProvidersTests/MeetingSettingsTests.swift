import Foundation
import Testing
@testable import YascribeProviders

@Test func oldSettingsJSONWithoutMeetingsDecodes() throws {
    let old = #"{"defaultPresetID":"12345678-1234-1234-1234-123456789012"}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(GlobalSettings.self, from: old)
    #expect(settings.meetings == nil)
}

@Test func defaultsMatchTheSpec() {
    let m = MeetingSettings()
    #expect(m.detectCallsOrDefault == true)
    #expect(m.autoStartOrDefault == false)
    #expect(m.launchAtLoginOrDefault == false)
    #expect(m.appleCalendarOrDefault == false)
}

@Test func meetingSettingsRoundTrips() throws {
    var m = MeetingSettings()
    m.detectCalls = false
    m.autoStart = true
    m.calendarIDs = ["local-123"]
    m.ignoredApps = ["com.apple.Whisper"]
    let encoded = try JSONEncoder().encode(m)
    let decoded = try JSONDecoder().decode(MeetingSettings.self, from: encoded)
    #expect(decoded == m)
}
