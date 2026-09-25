import Foundation
import MeetNotesSessionFormat

/// Spina źródła, pisarzy, dziennik i warunki końca. Jedyny moduł widzący całość
/// (spec rdzenia §4). Nie wie nic o ASR.
///
/// Współbieżność: porcje przychodzą z kolejek źródeł; cały stan chroni jeden
/// `NSLock`. Źródeł nie zatrzymujemy pod blokadą — `AudioDeviceStop` czeka na
/// trwające wywołanie IOProc, które może właśnie czekać na tę blokadę.
public final class SessionRecorder: @unchecked Sendable {
    public let directory: SessionDirectory
    private let sources: [any AudioSource]
    private let conditions: [any EndCondition]
    private let clock: any HostClock
    private let timebase: Timebase
    private let silenceThreshold: Double
    private let zeroWatch: [String: Double]
    private let lock = NSLock()

    private var journal: SessionJournal?
    private var writers: [String: TrackWriter] = [:]
    private var started: [any AudioSource] = []
    private var ended: Set<String> = []
    private var startedAt: UInt64 = 0
    private var lastLoudAt: UInt64 = 0
    private var lastChunkAt: UInt64 = 0
    private var finishing = false
    private var zeroFirstChunk: [String: UInt64] = [:]
    private var zeroResolved: Set<String> = []
    public private(set) var endReason: EndReason?

    public var onEnded: (@Sendable (EndReason) -> Void)?

    public init(directory: URL, sources: [any AudioSource], conditions: [any EndCondition] = .standard,
                clock: any HostClock = MachHostClock(), timebase: Timebase = .current,
                silenceThresholdDBFS: Double = -50, zeroWatch: [String: Double] = ["system": 60]) {
        self.directory = SessionDirectory(url: directory)
        self.sources = sources
        self.conditions = conditions
        self.clock = clock
        self.timebase = timebase
        self.silenceThreshold = silenceThresholdDBFS
        self.zeroWatch = zeroWatch
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let journal = try SessionJournal(url: directory.journalURL)
        let now = clock.now()
        try journal.append(.sessionStarted(hostTime: now, timebase: timebase, wallClock: Date()))

        var ready: [(any AudioSource, TrackWriter)] = []
        for source in sources {
            do {
                let fmt = try source.prepare()
                let writer = try TrackWriter(trackID: source.trackID, url: directory.trackURL(source.trackID),
                                             format: fmt, journal: journal, timebase: timebase)
                try journal.append(.trackOpened(source.trackID, hostTime: clock.now(), sampleRate: fmt.sampleRate,
                                                channels: fmt.channels, deviceUID: fmt.deviceUID))
                ready.append((source, writer))
            } catch AudioSourceError.permissionDenied(let permission) {
                try journal.append(.trackPermissionDenied(source.trackID, permission: permission,
                                                          detection: "prepare", hostTime: clock.now()))
            } catch {
                try journal.append(.trackFailed(source.trackID, reason: "\(error)", hostTime: clock.now()))
            }
        }

        lock.lock()
        self.journal = journal
        for (s, w) in ready { writers[s.trackID] = w }
        started = ready.map { $0.0 }
        startedAt = now
        lastLoudAt = now
        lastChunkAt = now
        lock.unlock()

        if ready.isEmpty {
            finish(.noSources)
            return
        }
        for (source, _) in ready {
            let id = source.trackID
            do {
                try source.start { [weak self] event in self?.handle(trackID: id, event) }
            } catch {
                try? journal.append(.trackFailed(id, reason: "\(error)", hostTime: clock.now()))
            }
        }
    }

    /// Przycisk „Stop".
    public func stop(reason: EndReason = .button) { finish(reason) }

    /// Warunki zależne od zegara ściennego (np. brak danych). W aplikacji co sekundę.
    public func tick() {
        let now = clock.now()
        lock.lock()
        let reason = finishing ? nil : evaluateLocked(now: now)
        lock.unlock()
        if let reason { finish(reason) }
    }

    private func handle(trackID: String, _ event: AudioSourceEvent) {
        var reason: EndReason?
        lock.lock()
        if !finishing, let journal {
            switch event {
            case .chunk(let chunk):
                do {
                    try writers[trackID]?.write(chunk)
                    watchZerosLocked(trackID: trackID, chunk: chunk, journal: journal)
                    lastChunkAt = max(lastChunkAt, chunk.hostTime)
                    if Levels.rmsDBFS(chunk.samples) > silenceThreshold { lastLoudAt = max(lastLoudAt, chunk.hostTime) }
                    reason = evaluateLocked(now: chunk.hostTime)
                } catch {
                    reason = Self.isDiskFull(error) ? .diskFull : .writeError
                }
            case .deviceChanged(let uid):
                try? journal.append(.deviceChanged(trackID, deviceUID: uid, hostTime: clock.now()))
            case .failed(let why):
                try? journal.append(.trackFailed(trackID, reason: why, hostTime: clock.now()))
            case .endOfStream:
                ended.insert(trackID)
                if ended.count == started.count { reason = .endOfInput }
            }
        }
        lock.unlock()
        if let reason { finish(reason) }
    }

    /// T9: ścieżka złożona z samych zer cyfrowych przez `zeroWatch[trackID]`
    /// sekund to najpewniej odmowa uprawnienia, a nie cisza — zapisujemy to jawnie,
    /// zamiast oddać „nagranie" pełne zer. Sesji nie przerywamy: prawdziwa cisza
    /// na starcie spotkania też się zdarza.
    private func watchZerosLocked(trackID: String, chunk: AudioChunk, journal: SessionJournal) {
        guard let window = zeroWatch[trackID], !zeroResolved.contains(trackID) else { return }
        if chunk.samples.contains(where: { $0 != 0 }) {
            zeroResolved.insert(trackID)
            return
        }
        let first = zeroFirstChunk[trackID] ?? chunk.hostTime
        zeroFirstChunk[trackID] = first
        if timebase.secondsBetween(chunk.hostTime, first) >= window {
            try? journal.append(.trackFailed(trackID, reason: "allZeros\(Int(window))s", hostTime: chunk.hostTime))
            zeroResolved.insert(trackID)
        }
    }

    private func evaluateLocked(now: UInt64) -> EndReason? {
        let state = RecorderState(now: now, startedAt: startedAt, lastLoudAt: lastLoudAt,
                                  lastChunkAt: lastChunkAt, timebase: timebase)
        for c in conditions { if let r = c.check(state) { return r } }
        return nil
    }

    private func finish(_ reason: EndReason) {
        lock.lock()
        if finishing { lock.unlock(); return }
        finishing = true
        endReason = reason
        let toStop = started
        lock.unlock()

        for s in toStop { s.stop() } // bez blokady — patrz komentarz klasy

        lock.lock()
        let now = clock.now()
        for w in writers.values { try? w.close(hostTime: now) }
        try? journal?.append(.sessionEnded(reason: reason.rawValue, hostTime: now))
        _ = try? directory.rebuildSummaryFile()
        try? journal?.close()
        lock.unlock()
        onEnded?(reason)
    }

    static func isDiskFull(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isDiskFull(u) }
        return false
    }
}
