import Foundation

/// Format ścieżki ustalany przed startem źródła: Int16, przeplatany.
public struct TrackFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var deviceUID: String

    public init(sampleRate: Double, channels: Int, deviceUID: String) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.deviceUID = deviceUID
    }
}

/// Porcja próbek w formacie ścieżki i czas hosta jej **pierwszej** próbki.
public struct AudioChunk: Sendable {
    public var samples: [Int16]
    public var hostTime: UInt64

    public init(samples: [Int16], hostTime: UInt64) {
        self.samples = samples
        self.hostTime = hostTime
    }
}

public enum AudioSourceEvent: Sendable {
    case chunk(AudioChunk)
    case deviceChanged(String)
    case failed(String)
    case endOfStream
}

public enum AudioSourceError: Error, Equatable {
    case permissionDenied(String)
    case deviceUnavailable(String)
    case coreAudio(String, Int32)
}

/// Jedno źródło = jedna ścieżka. Dwa kroki startu: `prepare()` ustala format
/// (żeby pisarz istniał, zanim przyjdzie pierwsza próbka), `start` zaczyna dostawy.
public protocol AudioSource: AnyObject, Sendable {
    var trackID: String { get }
    func prepare() throws -> TrackFormat
    func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws
    func stop()
}
