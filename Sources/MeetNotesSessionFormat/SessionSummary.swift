import Foundation

public enum SessionSummaryError: Error, Equatable {
    case missingSessionStart
}

/// Podsumowanie sesji — **pochodna** dziennika, odtwarzalna w każdej chwili.
public struct SessionSummary: Codable, Equatable, Sendable {
    public struct Gap: Codable, Equatable, Sendable {
        public var frameIndex: Int
        public var frames: Int
    }

    /// Okres wyciszenia toru w ramkach tego toru; `endFrame == nil` = do końca toru, którego długości nie znamy (awaria).
    public struct Mute: Codable, Equatable, Sendable {
        public var frameIndex: Int
        public var endFrame: Int?

        public init(frameIndex: Int, endFrame: Int? = nil) {
            self.frameIndex = frameIndex
            self.endFrame = endFrame
        }
    }

    public struct ClockAnchor: Codable, Equatable, Sendable {
        public var frameIndex: Int
        public var hostTime: UInt64
    }

    public struct Track: Codable, Equatable, Sendable {
        public var id: String
        public var sampleRate: Double
        public var channels: Int
        public var deviceUIDs: [String]
        public var firstSampleHostTime: UInt64?
        /// Przesunięcie pierwszej próbki względem osi sesji w sekundach.
        /// Oś taktuje ścieżka `system` (spec rdzenia §6).
        public var offsetSeconds: Double?
        /// `nil`, gdy ścieżka nie została zamknięta (awaria).
        public var frames: Int?
        public var gaps: [Gap]
        public var clock: [ClockAnchor]
        public var permissionDenied: String?
        public var failure: String?
        /// Rzeczywista częstotliwość z kotwic zegara — różni się od nominalnej
        /// o dryf zegara urządzenia.
        public var effectiveSampleRate: Double?
        /// Okresy wyciszenia z pigułki. Opcjonalne — stare `summary.json` go nie mają.
        public var mutes: [Mute]?
        /// Ramka pierwszych niezerowych próbek po `allZerosNs` (`track.audible`); `nil` = brak zdarzenia.
        public var audibleFrame: Int?

        public init(id: String, sampleRate: Double, channels: Int, deviceUIDs: [String] = [],
                    firstSampleHostTime: UInt64? = nil, offsetSeconds: Double? = nil, frames: Int? = nil,
                    gaps: [Gap] = [], clock: [ClockAnchor] = [], permissionDenied: String? = nil,
                    failure: String? = nil, effectiveSampleRate: Double? = nil) {
            self.id = id
            self.sampleRate = sampleRate
            self.channels = channels
            self.deviceUIDs = deviceUIDs
            self.firstSampleHostTime = firstSampleHostTime
            self.offsetSeconds = offsetSeconds
            self.frames = frames
            self.gaps = gaps
            self.clock = clock
            self.permissionDenied = permissionDenied
            self.failure = failure
            self.effectiveSampleRate = effectiveSampleRate
        }
    }

    public static let timelineTrackID = "system"

    public var startedHostTime: UInt64
    public var timebase: Timebase
    public var wallClock: Date?
    public var endReason: String?
    public var crashed: Bool
    public var tracks: [Track]

    public init(startedHostTime: UInt64, timebase: Timebase, wallClock: Date? = nil, endReason: String? = nil,
                crashed: Bool = false, tracks: [Track] = []) {
        self.startedHostTime = startedHostTime
        self.timebase = timebase
        self.wallClock = wallClock
        self.endReason = endReason
        self.crashed = crashed
        self.tracks = tracks
    }

