import Foundation

/// Wydarzenie z kalendarza w kształcie niezależnym od EventKit (adapter w `MeetNotesApp` je wypełnia). Nie jest zapisywane.
public struct CalendarEventInfo: Identifiable, Equatable, Sendable {
    public enum Availability: Equatable, Sendable { case busy, free, tentative, unavailable, notSupported }
    public enum ParticipantStatus: Equatable, Sendable { case accepted, declined, tentative, pending, none }

    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var availability: Availability
    public var myStatus: ParticipantStatus
    public var isCanceled: Bool
    public var url: URL?
    public var location: String?
    public var notes: String?
    public var attendees: [CalendarLink.Attendee]
    public var calendarName: String?
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var occurrenceStart: Date?

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, availability: Availability = .busy,
                myStatus: ParticipantStatus = .accepted, isCanceled: Bool = false, url: URL? = nil, location: String? = nil,
                notes: String? = nil, attendees: [CalendarLink.Attendee] = [], calendarName: String? = nil,
                eventIdentifier: String? = nil, externalIdentifier: String? = nil, occurrenceStart: Date? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
        self.myStatus = myStatus
        self.isCanceled = isCanceled
        self.url = url
        self.location = location
        self.notes = notes
        self.attendees = attendees
        self.calendarName = calendarName
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceStart = occurrenceStart
    }

    /// Stabilny na wystąpienie: wydarzenia cykliczne dzielą identyfikator serii, więc dochodzi data wystąpienia.
    public var id: String {
        (externalIdentifier ?? eventIdentifier ?? title) + "|" + (occurrenceStart ?? start).formatted(.iso8601)
    }

    public func link() -> CalendarLink {
        CalendarLink(title: title, start: start, end: end, calendarName: calendarName, attendees: attendees,
                     eventIdentifier: eventIdentifier, externalIdentifier: externalIdentifier, occurrenceStart: occurrenceStart)
    }
}
