import Foundation
import Testing
@testable import MeetNotesMeetings

private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10))!
private let teamsNotes = "Join: <https://teams.microsoft.com/meet/123456?p=abc> Or webex.com for video devices"

private func fixture(minutes: Double = 30, isAllDay: Bool = false, availability: CalendarEventInfo.Availability = .busy,
                     myStatus: CalendarEventInfo.ParticipantStatus = .accepted, isCanceled: Bool = false,
                     url: URL? = nil, location: String? = nil, notes: String? = teamsNotes,
                     attendees: [CalendarLink.Attendee] = [], isOrganizer: Bool = false) -> CalendarEventInfo {
    CalendarEventInfo(title: "Event", start: day, end: day + minutes * 60, isAllDay: isAllDay, availability: availability,
                      myStatus: myStatus, isCanceled: isCanceled, url: url, location: location, notes: notes, attendees: attendees,
                      isOrganizer: isOrganizer)
}

private func offerable(_ e: CalendarEventInfo) -> Bool { EventFilter.isOfferable(e, tuning: MeetingTuning()) }

@Test func teamsMeetingWithLinkInNotesIsOfferable() {
    #expect(offerable(fixture()))
}

@Test func doctorsVisitWithoutALinkIsNotOfferable() {
    #expect(!offerable(fixture(location: "Przychodnia, ul. Długa 1", notes: nil)))
}

@Test func allDayBirthdayIsNotOfferable() {
    #expect(!offerable(fixture(minutes: 24 * 60, isAllDay: true, notes: nil)))
    // sama flaga całodniowego (link jest, czas mieści się w progu) też odcina
    #expect(!offerable(fixture(minutes: 60, isAllDay: true)))
}

@Test func allDayOutOfOfficeIsNotOfferable() {
    #expect(!offerable(fixture(minutes: 24 * 60, isAllDay: true, myStatus: .none, notes: nil)))
    // nawet z linkiem: całodniowe odpada samo
    #expect(!offerable(fixture(minutes: 24 * 60, isAllDay: true)))
}

@Test func exchangeOutOfOfficeShownAsBusyIsNotOfferable() {
    let ooo = fixture(minutes: 72 * 60, isAllDay: true, availability: .busy, myStatus: .none, notes: nil)
    #expect(!offerable(ooo))
    #expect(!EventFilter.isPickable(ooo))
    // ten sam kształt, czas w progu: odcinają go wyłącznie brak linku i flaga całodniowego, nie dostępność
    #expect(!offerable(fixture(minutes: 60, isAllDay: true, availability: .busy, myStatus: .none, notes: nil)))
}

@Test func timedOutOfOfficeWithoutLinkIsNotOfferable() {
    #expect(!offerable(fixture(minutes: 5 * 60, myStatus: .none, notes: nil)))
}

@Test func multiDayBlockIsNotOfferableEvenWithALink() {
    #expect(!offerable(fixture(minutes: 72 * 60)))
    // krótki, ale przez północ: inny dzień kalendarzowy
    let overnight = CalendarEventInfo(title: "Night", start: day + 13 * 3600, end: day + 15 * 3600, notes: teamsNotes)
    #expect(!offerable(overnight))
    // próg godzin
    #expect(offerable(fixture(minutes: 8 * 60)))  // dokładnie próg, ten sam dzień
    #expect(!offerable(fixture(minutes: 8 * 60 + 1)))
}

@Test func declinedAndCanceledAreNotOfferable() {
    #expect(!offerable(fixture(myStatus: .declined)))
    #expect(!offerable(fixture(isCanceled: true)))
}

@Test func unansweredInvitationIsNotOfferable() {
    #expect(!offerable(fixture(availability: .tentative, myStatus: .pending)))
}

@Test func acceptedAndTentativeAndOwnEventsAreOfferable() {
    #expect(offerable(fixture(myStatus: .accepted)))
    #expect(offerable(fixture(myStatus: .tentative)))
    #expect(offerable(fixture(myStatus: .none)))
}

