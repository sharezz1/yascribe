import Foundation

/// Jedno zdarzenie dziennika sesji. Płaska struktura z polami opcjonalnymi:
/// prosta w kodowaniu i odporna na dopisywanie nowych pól.
public struct JournalEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStarted = "session.started"
        case trackOpened = "track.opened"
        case trackFirstSample = "track.firstSample"
        case trackClock = "track.clock"
        case deviceChanged = "device.changed"
        case trackGap = "track.gap"
        case trackPermissionDenied = "track.permissionDenied"
        case trackFailed = "track.failed"
        case trackClosed = "track.closed"
        case sessionEnded = "session.ended"
    }

    public var type: Kind
    public var hostTime: UInt64
    public var trackID: String?
    public var sampleRate: Double?
    public var channels: Int?
    public var deviceUID: String?
    public var sampleFormat: String?
    public var frameIndex: Int?
    public var gapFrames: Int?
    public var frames: Int?
    public var permission: String?
    public var detection: String?
    public var reason: String?
    public var timebase: Timebase?
    public var wallClock: Date?

    public init(type: Kind, hostTime: UInt64) {
        self.type = type
        self.hostTime = hostTime
    }
}

public extension JournalEvent {
    static func sessionStarted(hostTime: UInt64, timebase: Timebase, wallClock: Date) -> JournalEvent {
        var e = JournalEvent(type: .sessionStarted, hostTime: hostTime)
        e.timebase = timebase
        e.wallClock = wallClock
        return e
    }

    static func trackOpened(_ trackID: String, hostTime: UInt64, sampleRate: Double, channels: Int, deviceUID: String) -> JournalEvent {
        var e = JournalEvent(type: .trackOpened, hostTime: hostTime)
        e.trackID = trackID
        e.sampleRate = sampleRate
        e.channels = channels
        e.deviceUID = deviceUID
        e.sampleFormat = "int16"
        return e
    }

    static func trackFirstSample(_ trackID: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackFirstSample, hostTime: hostTime)
        e.trackID = trackID
        return e
    }

    static func trackClock(_ trackID: String, frameIndex: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackClock, hostTime: hostTime)
        e.trackID = trackID
        e.frameIndex = frameIndex
        return e
    }

    static func deviceChanged(_ trackID: String, deviceUID: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .deviceChanged, hostTime: hostTime)
        e.trackID = trackID
        e.deviceUID = deviceUID
        return e
    }

    static func trackGap(_ trackID: String, frameIndex: Int, gapFrames: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackGap, hostTime: hostTime)
        e.trackID = trackID
        e.frameIndex = frameIndex
        e.gapFrames = gapFrames
        return e
    }

    static func trackPermissionDenied(_ trackID: String, permission: String, detection: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackPermissionDenied, hostTime: hostTime)
        e.trackID = trackID
        e.permission = permission
        e.detection = detection
        return e
    }

    static func trackFailed(_ trackID: String, reason: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackFailed, hostTime: hostTime)
        e.trackID = trackID
        e.reason = reason
        return e
    }

    static func trackClosed(_ trackID: String, frames: Int, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .trackClosed, hostTime: hostTime)
        e.trackID = trackID
        e.frames = frames
        return e
    }

    static func sessionEnded(reason: String, hostTime: UInt64) -> JournalEvent {
        var e = JournalEvent(type: .sessionEnded, hostTime: hostTime)
        e.reason = reason
        return e
    }
}
