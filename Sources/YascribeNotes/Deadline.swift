import Foundation

/// Model nie odpowiedział w wyznaczonym czasie.
public struct DeadlineExceeded: Error, CustomStringConvertible, Equatable, Sendable {
    public let seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
    public var description: String { "The model didn't answer within \(Int(seconds)) s." }
}

/// Całkowity limit czasu operacji. `URLRequest.timeoutInterval` mierzy bezczynność łącza, a nie czas całości: dostawca,
/// który trzyma połączenie (keep-alive) i odpowiada po kilkunastu minutach, nigdy by nie przekroczył 120 s — stąd „wisząca"
/// korekta z odbioru T13. Po przekroczeniu limitu operacja jest anulowana (anuluje też żądanie sieciowe).
public func withDeadline<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DeadlineExceeded(seconds: seconds)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw DeadlineExceeded(seconds: seconds) }
        return first
    }
}
