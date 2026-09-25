import Foundation
import MeetNotesSessionFormat

/// Pisze **jedną** ścieżkę do **jednego** pliku. Nie ma dostępu do innych ścieżek,
/// więc miks jest tu strukturalnie niemożliwy (spec rdzenia §4, 🔴 rozdz. 18).
///
/// Luki: porównuje czas hosta **kolejnych** porcji. Skok ponad tolerancję
/// (przepięcie urządzenia, zgubione bufory) wypełnia ciszą i zapisuje w dzienniku.
/// Dryf zegara urządzenia nie wyzwala luk, bo nie kumuluje się między dwiema
/// sąsiednimi porcjami — pochłaniają go kotwice `track.clock`.
public final class TrackWriter {
    public let trackID: String
    public let format: TrackFormat
    private let caf: CAFWriter
    private let journal: SessionJournal
    private let timebase: Timebase
    private let gapTolerance: Double
    private let clockIntervalFrames: Int
    private var expectedNextHost: UInt64?
    private var lastClockFrame = 0

    public var framesWritten: Int { caf.framesWritten }

    public init(trackID: String, url: URL, format: TrackFormat, journal: SessionJournal, timebase: Timebase,
                gapToleranceSeconds: Double = 0.03, clockIntervalSeconds: Double = 10) throws {
        self.trackID = trackID
        self.format = format
        self.caf = try CAFWriter(url: url, sampleRate: format.sampleRate, channels: format.channels)
        self.journal = journal
        self.timebase = timebase
        self.gapTolerance = gapToleranceSeconds
        self.clockIntervalFrames = Int(clockIntervalSeconds * format.sampleRate)
    }

    public func write(_ chunk: AudioChunk) throws {
        let frames = chunk.samples.count / format.channels
        guard frames > 0 else { return }
        var anchorNow = false
        if let expected = expectedNextHost {
            let jump = timebase.secondsBetween(chunk.hostTime, expected)
            if jump > gapTolerance {
                let gapFrames = Int((jump * format.sampleRate).rounded())
                try journal.append(.trackGap(trackID, frameIndex: caf.framesWritten, gapFrames: gapFrames, hostTime: chunk.hostTime))
                try caf.appendSilence(frames: gapFrames)
                anchorNow = true
            }
        } else {
            try journal.append(.trackFirstSample(trackID, hostTime: chunk.hostTime))
            lastClockFrame = 0
        }
        let firstFrame = caf.framesWritten
        if anchorNow || firstFrame - lastClockFrame >= clockIntervalFrames {
            try journal.append(.trackClock(trackID, frameIndex: firstFrame, hostTime: chunk.hostTime))
            lastClockFrame = firstFrame
        }
        try caf.append(chunk.samples)
        expectedNextHost = chunk.hostTime + timebase.ticks(seconds: Double(frames) / format.sampleRate)
    }

    public func close(hostTime: UInt64) throws {
        // Błąd dziennika nie może zostawić otwartego, niezsynchronizowanego pliku (P9).
        do {
            try journal.append(.trackClosed(trackID, frames: caf.framesWritten, hostTime: hostTime))
        } catch {
            try? caf.close()
            throw error
        }
        try caf.close()
    }
}
