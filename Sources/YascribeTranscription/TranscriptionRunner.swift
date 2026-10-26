import Foundation
import YascribeProviders
import YascribeSessionFormat

public enum RunError: Error, Equatable {
    case badRunID(String)
    /// Ten sam runID, inne wejście (preset, bramka, limit okna, progi przesłuchu, ramki ścieżek) — ChatGPT #4.
    case inputMismatch
}

/// Wszystko, od czego zależą zapisane okna. Wznowienie tylko przy identycznym wejściu.
public struct RunInput: Codable, Equatable, Sendable {
    public var snapshot: RunSnapshot
    public var gate: EnergyGate.Config
    public var maxChunkSeconds: Double
    public var crosstalk: CrosstalkFilter
    public var trackFrames: [String: Int]
}

public struct TranscriptionProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
}

/// Katalog przebiegu: `<sesja>/runs/<runID>/`. Przebiegi leżą obok siebie (§8).
public struct RunDirectory: Sendable {
    public let url: URL
    public init(session: URL, runID: String) { url = session.appendingPathComponent("runs").appendingPathComponent(runID) }
    public var metadata: URL { url.appendingPathComponent("run.json") }
    public var transcript: URL { url.appendingPathComponent("transcript.json") }
    public var input: URL { url.appendingPathComponent("input.json") }

