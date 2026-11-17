import Testing
import YascribeMeetings
@testable import YascribeApp

@Test func speakerPickerAttendeesFallbackAndEmptyNames() {
    let result = SpeakerPickerOptions.make(attendees: [.init(name: nil, email: "mail@example.com"), .init(name: "", email: "ignored@example.com"), .init(name: "  "), .init()], known: [], query: "", currentName: nil)
    #expect(result.attendees == ["mail@example.com"])
    #expect(result.typed == nil)
    #expect(!result.canClear)
}

@Test func speakerPickerFiltersAndDeduplicates() {
    let attendees: [CalendarLink.Attendee] = [.init(name: "Ala"), .init(name: "Bob")]
    let result = SpeakerPickerOptions.make(attendees: attendees, known: ["ALA", "Alina", "Ola"], query: " aL ", currentName: "Ala")
    #expect(result.attendees == ["Ala"])
    #expect(result.known == ["Alina"])
    #expect(result.typed == "aL")
    #expect(result.canClear)
    let exact = SpeakerPickerOptions.make(attendees: attendees, known: ["Alina"], query: " aLA ", currentName: nil)
    #expect(exact.typed == nil)
    let recent = SpeakerPickerOptions.make(attendees: attendees, known: ["Alina"], query: "alina", currentName: nil)
    #expect(recent.typed == nil)
}
