import Foundation

/// Migawka wydarzenia powiązanego z notatką (`notes/meta.json`). Notatka pokazuje ją bez dostępu do kalendarza;
/// wszystkie pola poza tytułem i czasem są opcjonalne (lekcja E6).
public struct CalendarLink: Codable, Equatable, Sendable {
    public struct Attendee: Codable, Equatable, Sendable {
        public var name: String?
        public var email: String?
        public init(name: String? = nil, email: String? = nil) {
            self.name = name
            self.email = email
        }
    }

    public var title: String
    public var start: Date
    public var end: Date
    public var calendarName: String?
    public var attendees: [Attendee]?
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var occurrenceStart: Date?

    public init(title: String, start: Date, end: Date, calendarName: String? = nil, attendees: [Attendee]? = nil,
                eventIdentifier: String? = nil, externalIdentifier: String? = nil, occurrenceStart: Date? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.calendarName = calendarName
        self.attendees = attendees
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.occurrenceStart = occurrenceStart
    }
}
