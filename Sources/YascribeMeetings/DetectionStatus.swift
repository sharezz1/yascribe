/// Tekst stanu wykrywania w pasku menu: mówi tylko o tym, co faktycznie działa (Detect calls i/lub Apple Calendar).
public enum DetectionStatus {
    public enum CalendarProblem: Equatable, Sendable { case denied, selectionStale }

    public static func text(calls: Bool, calendar: Bool, problem: CalendarProblem?) -> String {
        guard calls || calendar else { return "Detection off" }
        if calendar, problem == .selectionStale { return "Selected calendars not found — re-select in Settings" }
        if calendar, problem == .denied { return calls ? "Detecting calls (calendar access off)" : "Detection off (calendar access off)" }
        switch (calls, calendar) {
        case (true, true): return "Detecting meetings"
        case (true, false): return "Detecting calls"
        default: return "Detecting calendar events"
        }
    }
}
