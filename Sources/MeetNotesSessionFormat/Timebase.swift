import Foundation

/// Przelicznik tików `mach_absolute_time` na sekundy. Zapisywany w dzienniku,
/// żeby sesję dało się wyrównać na innej maszynie albo po restarcie.
public struct Timebase: Codable, Equatable, Sendable {
    public var numer: UInt32
    public var denom: UInt32

    public init(numer: UInt32, denom: UInt32) {
        self.numer = numer
        self.denom = denom
    }

    public static var current: Timebase {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numer: info.numer, denom: info.denom)
    }

    public func seconds(ticks: UInt64) -> Double {
        Double(ticks) * Double(numer) / Double(denom) / 1_000_000_000
    }

    public func ticks(seconds: Double) -> UInt64 {
        UInt64((seconds * 1_000_000_000 * Double(denom) / Double(numer)).rounded())
    }

    /// Różnica `a - b` w sekundach, ze znakiem.
    public func secondsBetween(_ a: UInt64, _ b: UInt64) -> Double {
        a >= b ? seconds(ticks: a - b) : -seconds(ticks: b - a)
    }
}
