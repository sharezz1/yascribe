import Foundation

/// Źródło czasu hosta. W aplikacji `mach_absolute_time`, w testach sterowany ręcznie.
public protocol HostClock: Sendable {
    func now() -> UInt64
}

public struct MachHostClock: HostClock {
    public init() {}
    public func now() -> UInt64 { mach_absolute_time() }
}

public final class ManualHostClock: HostClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    public init(_ start: UInt64 = 0) { value = start }

    public func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ v: UInt64) {
        lock.lock(); value = v; lock.unlock()
    }
}
