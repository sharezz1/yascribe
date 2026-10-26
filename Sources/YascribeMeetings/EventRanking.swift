import Foundation

public struct Ranked: Equatable, Sendable {
    public var event: CalendarEventInfo
    public var overlapsRecording: Bool
}

/// Lista ręcznego wyboru wydarzenia (spec §4.7): bliskość początku wydarzenia do początku nagrania.
public enum EventRanking {
    /// `recordingEnd == nil` = nagranie w toku, koniec to `now`. Remis odległości rozstrzyga `id` (stabilna kolejność).
    public static func order(_ events: [CalendarEventInfo], recordingStart: Date, recordingEnd: Date?, now: Date) -> [Ranked] {
        let end = recordingEnd ?? now
        return events.filter(EventFilter.isPickable)
            .sorted {
                let (a, b) = (abs($0.start.timeIntervalSince(recordingStart)), abs($1.start.timeIntervalSince(recordingStart)))
                return a != b ? a < b : $0.id < $1.id
            }
            .map { Ranked(event: $0, overlapsRecording: $0.start < end && $0.end > recordingStart) }
    }
}
