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
    private let trackStallSeconds: Double
    private var lastChunkByTrack: [String: UInt64] = [:]
    private var stalledTracks: Set<String> = []
    /// Tory z już zapisanym `track.failed` z innego powodu — nadzór ich nie
    /// nadpisuje swoim `stalled30s` (P2).
    private var failedTracks: Set<String> = []
    public private(set) var endReason: EndReason?
    private var levels: [String: Double] = [:]

    public var onEnded: (@Sendable (EndReason) -> Void)?

    /// Ostatni poziom (dBFS RMS) każdej ścieżki — dla wskaźnika na pigułce. Czyta pod tą samą blokadą co zapis.
    public func currentLevels() -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return levels
    }

    /// Sekundy od ostatniej głośnej porcji (ten sam próg i ten sam `lastLoudAt` co `SilenceCondition`) — dla pytania "Meeting ended?".
    public func silentSeconds() -> Double {
        let now = clock.now()
        lock.lock(); defer { lock.unlock() }
        return timebase.secondsBetween(now, lastLoudAt)
    }

    public init(directory: URL, sources: [any AudioSource], conditions: [any EndCondition] = .standard,
                clock: any HostClock = MachHostClock(), timebase: Timebase = .current,
                silenceThresholdDBFS: Double = -50, zeroWatch: [String: Double] = ["system": 60], trackStallSeconds: Double = 30) {
        self.directory = SessionDirectory(url: directory)
        self.sources = sources
        self.conditions = conditions
        self.clock = clock
        self.timebase = timebase
        self.silenceThreshold = silenceThresholdDBFS
        self.zeroWatch = zeroWatch
        self.trackStallSeconds = trackStallSeconds
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let journal = try SessionJournal(url: directory.journalURL)
        let now = clock.now()
        try journal.append(.sessionStarted(hostTime: now, timebase: timebase, wallClock: Date()))

        var ready: [(any AudioSource, TrackWriter, UInt64)] = []
        for source in sources {
            // trackID idzie do nazwy pliku — tylko bezpieczne znaki, nic poza katalogiem sesji (P12).
            guard Self.isSafeTrackID(source.trackID) else {
                try journal.append(.trackFailed(source.trackID, reason: "invalidTrackID", hostTime: clock.now()))
                continue
            }
            do {
                let fmt = try source.prepare()
                let writer = try TrackWriter(trackID: source.trackID, url: directory.trackURL(source.trackID),
                                             format: fmt, journal: journal, timebase: timebase)
                let opened = clock.now()
                try journal.append(.trackOpened(source.trackID, hostTime: opened, sampleRate: fmt.sampleRate,
                                                channels: fmt.channels, deviceUID: fmt.deviceUID))
                ready.append((source, writer, opened))
            } catch AudioSourceError.permissionDenied(let permission) {
                try journal.append(.trackPermissionDenied(source.trackID, permission: permission,
                                                          detection: "prepare", hostTime: clock.now()))
            } catch {
                try journal.append(.trackFailed(source.trackID, reason: "\(error)", hostTime: clock.now()))
            }
        }

        lock.lock()
        self.journal = journal
        for (s, w, opened) in ready {
            writers[s.trackID] = w
            lastChunkByTrack[s.trackID] = opened // 30 s liczone od otwarcia toru, nie od startu sesji (P7)
        }
        started = ready.map { $0.0 }
        startedAt = now
        lastLoudAt = now
        lastChunkAt = now
        lock.unlock()

        if ready.isEmpty {
            finish(.noSources)
            return
        }
        for (source, _, _) in ready {
            let id = source.trackID
            do {
                try source.start { [weak self] event in self?.handle(trackID: id, event) }
            } catch {
                // Jak .failed w handle(): insert tylko po udanym zapisie, bez ponowienia (P3).
                do {
                    try journal.append(.trackFailed(id, reason: "\(error)", hostTime: clock.now()))
                    lock.lock(); failedTracks.insert(id); lock.unlock()
                } catch {}
            }
        }
    }

    /// Przycisk „Stop".
    public func stop(reason: EndReason = .button) { finish(reason) }

    /// Warunki zależne od zegara ściennego (np. brak danych). W aplikacji co sekundę.
    public func tick() {
        let now = clock.now()
        lock.lock()
        var reason: EndReason?
        if !finishing, let journal { // bez dziennika sesja jeszcze nie ruszyła (Hermes 2.1)
            reason = evaluateLocked(now: now)
            // Każdy tor z osobna: martwy tor nie chowa się za żywym (ChatGPT #9).
            // ponytail: append (fsync) pod blokadą jak w handle(); ≤ 1 na tor na sesję.
            // Całość dziennika poza blokadą — osobne zadanie (P11).
            for s in started where !ended.contains(s.trackID) && !stalledTracks.contains(s.trackID)
                && !failedTracks.contains(s.trackID) {
                let last = lastChunkByTrack[s.trackID] ?? startedAt
                if timebase.secondsBetween(now, last) >= trackStallSeconds {
                    // Niezapisane zdarzenie = spróbuj przy następnym tick(), nie wyłączaj toru z nadzoru (P3).
                    do {
                        try journal.append(.trackFailed(s.trackID, reason: "stalled\(Int(trackStallSeconds))s", hostTime: now))
                        stalledTracks.insert(s.trackID)
                    } catch {}
                }
            }
        }
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
                    lastChunkByTrack[trackID] = chunk.hostTime
                    // Tor ożył — podsumowanie nie może dalej mówić „stalled" (P6). Tylko gdy stall był
                    // ostatnią awarią: późniejsza prawdziwa przyczyna zostaje w podsumowaniu (P2).
                    // Niezapisane zdarzenie = spróbuj przy następnej porcji (jak P3).
                    if stalledTracks.contains(trackID) && !failedTracks.contains(trackID) {
                        do {
                            try journal.append(.trackRecovered(trackID, hostTime: chunk.hostTime))
                            stalledTracks.remove(trackID)
                        } catch {}
                    }
                    let db = Levels.rmsDBFS(chunk.samples)
                    levels[trackID] = db
                    if db > silenceThreshold { lastLoudAt = max(lastLoudAt, chunk.hostTime) }
                    reason = evaluateLocked(now: chunk.hostTime)
                } catch {
                    reason = Self.isDiskFull(error) ? .diskFull : .writeError
                }
            case .deviceChanged(let uid):
                try? journal.append(.deviceChanged(trackID, deviceUID: uid, hostTime: clock.now()))
            case .failed(let why):
                // Zdarzenie jednorazowe, bez ponowienia. Insert tylko po udanym zapisie: inaczej
                // tor nie miałby w dzienniku żadnego track.failed — niech wtedy zapisze go nadzór (stalled).
                do {
                    try journal.append(.trackFailed(trackID, reason: why, hostTime: clock.now()))
                    failedTracks.insert(trackID)
                } catch {}
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
            zeroResolved.insert(trackID) // jednorazowo, bez ponowienia — jak .failed w handle()
            do {
                try journal.append(.trackFailed(trackID, reason: "allZeros\(Int(window))s", hostTime: chunk.hostTime))
                failedTracks.insert(trackID)
            } catch {}
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

    static func isSafeTrackID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func isDiskFull(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isDiskFull(u) }
        return false
    }
}
