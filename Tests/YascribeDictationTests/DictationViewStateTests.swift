import Foundation
import Testing
import YascribeProviders
@testable import YascribeDictation

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@Test func groupingLabelsTodayAndYesterday() {
    let now = date(2026, 11, 3, 9)
    #expect(DictationDayLabel.text(for: calendar.startOfDay(for: now), now: now, calendar: calendar) == "Today")
    #expect(DictationDayLabel.text(for: calendar.startOfDay(for: date(2026, 11, 2)), now: now, calendar: calendar) == "Yesterday")
    #expect(DictationDayLabel.text(for: calendar.startOfDay(for: date(2026, 10, 26)), now: now, calendar: calendar) == "Monday, Oct 26")
    #expect(DictationDayLabel.text(for: calendar.startOfDay(for: date(2025, 12, 31)), now: now, calendar: calendar) == "Wednesday, Dec 31, 2025")
}

@Test func rowNotes() {
    #expect(DictationPresentation.notes(for: DictationEntry(text: "a")).isEmpty)
    #expect(DictationPresentation.notes(for: DictationEntry(text: "a", correctionFailed: true)) == ["Correction failed — original text used"])
    #expect(DictationPresentation.notes(for: DictationEntry(text: "a", inserted: false)) == ["Copied only"])
    #expect(DictationPresentation.notes(for: DictationEntry(text: "a", correctionFailed: true, inserted: false)).count == 2)
    #expect(DictationPresentation.notes(for: DictationEntry(text: "a", correctionFailed: false, inserted: true)).isEmpty)
}

@Test func copyOriginalOnlyWhenDifferent() {
    #expect(!DictationPresentation.hasDistinctOriginal(DictationEntry(raw: "x", text: "x")))
    #expect(!DictationPresentation.hasDistinctOriginal(DictationEntry(raw: "", text: "x")))
    #expect(DictationPresentation.hasDistinctOriginal(DictationEntry(raw: "x y", text: "x, y")))
}

@Test func metaLineAndEmptyHint() {
    let e = DictationEntry(app: "Notes", asrModel: "a/model-1", correctionModel: "b/model-2")
    #expect(DictationPresentation.metaLine(e) { String($0.split(separator: "/").last!) } == "Notes · model-1 → model-2")
    #expect(DictationPresentation.metaLine(DictationEntry(), name: { $0 }) == "")
    #expect(DictationPresentation.emptyHint(hotkey: .fn, mode: .hold).hasPrefix("Hold Fn and speak"))
    #expect(DictationPresentation.emptyHint(hotkey: .fn, mode: .toggle).hasPrefix("Press Fn and speak"))
}
