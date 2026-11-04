import Foundation

public enum LauncherStatus: Equatable, Sendable {
    case listening, processing, inserted, copied, error(String)
}

/// Co pokazuje pastylka; `nil` z `presentation` = ukryta.
public enum LauncherPresentation: Equatable, Sendable {
    case dot, expanded, status(LauncherStatus)
}

/// Stan pastylki bez AppKit: hover z czasem zjechania i reguła widoczności.
public struct LauncherState: Equatable, Sendable {
    /// Krótkie zjechanie kursora (np. przy zmianie rozmiaru okna) nie zwija pigułki.
    public static let collapseDelay: TimeInterval = 0.4

    private var hovering = false
    private var leftAt: TimeInterval?

    public init() {}

    /// Panel znika bez zdarzenia „kursor wyszedł": zerujemy hover, inaczej zostaje „wciśnięty" na zawsze.
    public mutating func reset() {
        hovering = false
        leftAt = nil
    }

    public mutating func hoverChanged(_ inside: Bool, at time: TimeInterval) {
        if !inside, hovering { leftAt = time }
        hovering = inside
    }

    /// Zapisywane X (środek dolnej krawędzi) wsunięte w poziomy zakres głównego ekranu.
    public static func originX(_ x: Double, minX: Double, maxX: Double) -> Double { min(max(x, minX), maxX) }

    /// Status wygrywa z hoverem w każdej fazie poza `idle` (inaczej „Retry” po błędzie byłby nieosiągalny).
    public func presentation(phase: DictationPhase, meetingRecording: Bool, now: TimeInterval) -> LauncherPresentation? {
        // Dyktowanie i nagrywanie spotkania się wykluczają: w trakcie spotkania jest pigułka nagrania.
        if meetingRecording { return nil }
        switch phase {
        case .idle:
            if hovering { return .expanded }
            if let leftAt, now - leftAt < Self.collapseDelay { return .expanded }
            return .dot
        case .listening: return .status(.listening)
        case .processing: return .status(.processing)
        case .finished(.inserted): return .status(.inserted)
        case .finished(.copiedOnly): return .status(.copied)
        case .finished(.blocked(let reason)): return .status(.error(reason))
        case .failed(let message), .refused(let message): return .status(.error(message))
        }
    }
}
