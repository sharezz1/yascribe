import Foundation
import MeetNotesSessionFormat

/// Źródło z próbek w pamięci. Deterministyczne — bez niego nie ma powtarzalnych
/// testów, bo mikrofonu i głośników nie da się zaskryptować (spec rdzenia §4).
/// Emituje **synchronicznie** w `start`, porcja po porcji, z syntetycznym czasem hosta.
public final class FileSource: AudioSource, @unchecked Sendable {
    public let trackID: String
    private let samples: [Int16]
    private let format: TrackFormat
    private let startHostTime: UInt64
    private let timebase: Timebase
    private let chunkFrames: Int
    /// indeks ramki → dodatkowy skok czasu hosta w sekundach przed tą ramką
    private let jumps: [Int: Double]
    private let lock = NSLock()
    private var stopped = false

    public init(trackID: String, samples: [Int16], sampleRate: Double, channels: Int, deviceUID: String = "file",
                startHostTime: UInt64, timebase: Timebase, chunkFrames: Int = 1_024, jumps: [Int: Double] = [:]) {
        self.trackID = trackID
        self.samples = samples
        self.format = TrackFormat(sampleRate: sampleRate, channels: channels, deviceUID: deviceUID)
        self.startHostTime = startHostTime
        self.timebase = timebase
        self.chunkFrames = chunkFrames
        self.jumps = jumps
    }

    public func prepare() throws -> TrackFormat { format }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        let ch = format.channels
        let totalFrames = samples.count / ch
        var frame = 0
        var extra = 0.0
        while frame < totalFrames {
            lock.lock(); let s = stopped; lock.unlock()
            if s { return }
            let n = min(chunkFrames, totalFrames - frame)
            for (at, secs) in jumps where at >= frame && at < frame + n { extra += secs }
            let host = startHostTime + timebase.ticks(seconds: Double(frame) / format.sampleRate + extra)
            handler(.chunk(AudioChunk(samples: Array(samples[(frame * ch)..<((frame + n) * ch)]), hostTime: host)))
            frame += n
        }
        handler(.endOfStream)
    }

    public func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }
}
