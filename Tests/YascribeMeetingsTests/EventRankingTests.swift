import Foundation
import Testing
@testable import YascribeMeetings

private let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10))!

private func ev(_ title: String, at offsetMin: Double, minutes: Double = 30, isAllDay: Bool = false,
                notes: String? = nil, location: String? = nil) -> CalendarEventInfo {
    CalendarEventInfo(title: title, start: t0 + offsetMin * 60, end: t0 + (offsetMin + minutes) * 60, isAllDay: isAllDay,
                      location: location, notes: notes)
}

private func titles(_ r: [Ranked]) -> [String] { r.map(\.event.title) }

@Test func eventsAreOrderedByDistanceFromRecordingStart() {
    let r = EventRanking.order([ev("far", at: 120), ev("before", at: -20), ev("exact", at: 0)],
                               recordingStart: t0, recordingEnd: t0 + 3600, now: t0 + 7200)
    #expect(titles(r) == ["exact", "before", "far"])
}

@Test func overlappingEventsAreFlagged() {
    let r = EventRanking.order([ev("during", at: 10), ev("after", at: 90), ev("ended", at: -60, minutes: 30)],
                               recordingStart: t0, recordingEnd: t0 + 3600, now: t0 + 7200)
    #expect(Dictionary(uniqueKeysWithValues: r.map { ($0.event.title, $0.overlapsRecording) }) == ["during": true, "after": false, "ended": false])
}

@Test func allDayAndOutOfOfficeAreNeverListed() {
    let r = EventRanking.order([ev("birthday", at: 0, isAllDay: true), ev("ooo", at: 0, minutes: 48 * 60), ev("standup", at: 5)],
                               recordingStart: t0, recordingEnd: nil, now: t0 + 600)
    #expect(titles(r) == ["standup"])
}

@Test func inPersonEventsWithoutALinkAreListed() {
    let r = EventRanking.order([ev("doctor", at: 0, location: "Clinic, Main St")], recordingStart: t0, recordingEnd: nil, now: t0 + 600)
    #expect(titles(r) == ["doctor"])
}

@Test func nilRecordingEndUsesNowAsTheEnd() {
    let events = [ev("running", at: 5), ev("later", at: 60)]
    let live = EventRanking.order(events, recordingStart: t0, recordingEnd: nil, now: t0 + 600)
    #expect(live.map(\.overlapsRecording) == [true, false])
    // Znany koniec wygrywa z `now`; wydarzenie zaczynające się dokładnie o końcu nagrania nie nakłada się.
    let done = EventRanking.order(events, recordingStart: t0, recordingEnd: t0 + 3600, now: t0 + 7200)
    #expect(done.map(\.overlapsRecording) == [true, false])
    let late = EventRanking.order(events, recordingStart: t0, recordingEnd: nil, now: t0 + 7200)
    #expect(late.map(\.overlapsRecording) == [true, true])
}

@Test func tiesAreBrokenByIDForStableOrder() {
    let a = ev("A", at: 15), b = ev("B", at: -15), c = ev("C", at: 15)
    let r1 = EventRanking.order([c, b, a], recordingStart: t0, recordingEnd: nil, now: t0)
    let r2 = EventRanking.order([a, c, b], recordingStart: t0, recordingEnd: nil, now: t0)
    #expect(titles(r1) == titles(r2))
    #expect(r1.map(\.event.id) == r1.map(\.event.id).sorted())
}
