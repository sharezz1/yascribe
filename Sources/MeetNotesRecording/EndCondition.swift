import Foundation
import MeetNotesSessionFormat

/// Powód zakończenia sesji, zapisywany w `session.ended.reason`.
public enum EndReason: String, Codable, Sendable {
    case button
    case silence
    case hardLimit
    case sourceStalled
    case endOfInput
    case diskFull
    case writeError
    case noSources
}

/// Stan widziany przez warunki końca. Czas w tikach hosta.
public struct RecorderState: Sendable {
    public var now: UInt64
    public var startedAt: UInt64
    public var lastLoudAt: UInt64
    public var lastChunkAt: UInt64
    public var timebase: Timebase
}

/// 🔴 Koniec sesji musi mieć warunek mechaniczny (W§1). Lista warunków zamiast
/// jednego `if`, żeby kalendarz dało się dołożyć bez dotykania rdzenia.
public protocol EndCondition: Sendable {
    func check(_ state: RecorderState) -> EndReason?
}

/// Cisza na **wszystkich** ścieżkach dłużej niż `seconds`.
public struct SilenceCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.lastLoudAt) >= seconds ? .silence : nil
    }
}

public struct HardLimitCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.startedAt) >= seconds ? .hardLimit : nil
    }
}

/// Żadne źródło nie dostarczyło porcji od `seconds`.
public struct StallCondition: EndCondition {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public func check(_ s: RecorderState) -> EndReason? {
        s.timebase.secondsBetween(s.now, s.lastChunkAt) >= seconds ? .sourceStalled : nil
    }
}

public extension Array where Element == any EndCondition {
    /// Domyślny zestaw z speców: 10 min ciszy, 4 h twardego limitu, 30 s bez danych.
    static var standard: [any EndCondition] {
        [SilenceCondition(seconds: 600), HardLimitCondition(seconds: 4 * 3600), StallCondition(seconds: 30)]
    }
}
