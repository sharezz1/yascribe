import Foundation
import Testing
@testable import YascribeMeetings

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func fields(availability: Int? = 0, status: Int? = 1, myParticipantStatus: Int? = 2, isOrganizer: Bool = false,
                    hasRecurrenceRules: Bool = false, occurrenceStart: Date? = nil) -> EventFields {
    EventFields(title: "Event", start: t0, end: t0 + 1800, availability: availability, status: status,
                myParticipantStatus: myParticipantStatus, isOrganizer: isOrganizer, hasRecurrenceRules: hasRecurrenceRules,
                occurrenceStart: occurrenceStart)
}

@Test func unavailableAvailabilityMapsToUnavailable() {
    #expect(EventMapping.map(fields(availability: 3)).availability == .unavailable)
    #expect(EventMapping.map(fields(availability: 0)).availability == .busy)
    #expect(EventMapping.map(fields(availability: 1)).availability == .free)
    #expect(EventMapping.map(fields(availability: 2)).availability == .tentative)
    #expect(EventMapping.map(fields(availability: -1)).availability == .notSupported)
}

@Test func declinedParticipantMapsToDeclined() {
    #expect(EventMapping.map(fields(myParticipantStatus: 3)).myStatus == .declined)
    #expect(EventMapping.map(fields(myParticipantStatus: 2)).myStatus == .accepted)
    #expect(EventMapping.map(fields(myParticipantStatus: 4)).myStatus == .tentative)
}

@Test func unknownParticipantStatusMapsToPendingNotNone() {
    for raw in [0, 1, 5, 6, 7, 99] {
        #expect(EventMapping.map(fields(myParticipantStatus: raw)).myStatus == .pending)
    }
}

@Test func noUserEntryMapsToNone() {
    #expect(EventMapping.map(fields(myParticipantStatus: nil)).myStatus == .none)
}

@Test func canceledStatusMapsToIsCanceled() {
    #expect(EventMapping.map(fields(status: 3)).isCanceled)
    #expect(!EventMapping.map(fields(status: 1)).isCanceled)
}

@Test func recurringEventKeepsExternalIDAndOccurrenceStart() {
    let occ = t0 + 86_400
    var f = fields(hasRecurrenceRules: true, occurrenceStart: occ)
    f.externalIdentifier = "ext-1"
    f.eventIdentifier = "ev-1"
    let e = EventMapping.map(f)
    #expect(e.externalIdentifier == "ext-1")
    #expect(e.eventIdentifier == "ev-1")
    #expect(e.occurrenceStart == occ)
    // wydarzenie niecykliczne nie dostaje daty wystąpienia, nawet gdy EventKit ją poda
    #expect(EventMapping.map(fields(hasRecurrenceRules: false, occurrenceStart: occ)).occurrenceStart == nil)
}

@Test func missingFieldsDoNotCrash() {
    let e = EventMapping.map(EventFields(start: t0, end: t0))
    #expect(e.title == "")
    #expect(e.availability == .busy)
    #expect(e.myStatus == .none)
    #expect(!e.isCanceled)
    #expect(e.url == nil && e.location == nil && e.notes == nil && e.calendarName == nil)
    #expect(e.attendees.isEmpty)
    #expect(e.occurrenceStart == nil)
}

@Test func organizerFlagIsCarried() {
    #expect(EventMapping.map(fields(isOrganizer: true)).isOrganizer)
    #expect(!EventMapping.map(fields(isOrganizer: false)).isOrganizer)
}
