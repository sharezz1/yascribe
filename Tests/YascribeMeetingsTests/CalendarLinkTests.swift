import Foundation
import Testing
@testable import YascribeMeetings

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func event(external: String? = "ext", occurrence: Date? = nil) -> CalendarEventInfo {
    CalendarEventInfo(title: "Weekly", start: t0, end: t0 + 1800, attendees: [.init(name: "A", email: "a@example.com")],
                      calendarName: "Work", eventIdentifier: "local", externalIdentifier: external, occurrenceStart: occurrence)
}

@Test func eventIDDiffersPerOccurrenceOfARecurringEvent() {
    #expect(event(occurrence: t0).id != event(occurrence: t0 + 7 * 86_400).id)
    #expect(event(occurrence: t0).id == event(occurrence: t0).id)
}

@Test func eventLinkCopiesTheSnapshotAndRoundTrips() throws {
    let link = event(occurrence: t0).link()
    #expect(link.title == "Weekly" && link.externalIdentifier == "ext" && link.attendees?.first?.email == "a@example.com")
    #expect(try JSONDecoder().decode(CalendarLink.self, from: JSONEncoder().encode(link)) == link)
}

@Test func tuningDefaultsMatchTheSpikeReport() {
    let t = MeetingTuning()
    #expect(t.offerLead == 60 && t.offerGrace == 600 && t.maxEventHours == 8)
    #expect(t.startSeconds == 12 && t.releaseSeconds == 20 && t.silenceSeconds == 180 && t.snoozeSeconds == 600)
    #expect(t.callApps == ["com.microsoft.teams2"] && !t.linkPatterns.contains("webex.com"))
}