    public static func rebuild(from events: [JournalEvent]) throws -> SessionSummary {
        guard let start = events.first, start.type == .sessionStarted, let timebase = start.timebase else {
            throw SessionSummaryError.missingSessionStart
        }
        var summary = SessionSummary(
            startedHostTime: start.hostTime, timebase: timebase, wallClock: start.wallClock,
            endReason: nil, crashed: true, tracks: [])
        var index: [String: Int] = [:]

        for e in events.dropFirst() {
            switch e.type {
            case .trackOpened:
                guard let id = e.trackID else { continue }
                index[id] = summary.tracks.count
                summary.tracks.append(Track(id: id, sampleRate: e.sampleRate ?? 0, channels: e.channels ?? 0,
                                            deviceUIDs: e.deviceUID.map { [$0] } ?? []))
            case .trackFirstSample:
                if let i = e.trackID.flatMap({ index[$0] }) {
                    summary.tracks[i].firstSampleHostTime = e.hostTime
                    summary.tracks[i].clock.append(ClockAnchor(frameIndex: 0, hostTime: e.hostTime))
                }
            case .trackClock:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex {
                    summary.tracks[i].clock.append(ClockAnchor(frameIndex: f, hostTime: e.hostTime))
                }
            case .deviceChanged:
                if let i = e.trackID.flatMap({ index[$0] }), let uid = e.deviceUID {
                    summary.tracks[i].deviceUIDs.append(uid)
                }
            case .trackGap:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex, let g = e.gapFrames {
                    summary.tracks[i].gaps.append(Gap(frameIndex: f, frames: g))
                }
            case .trackPermissionDenied:
                guard let id = e.trackID else { continue }
                if let i = index[id] {
                    summary.tracks[i].permissionDenied = e.permission
                } else {
                    index[id] = summary.tracks.count
                    summary.tracks.append(Track(id: id, sampleRate: 0, channels: 0, permissionDenied: e.permission))
                }
            case .trackFailed:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].failure = e.reason }
            case .trackRecovered:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].failure = nil }
            case .trackMuted:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex,
                   summary.tracks[i].mutes?.last.map({ $0.endFrame != nil }) ?? true {
                    summary.tracks[i].mutes = (summary.tracks[i].mutes ?? []) + [Mute(frameIndex: f)]
                }
            case .trackUnmuted:
                if let i = e.trackID.flatMap({ index[$0] }), let f = e.frameIndex, let last = summary.tracks[i].mutes?.indices.last,
                   summary.tracks[i].mutes?[last].endFrame == nil {
                    summary.tracks[i].mutes?[last].endFrame = f
                }
            case .trackAudible:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].audibleFrame = e.frameIndex }
            case .trackClosed:
                if let i = e.trackID.flatMap({ index[$0] }) { summary.tracks[i].frames = e.frames }
            case .sessionEnded:
                summary.endReason = e.reason
                summary.crashed = false
            case .sessionStarted:
                continue
            }
        }

        let anchor = summary.tracks.first(where: { $0.id == timelineTrackID })?.firstSampleHostTime
            ?? summary.startedHostTime
        for i in summary.tracks.indices {
            // Wyciszenie trwające przy Stop kończy się na ostatniej ramce toru; po awarii (tor niezamknięty) zostaje otwarte.
            if var m = summary.tracks[i].mutes, let last = m.indices.last, m[last].endFrame == nil {
                m[last].endFrame = summary.tracks[i].frames
                summary.tracks[i].mutes = m
            }
            if let first = summary.tracks[i].firstSampleHostTime {
                summary.tracks[i].offsetSeconds = timebase.secondsBetween(first, anchor)
            }
            let c = summary.tracks[i].clock
            if let a = c.first, let b = c.last, b.frameIndex > a.frameIndex {
                let secs = timebase.secondsBetween(b.hostTime, a.hostTime)
                if secs > 0 { summary.tracks[i].effectiveSampleRate = Double(b.frameIndex - a.frameIndex) / secs }
            }
        }
        return summary
    }

    /// Czas hosta ramki `frame` ścieżki `trackID`, liczony z kotwic zegara
    /// (interpolacja liniowa, poza ostatnią kotwicą — ekstrapolacja z ostatniego
    /// odcinka). To jest to, co naprawdę sprawdza T8.
    public func hostTime(track trackID: String, frame: Int) -> UInt64? {
        guard let t = tracks.first(where: { $0.id == trackID }), let first = t.clock.first else { return nil }
        let anchors = t.clock
        let rate: (ClockAnchor, ClockAnchor) -> Double = { a, b in
            Double(b.frameIndex - a.frameIndex) / timebase.secondsBetween(b.hostTime, a.hostTime)
        }
        var lower = first
        var upper: ClockAnchor?
        for a in anchors {
            if a.frameIndex <= frame { lower = a } else { upper = a; break }
        }
        let fps: Double
        if let u = upper, u.frameIndex > lower.frameIndex {
            fps = rate(lower, u)
        } else if anchors.count >= 2, let prev = anchors.dropLast().last, let last = anchors.last, last.frameIndex > prev.frameIndex {
            fps = rate(prev, last)
        } else {
            fps = t.sampleRate
        }
        guard fps > 0 else { return nil }
        let dt = Double(frame - lower.frameIndex) / fps
        return dt >= 0 ? lower.hostTime + timebase.ticks(seconds: dt) : lower.hostTime - timebase.ticks(seconds: -dt)
    }

    public func write(to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        try e.encode(self).write(to: url, options: .atomic)
    }
}
