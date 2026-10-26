import Foundation

/// Ogranicza częstość publikacji postępu: FluidAudio wysyła ok. 7,5 tys. zdarzeń na pobranie, a UI nie potrzebuje więcej niż ~10/s.
/// Wołane z dowolnego wątku (zdarzenia przychodzą współbieżnie).
public final class ProgressThrottle: @unchecked Sendable {
    private let minInterval: TimeInterval
    private let lock = NSLock()
    private var last: Date?

    public init(minInterval: TimeInterval = 0.1) { self.minInterval = minInterval }

    /// `true` = opublikuj to zdarzenie; pierwsze zawsze przechodzi.
    public func admit(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last, now.timeIntervalSince(last) < minInterval { return false }
        last = now
        return true
    }
}
