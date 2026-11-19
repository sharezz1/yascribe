import Foundation

/// Nagłówek dnia na liście historii: „Today”, „Yesterday”, inaczej data (rok tylko dla innego roku niż bieżący).
public enum DictationDayLabel {
    public static func text(for day: Date, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(day, equalTo: now, toGranularity: .year) ? "EEEE MMM d" : "EEEE MMM d yyyy")
        return f.string(from: day)
    }
}
