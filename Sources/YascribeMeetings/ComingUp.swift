import Foundation

/// „Coming up” na stronie głównej (macos.md §11.5, wariant B): najbliższe spotkanie i reszta dnia. Czysta logika, czas wstrzykiwany.
public struct ComingUp: Equatable, Sendable {
    /// Karta: wydarzenie, które zaczyna się w ciągu `window` albo właśnie trwa.
    public var next: CalendarEventInfo?
    /// „Later today”: jeszcze niezaczęte wydarzenia do końca dnia `now`, bez `next`, po godzinie startu.
    public var later: [CalendarEventInfo]

    /// Karta pojawia się 60 min przed startem (włącznie).
    public static let window: TimeInterval = 3600

    /// Lista jak w ręcznym wyborze 1.6 (`isPickable`: bez całodniowych i OOO), do tego bez anulowanych i odrzuconych
    /// (spec 1.6 decyzja 10: „bez odrzuconych"). Brak linku nie wyklucza (decyzja 11).
    public static func isListed(_ e: CalendarEventInfo) -> Bool {
        EventFilter.isPickable(e) && !e.isCanceled && e.myStatus != .declined
    }

    /// Przy kilku kandydatach karta bierze najbliższy start (przeszły albo przyszły), remis po `id` — jak `OfferDetector`,
    /// więc karta i pigułka wskazują to samo wydarzenie. Wydarzenia z kolejnego dnia nie wchodzą (także po 23:00).
    public static func of(_ events: [CalendarEventInfo], now: Date, calendar: Calendar = .current) -> ComingUp {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let today = events.filter { isListed($0) && $0.end > now && $0.start < dayEnd }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
        let next = today.filter { $0.start <= now + window }.min {
            let (a, b) = (abs($0.start.timeIntervalSince(now)), abs($1.start.timeIntervalSince(now)))
            return a != b ? a < b : $0.id < $1.id
        }
        return ComingUp(next: next, later: today.filter { $0.start > now && $0.id != next?.id })
    }

    /// Nazwa aplikacji z linku do spotkania; `nil` = brak linku („In person”).
    public static func appName(_ e: CalendarEventInfo, tuning: MeetingTuning = MeetingTuning()) -> String? {
        guard let url = EventFilter.meetingURL(in: e, patterns: tuning.linkPatterns) else { return nil }
        let host = url.host?.lowercased() ?? ""
        if host.contains("teams.") { return "Teams" }
        if host.contains("meet.google.") { return "Google Meet" }
        if host.contains("zoom.us") { return "Zoom" }
        return host.isEmpty ? "Online" : host
    }

    /// „Next · in 8 min” (w górę: zostało 7,5 min → 8) albo „Now · started 5 min ago” dla trwającego.
    public static func timing(_ e: CalendarEventInfo, now: Date) -> String {
        let s = e.start.timeIntervalSince(now)
        if s > 0 { return "Next · in \(Int((s / 60).rounded(.up))) min" }
        let ago = Int(-s / 60)
        return ago < 1 ? "Now · starting" : "Now · started \(ago) min ago"
    }
}
