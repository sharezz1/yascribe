import Foundation

/// Jedna pula w LocalASRSupport. Parakeet może współdzielić RAM; Cohere wymaga wyłączności.
public final class LocalASRReservations: @unchecked Sendable { // Wszystkie zmiany właścicieli pod NSLock.
    private let lock = NSLock()
    private var owners: [UUID: LocalASRModel] = [:]

    public init() {}
    public var isIdle: Bool { lock.withLock { owners.isEmpty } }

    public func acquire(model: LocalASRModel) throws -> LocalASRReservation {
        try lock.withLock {
            guard owners.isEmpty || (model != .cohereTranscribe6bit && !owners.values.contains(.cohereTranscribe6bit)) else {
                throw RunGateRefusal(message: "On-device speech recognition is in use by another transcription, probe or dictation. Try again when it finishes.", canDownload: false)
            }
            let id = UUID()
            owners[id] = model
            return LocalASRReservation { [self] in lock.withLock { _ = owners.removeValue(forKey: id) } }
        }
    }
}

public final class LocalASRReservation: Sendable {
    private let finish: @Sendable () -> Void
    fileprivate init(finish: @escaping @Sendable () -> Void) { self.finish = finish }
    deinit { finish() }
}
