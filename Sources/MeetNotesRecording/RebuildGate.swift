import Foundation

enum RebuildDecision: Equatable {
    case now
    case deferred(until: Double)
}

/// Ogranicza tempo przebudów tapa. Słuchawki przełączają A2DP↔HFP w kółko, a każda zmiana częstotliwości
/// woła `rebuild()`. Bramka nigdy nie odrzuca: zawsze wyznacza termin, więc ostatni stan i tak zostanie zastosowany.
struct RebuildGate {
    private let minInterval: Double
    private let maxPerMinute: Int
    private var granted: [Double] = []

    init(minInterval: Double = 1.0, maxPerMinute: Int = 6) {
        self.minInterval = minInterval
        self.maxPerMinute = maxPerMinute
    }

    mutating func decide(now: Double) -> RebuildDecision {
        granted.removeAll { $0 <= now - 60 }
        if let last = granted.last, now - last < minInterval { return .deferred(until: last + minInterval) }
        if granted.count >= maxPerMinute, let oldest = granted.first { return .deferred(until: oldest + 60) }
        granted.append(now)
        return .now
    }
}