    /// Jeden bezpieczny komponent ścieżki: bez `/`, bez `..`, bez kropki na początku (ChatGPT #13).
    public static func isValid(runID: String) -> Bool {
        !runID.isEmpty && runID.count <= 64 && !runID.hasPrefix(".")
            && runID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    /// Najnowszy przebieg aplikacji: `runID` ma wzorzec `AppModel.sessionName` (`yyyy-MM-dd'T'HH-mm-ss'Z'-xxxx`), więc
    /// sortuje się chronologicznie. Decyduje o kasowaniu audio (`AudioRetention`), dlatego nazwy spoza wzorca
    /// (`--run debug` z CLI, `notes.txt`, `.DS_Store`) są pomijane — inaczej `debug` wygrywałby jako „najnowszy”.
    /// Katalogi obok `runs/` (jak `notes/`) tu nie wchodzą w ogóle.
    public static func latestRunID(in session: URL) -> String? { runIDs(in: session).last }

    /// Przebiegi aplikacji od najstarszego do najnowszego (ten sam filtr nazw co `latestRunID`).
    public static func runIDs(in session: URL) -> [String] {
        let runs = session.appendingPathComponent("runs")
        return ((try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? [])
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z-[0-9a-f]{4}$"#, options: .regularExpression) != nil }
            .sorted()
    }

    /// Identyfikator nowego przebiegu (F7): znacznik UTC do sekundy + sufiks, ściśle większy leksykalnie od najnowszego istniejącego
    /// (`latest`, z dysku — także po restarcie i przy cofniętym zegarze). Sekunda = max(teraz, najnowszy + 1 s), więc o kolejności
    /// dwóch prób z tej samej sekundy nie decyduje losowy sufiks.
    public static func nextRunID(latest: String?, now: Date, suffix: String = String(UUID().uuidString.prefix(4)).lowercased()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        var stamp = f.string(from: now)
        if let last = latest.map({ String($0.prefix(stamp.count)) }), stamp <= last, let date = f.date(from: last) {
            stamp = f.string(from: date + 1)
        }
        return stamp + "-" + suffix
    }

    public func chunk(_ track: String, _ i: Int) -> URL { url.appendingPathComponent("chunks/\(track)-\(i).json") }
}

/// Potok: ścieżka → 16 kHz mono → bramka → pakowanie → okna do ASR → scalenie.
/// Wznawialny: gotowe okna leżą na dysku i nie są wysyłane ponownie (P5).
/// Nieudane okno nie przerywa przebiegu — zostaje jawną luką (§6.4).
public struct TranscriptionRunner: Sendable {
    public let session: SessionDirectory
    public let runID: String
    public let snapshot: RunSnapshot
    /// OpenAI-compatible albo ElevenLabs — wybór po `Provider.api` u wołającego.
    public let client: any TranscriptionClient
    public let maxChunkSeconds: Double
    public let gate: EnergyGate
    public let crosstalk: CrosstalkFilter

    public init(session: URL, runID: String, snapshot: RunSnapshot, client: any TranscriptionClient,
                maxChunkSeconds: Double = 59, gate: EnergyGate = EnergyGate(), crosstalk: CrosstalkFilter = CrosstalkFilter()) {
        self.session = SessionDirectory(url: session)
        self.runID = runID
        self.snapshot = snapshot
        self.client = client
        self.maxChunkSeconds = maxChunkSeconds
        self.gate = gate
        self.crosstalk = crosstalk
    }

    /// „Oni" = ścieżka systemowa; „ja" = mikrofon po AEC, a gdy go brak albo gdy jego ścieżka
    /// zanotowała awarię (`trackFailed`, E3) — surowy `mic_raw`.
    static func tracks(in summary: SessionSummary) -> [(id: String, speaker: Speaker)] {
        let ids = Set(summary.tracks.filter { $0.channels > 0 }.map(\.id))
        var out: [(String, Speaker)] = []
        if ids.contains("system") { out.append(("system", .them)) }
        let aecFailed = summary.tracks.first { $0.id == "mic_aec" }?.failure != nil // Hermes 4.2
        if ids.contains("mic_aec") && !aecFailed { out.append(("mic_aec", .me)) }
        else if ids.contains("mic_raw") { out.append(("mic_raw", .me)) }
        return out
    }

    public func run(progress: @Sendable (TranscriptionProgress) -> Void = { _ in }) async throws -> Transcript {
        guard RunDirectory.isValid(runID: runID) else { throw RunError.badRunID(runID) }
        let summary = try session.summarize()
        let dir = RunDirectory(session: session.url, runID: runID)
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        let input = RunInput(snapshot: snapshot, gate: gate.config, maxChunkSeconds: maxChunkSeconds, crosstalk: crosstalk,
                             trackFrames: Dictionary(summary.tracks.map { ($0.id, $0.frames ?? -1) }, uniquingKeysWith: { a, _ in a }))
        if let saved = try JSONFile.load(RunInput?.self, from: dir.input, default: nil) {
            guard saved == input else { throw RunError.inputMismatch }
        } else {
            try JSONFile.save(input, to: dir.input)
        }
        let clock = SessionClock(summary: summary)
        let started = Date()

        var plan: [(track: String, chunk: Chunk, samples: [Float])] = []
        var speakers: [String: Speaker] = [:]
        var systemX: [Float]?
        for (id, speaker) in Self.tracks(in: summary) { // `tracks(in:)` zwraca `system` pierwszy
            speakers[id] = speaker
            let caf = try CAFReader(url: session.trackURL(id))
            let x = try Resampler.toASR(caf.samples, sampleRate: caf.sampleRate, channels: caf.channels)
            var regions = gate.speechRegions(x, rate: Resampler.asrRate)
            if speaker == .me, let sys = systemX {
                let offset = summary.tracks.first { $0.id == id }?.offsetSeconds ?? 0
                regions = crosstalk.keep(regions, mic: x, system: sys, micOffsetSeconds: offset)
            }
            if id == "system" { systemX = x }
            let chunks = ChunkPacker(maxSeconds: maxChunkSeconds).pack(regions, samples: x)
            for c in chunks { plan.append((id, c, x)) }
        }

        var results: [ChunkResult] = []
        var failures: [ChunkFailure] = []
        var requests = 0
        var secondsSent = 0.0
        progress(TranscriptionProgress(done: 0, total: plan.count))
        for (n, item) in plan.enumerated() {
            let file = dir.chunk(item.track, item.chunk.index)
            if let saved = try? JSONFile.load(ChunkResult?.self, from: file, default: nil), saved.chunk == item.chunk {
                results.append(saved)
            } else {
                do {
                    requests += 1
                    secondsSent += Double(item.chunk.length) / Resampler.asrRate
                    let r = try await client.transcribe(wav: WAVEncoder.encode(item.chunk, samples: item.samples),
                                                        model: snapshot.model, language: snapshot.language, shape: snapshot.shape)
                    let cr = ChunkResult(track: item.track, chunk: item.chunk, result: r)
                    try JSONFile.save(cr, to: file)
                    results.append(cr)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append(ChunkFailure(
                        track: item.track, index: item.chunk.index,
                        start: clock.sessionSeconds(track: item.track, trackSeconds: item.chunk.sourceStartSeconds),
                        end: clock.sessionSeconds(track: item.track, trackSeconds: item.chunk.sourceEndSeconds),
                        error: "\(error)"))
                }
            }
            try Task.checkCancellation()
            progress(TranscriptionProgress(done: n + 1, total: plan.count))
        }

        let transcript = Merger.merge(results, speakers: speakers, clock: clock,
                                      language: snapshot.language, failures: failures)
        try JSONFile.save(transcript, to: dir.transcript)
        try JSONFile.save(RunMetadata(runID: runID, snapshot: snapshot, startedAt: started, finishedAt: Date(),
                                      chunkCount: plan.count, requestCount: requests, audioSecondsSent: secondsSent,
                                      failedChunkCount: failures.count, languageFlagCount: transcript.languageFlagCount),
                          to: dir.metadata)
        return transcript
    }
}
