import Foundation

/// Surowe pola `EKEvent` jako proste wartości (liczby to `rawValue` enumów EventKit) — mapowanie testuje się bez EventKit.
public struct EventFields: Sendable {
    public var title: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// `EKEventAvailability`: -1 notSupported, 0 busy, 1 free, 2 tentative, 3 unavailable.
    public var availability: Int?
    /// `EKEventStatus`: 0 none, 1 confirmed, 2 tentative, 3 canceled.
    public var status: Int?
    /// `EKParticipantStatus` użytkownika; nil = brak wpisu użytkownika wśród uczestników.
    public var myParticipantStatus: Int?
    public var isOrganizer: Bool
    public var url: URL?
    public var location: String?
    public var notes: String?
    public var attendees: [CalendarLink.Attendee]
    public var calendarName: String?
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var hasRecurrenceRules: Bool
    public var occurrenceStart: Date?

    public init(title: String? = nil, start: Date, end: Date, isAllDay: Bool = false, availability: Int? = nil, status: Int? = nil,
                myParticipantStatus: Int? = nil, isOrganizer: Bool = false, url: URL? = nil, location: String? = nil,
                notes: String? = nil, attendees: [CalendarLink.Attendee] = [], calendarName: String? = nil,
                eventIdentifier: String? = nil, externalIdentifier: String? = nil, hasRecurrenceRules: Bool = false,
                occurrenceStart: Date? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
        self.status = status
        self.myParticipantStatus = myParticipantStatus
        self.isOrganizer = isOrganizer
        self.url = url
        self.location = location
        self.notes = notes
        self.attendees = attendees
        self.calendarName = calendarName
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.hasRecurrenceRules = hasRecurrenceRules
        self.occurrenceStart = occurrenceStart
    }
}

public enum EventMapping {
    public static func map(_ f: EventFields) -> CalendarEventInfo {
        let availability: CalendarEventInfo.Availability = switch f.availability {
        case -1: .notSupported
        case 1: .free
        case 2: .tentative
        case 3: .unavailable
        default: .busy
        }
        // `.none` wyłącznie bez wpisu użytkownika; każdy nieznany/oczekujący stan to `.pending` (nie wpuszcza do oferty).
        let myStatus: CalendarEventInfo.ParticipantStatus = switch f.myParticipantStatus {
        case nil: .none
        case 2: .accepted
        case 3: .declined
        case 4: .tentative
        default: .pending
        }
        return CalendarEventInfo(
            title: f.title ?? "", start: f.start, end: f.end, isAllDay: f.isAllDay, availability: availability,
            myStatus: myStatus, isCanceled: f.status == 3, url: f.url, location: f.location, notes: f.notes,
            attendees: f.attendees, calendarName: f.calendarName, eventIdentifier: f.eventIdentifier,
            externalIdentifier: f.externalIdentifier, occurrenceStart: f.hasRecurrenceRules ? f.occurrenceStart : nil,
            isOrganizer: f.isOrganizer)
    }
}
