import EventKit
import Foundation
import YascribeMeetings

/// Apple Calendar przez EventKit, tylko do odczytu. Brak dostępu → puste wyniki, nic nie rzuca.
/// Nie loguje ani nie zapisuje tytułów, uczestników ani adresów.
// Nagłówki EventKit dopuszczają zapytania poza wątkiem głównym, ale nie gwarantują thread-safety `EKEventStore`;
// `@unchecked`, bo wołamy z jednego aktora (monitor, T10).
final class EventKitCalendar: CalendarSource, @unchecked Sendable {
    private let store = EKEventStore()

    func authorization() -> CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        guard authorization() == .granted else { return [] }
        return store.calendars(for: .event).map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    func events(from: Date, to: Date, calendarIDs: [String]?) -> [CalendarEventInfo] {
        guard authorization() == .granted else { return [] }
        var cals: [EKCalendar]?
        if let ids = calendarIDs {
            let chosen = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            guard !chosen.isEmpty else { return [] }  // pusta lista dla EventKit znaczy „wszystkie"
            cals = chosen
        }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals))
            .map { EventMapping.map(Self.fields($0)) }
    }

    var changes: AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont in
            nonisolated(unsafe) let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
                cont.yield()
            }
            cont.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    private static func fields(_ e: EKEvent) -> EventFields {
        let me = e.attendees?.first { $0.isCurrentUser }
        return EventFields(
            title: e.title, start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
            availability: e.availability.rawValue, status: e.status.rawValue,
            myParticipantStatus: me.map { $0.participantStatus.rawValue },
            isOrganizer: e.organizer?.isCurrentUser ?? false, url: e.url, location: e.location, notes: e.notes,
            attendees: (e.attendees ?? []).map {
                .init(name: $0.name, email: $0.url.scheme == "mailto" ? String($0.url.absoluteString.dropFirst("mailto:".count)) : nil)
            },
            calendarName: e.calendar?.title, eventIdentifier: e.eventIdentifier,
            externalIdentifier: e.calendarItemExternalIdentifier, hasRecurrenceRules: e.hasRecurrenceRules,
            occurrenceStart: e.occurrenceDate)
    }
}
