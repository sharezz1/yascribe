import Testing
@testable import YascribeMeetings

@Test func statusNamesOnlyWhatIsActuallyDetected() {
    #expect(DetectionStatus.text(calls: false, calendar: false, problem: nil) == "Detection off")
    #expect(DetectionStatus.text(calls: true, calendar: false, problem: nil) == "Detecting calls")
    #expect(DetectionStatus.text(calls: false, calendar: true, problem: nil) == "Detecting calendar events")
    #expect(DetectionStatus.text(calls: true, calendar: true, problem: nil) == "Detecting meetings")
}

@Test func calendarProblemsOnlyMatterWhenTheCalendarIsOn() {
    #expect(DetectionStatus.text(calls: true, calendar: false, problem: .denied) == "Detecting calls")
    #expect(DetectionStatus.text(calls: true, calendar: true, problem: .denied) == "Detecting calls (calendar access off)")
    #expect(DetectionStatus.text(calls: false, calendar: true, problem: .denied) == "Detection off (calendar access off)")
    #expect(DetectionStatus.text(calls: true, calendar: true, problem: .selectionStale).hasPrefix("Selected calendars not found"))
}
