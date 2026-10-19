import Foundation
import MeetNotesMeetings
import MeetNotesNotes

// Faza 1.6, T12: ręczne powiązanie notatki z wydarzeniem kalendarza (spec §4.7). Działa też dla starych notatek i ad hoc.

extension AppModel {
    func link(_ event: CalendarEventInfo, to item: SessionItem) { setCalendarEvent(event.link(), for: item) }

    func unlink(_ item: SessionItem) { setCalendarEvent(nil, for: item) }

    /// Apple Calendar włączony w Settings i zgoda przyznana (inaczej lista pokazuje „Connect Apple Calendar in Settings").
    var calendarReady: Bool { settings.meetings?.appleCalendarEnabled == true && calendarSource.authorization() == .granted }

    /// Wydarzenia z dnia nagrania (północ–północ), po rankingu. `[]` bez podłączonego kalendarza.
    func pickableEvents(for item: SessionItem) -> [Ranked] {
        guard calendarReady else { return [] }
        let cal = Calendar.current
        let from = cal.startOfDay(for: item.startedAt)
        let to = cal.date(byAdding: .day, value: 1, to: from) ?? from + 86400
        let events = calendarSource.events(from: from, to: to, calendarIDs: settings.meetings?.calendarIDs)
        return EventRanking.order(events, recordingStart: item.startedAt, recordingEnd: item.duration.map { item.startedAt + $0 }, now: Date())
    }

    /// Wydarzenia dnia `now` (północ–północ) dla „Coming up” na stronie głównej. `[]` bez podłączonego kalendarza.
    func todaysEvents(now: Date) -> [CalendarEventInfo] {
        guard calendarReady else { return [] }
        let from = Calendar.current.startOfDay(for: now)
        return calendarSource.events(from: from, to: Calendar.current.date(byAdding: .day, value: 1, to: from) ?? from + 86400,
                                     calendarIDs: settings.meetings?.calendarIDs)
    }

    private func setCalendarEvent(_ link: CalendarLink?, for item: SessionItem) {
        guard recordingsMove == nil else { lastError = "Meetings are being moved to a new folder. Try again when that finishes."; return }
        do {
            if let note = try NotesStore(session: item.url).updateMeta({ $0.calendarEvent = link }) { lastError = note }
        } catch {
            lastError = "Couldn't save the calendar event: \(error)"
        }
        reloadSessions()
    }
}
