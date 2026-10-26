import Foundation
import Testing
@testable import YascribeMeetings

// Stała strefa: koniec dnia nie może zależeć od strefy maszyny, na której lecą testy.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    return c
}()
private let now = cal.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10))!
private let teams = "Join: <https://teams.microsoft.com/meet/123456?p=abc>"

private func event(_ title: String, in minutes: Double, length: Double = 30, isAllDay: Bool = false,
                   myStatus: CalendarEventInfo.ParticipantStatus = .accepted, isCanceled: Bool = false,
                   notes: String? = teams) -> CalendarEventInfo {
    CalendarEventInfo(title: title, start: now + minutes * 60, end: now + (minutes + length) * 60, isAllDay: isAllDay,
                      myStatus: myStatus, isCanceled: isCanceled, notes: notes, eventIdentifier: title)
}

private func pick(_ events: [CalendarEventInfo], at t: Date = now) -> ComingUp { ComingUp.of(events, now: t, calendar: cal) }

@Test func cardShowsAMeetingStartingWithinSixtyMinutesInclusive() {
    #expect(pick([event("A", in: 59)]).next?.title == "A")
    #expect(pick([event("A", in: 60)]).next?.title == "A")
    let late = pick([event("A", in: 61)])
    #expect(late.next == nil)
    #expect(late.later.map(\.title) == ["A"])  // nie na karcie, ale w „Later today"
}

@Test func cardShowsAnOngoingMeetingAndDropsEndedOnes() {
    #expect(pick([event("Ongoing", in: -10, length: 30)]).next?.title == "Ongoing")
    let ended = pick([event("Ended", in: -40, length: 30)])
    #expect(ended.next == nil && ended.later.isEmpty)
}

@Test func nearestStartWinsBetweenOngoingAndUpcoming() {
    // trwa od 50 min, następne za 5 → karta dla następnego; trwa od 2 min, następne za 30 → karta dla trwającego
    #expect(pick([event("Ongoing", in: -50, length: 60), event("Soon", in: 5)]).next?.title == "Soon")
    let r = pick([event("Ongoing", in: -2, length: 60), event("Soon", in: 30)])
    #expect(r.next?.title == "Ongoing")
    #expect(r.later.map(\.title) == ["Soon"])
}

@Test func allDayAndOutOfOfficeAreHidden() {
    let birthday = event("Birthday", in: -600, length: 24 * 60, isAllDay: true, notes: nil)
    let ooo = event("OOO", in: -600, length: 72 * 60, myStatus: .none, notes: nil)
    let r = pick([birthday, ooo, event("Later", in: 200)])
    #expect(r.next == nil)
    #expect(r.later.map(\.title) == ["Later"])
    // całodniowe za 30 min (flaga, nie długość) też odpada
    #expect(pick([event("Holiday", in: 30, isAllDay: true)]).next == nil)
}

@Test func declinedAndCanceledAreHiddenButMeetingsWithoutALinkAreShown() {
    #expect(pick([event("Declined", in: 10, myStatus: .declined), event("Canceled", in: 20, isCanceled: true)]) == ComingUp(next: nil, later: []))
    let dentist = event("Dentist", in: 10, notes: nil)
    #expect(pick([dentist]).next?.title == "Dentist")
    #expect(ComingUp.appName(dentist) == nil)
}

@Test func laterTodayStopsAtMidnight() {
    let lateEvening = cal.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 23, minute: 20))!
    let tonight = CalendarEventInfo(title: "Tonight", start: lateEvening + 600, end: lateEvening + 1800)  // 23:30
    let tomorrow = CalendarEventInfo(title: "Tomorrow", start: lateEvening + 3000, end: lateEvening + 4800)  // 00:10, w 60 min
    let r = pick([tomorrow, tonight], at: lateEvening)
    #expect(r.next?.title == "Tonight")
    #expect(r.later.isEmpty)
    #expect(pick([tomorrow], at: lateEvening).next == nil)
}

@Test func laterTodayIsSortedByStartWithoutTheCard() {
    let r = pick([event("C", in: 360), event("A", in: 8), event("B", in: 90)])
    #expect(r.next?.title == "A")
    #expect(r.later.map(\.title) == ["B", "C"])
}

@Test func appNameAndTimingLabels() {
    #expect(ComingUp.appName(event("T", in: 8)) == "Teams")
    #expect(ComingUp.appName(event("G", in: 8, notes: "https://meet.google.com/abc-defg-hij")) == "Google Meet")
    #expect(ComingUp.appName(event("Z", in: 8, notes: "zoom.us/j/55")) == "Zoom")
    #expect(ComingUp.timing(event("A", in: 7.5), now: now) == "Next · in 8 min")
    #expect(ComingUp.timing(event("A", in: -5), now: now) == "Now · started 5 min ago")
    #expect(ComingUp.timing(event("A", in: 0), now: now) == "Now · starting")
}