@Test func foreignEventWithoutAResponseIsNotOfferableButOwnOnesAre() {
    let others = [CalendarLink.Attendee(name: "Ola", email: "ola@example.com")]
    // obce lub udostępnione: są uczestnicy, użytkownik nie jest organizatorem, status .none → nie jest jego spotkaniem
    #expect(!offerable(fixture(myStatus: .none, attendees: others)))
    // własne: bez uczestników albo jako organizator
    #expect(offerable(fixture(myStatus: .none, attendees: [])))
    #expect(offerable(fixture(myStatus: .none, attendees: others, isOrganizer: true)))
    // odpowiedź (accepted/tentative) nadal wystarcza, także przy uczestnikach
    #expect(offerable(fixture(myStatus: .accepted, attendees: others)))
    #expect(offerable(fixture(myStatus: .tentative, attendees: others)))
}

@Test func teamsMeetLinkInNotesIsRecognised() {
    let url = EventFilter.meetingURL(in: fixture(), patterns: MeetingTuning().linkPatterns)
    #expect(url?.absoluteString == "https://teams.microsoft.com/meet/123456?p=abc")
}

@Test func webexAloneIsNotAMeetingLink() {
    let e = fixture(location: "Microsoft Teams", notes: "Join with a video system: example@m.webex.com or https://www.webex.com/")
    #expect(EventFilter.meetingURL(in: e, patterns: MeetingTuning().linkPatterns) == nil)
    #expect(!offerable(e))
}

@Test func meetingWithLinkButNoOtherAttendeesIsOfferable() {
    #expect(offerable(fixture(attendees: [])))
}

@Test func linkPatternsMatchTeamsMeetZoomWebex() {
    let p = MeetingTuning().linkPatterns
    #expect(EventFilter.meetingURL(in: fixture(notes: "https://TEAMS.microsoft.com/meet/1"), patterns: p) != nil)  // wielkość liter
    #expect(EventFilter.meetingURL(in: fixture(notes: "https://us02web.zoom.us/j/123"), patterns: p)?.host == "us02web.zoom.us")
    #expect(EventFilter.meetingURL(in: fixture(notes: "https://meet.google.com/abc-defg-hij"), patterns: p) != nil)
    #expect(EventFilter.meetingURL(in: fixture(notes: "https://acme.webex.com/meet/x"), patterns: p) == nil)
    // kolejność pól: notes przed url przed location
    let both = fixture(url: URL(string: "https://zoom.us/j/9"), location: "https://meet.google.com/x", notes: "https://teams.microsoft.com/meet/1")
    #expect(EventFilter.meetingURL(in: both, patterns: p)?.host == "teams.microsoft.com")
    #expect(EventFilter.meetingURL(in: fixture(url: URL(string: "https://zoom.us/j/9"), location: "https://meet.google.com/x", notes: nil), patterns: p)?.host == "zoom.us")
    #expect(EventFilter.meetingURL(in: fixture(location: "https://meet.google.com/x", notes: nil), patterns: p)?.host == "meet.google.com")
    // adres bez schematu dostaje https://
    #expect(EventFilter.meetingURL(in: fixture(notes: "zoom.us/j/55."), patterns: p)?.absoluteString == "https://zoom.us/j/55")
}

@Test func pickableHidesAllDayAndOOOButKeepsInPersonEvents() {
    #expect(EventFilter.isPickable(fixture(myStatus: .pending, notes: nil)))              // stacjonarne, bez linku i odpowiedzi
    #expect(!EventFilter.isPickable(fixture(minutes: 24 * 60, isAllDay: true)))
    #expect(!EventFilter.isPickable(fixture(minutes: 72 * 60)))                            // wielodniowy blok bez flagi całodniowego
    #expect(EventFilter.isPickable(fixture(minutes: 23 * 60 + 59)))
}

@Test func organizerWithPendingEntryIsOfferable() {
    // Exchange wpisuje organizatora na listę uczestników ze statusem unknown/pending
    let others = [CalendarLink.Attendee(name: "Ola", email: "ola@example.com")]
    #expect(offerable(fixture(myStatus: .pending, attendees: others, isOrganizer: true)))
}

@Test func nonOrganizerPendingStillNotOfferable() {
    let others = [CalendarLink.Attendee(name: "Ola", email: "ola@example.com")]
    #expect(!offerable(fixture(myStatus: .pending, attendees: others, isOrganizer: false)))
}

@Test func declinedOrganizerStillNotOffered() {
    // jawne .declined odrzuca także organizatora
    #expect(!offerable(fixture(myStatus: .declined, isOrganizer: true)))
}
