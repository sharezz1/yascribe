/// Ile przebiegów (spotkanie, dyktowanie, sonda) trzyma teraz lokalny model. Każdy `begin()` ma swój `end()` w tym samym
/// zakresie; usunięcie modelu i zgaszenie „Preparing…” tylko przy zerze (jeden przebieg nie gasi drugiego).
public struct ModelRunCount: Equatable, Sendable {
    public private(set) var count = 0

    public init() {}

    public mutating func begin() { count += 1 }

    public mutating func end() { count = max(0, count - 1) }

    public var isIdle: Bool { count == 0 }
}
