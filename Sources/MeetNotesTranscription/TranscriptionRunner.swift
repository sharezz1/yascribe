import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat

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
    public func chunk(_ track: String, _ i: Int) -> URL { url.appendingPathComponent("chunks/\(track)-\(i).json") }
}

/// Potok: ścieżka → 16 kHz mono → bramka → pakowanie → okna do ASR → scalenie.
/// Wznawialny: gotowe okna leżą na dysku i nie są wysyłane ponownie (P5).
/// Nieudane okno nie przerywa przebiegu — zostaje jawną luką (§6.4).
public struct TranscriptionRunner: Sendable {
    public let session: SessionDirectory
    public let runID: String
    public let snapshot: RunSnapshot
    public let client: OpenAICompatibleClient
    public let maxChunkSeconds: Double
    public let gate: EnergyGate

    public init(session: URL, runID: String, snapshot: RunSnapshot, client: OpenAICompatibleClient,
                maxChunkSeconds: Double = 59, gate: EnergyGate = EnergyGate()) {
        self.session = SessionDirectory(url: session)
        self.runID = runID
        self.snapshot = snapshot
        self.client = client
        self.maxChunkSeconds = maxChunkSeconds
        self.gate = gate
    }

    /// „Oni" = ścieżka systemowa; „ja" = mikrofon po AEC, a gdy go brak — surowy.
    static func tracks(in summary: SessionSummary) -> [(id: String, speaker: Speaker)] {
        let ids = Set(summary.tracks.filter { $0.channels > 0 }.map(\.id))
        var out: [(String, Speaker)] = []
        if ids.contains("system") { out.append(("system", .them)) }
        if ids.contains("mic_aec") { out.append(("mic_aec", .me)) } else if ids.contains("mic_raw") { out.append(("mic_raw", .me)) }
        return out
    }

    public func run(progress: @Sendable (TranscriptionProgress) -> Void = { _ in }) async throws -> Transcript {
        let summary = try session.summarize()
        let dir = RunDirectory(session: session.url, runID: runID)
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        let started = Date()

        var plan: [(track: String, chunk: Chunk, samples: [Float])] = []
        var speakers: [String: Speaker] = [:]
        for (id, speaker) in Self.tracks(in: summary) {
            speakers[id] = speaker
            let caf = try CAFReader(url: session.trackURL(id))
            let x = try Resampler.toASR(caf.samples, sampleRate: caf.sampleRate, channels: caf.channels)
            let chunks = ChunkPacker(maxSeconds: maxChunkSeconds).pack(gate.speechRegions(x, rate: Resampler.asrRate), samples: x)
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
                    failures.append(ChunkFailure(track: item.track, index: item.chunk.index, start: item.chunk.sourceStartSeconds,
                                                 end: item.chunk.sourceEndSeconds, error: "\(error)"))
                }
            }
            try Task.checkCancellation()
            progress(TranscriptionProgress(done: n + 1, total: plan.count))
        }

        let transcript = Merger.merge(results, speakers: speakers, clock: SessionClock(summary: summary),
                                      language: snapshot.language, failures: failures)
        try JSONFile.save(transcript, to: dir.transcript)
        try JSONFile.save(RunMetadata(runID: runID, snapshot: snapshot, startedAt: started, finishedAt: Date(),
                                      chunkCount: plan.count, requestCount: requests, audioSecondsSent: secondsSent,
                                      failedChunkCount: failures.count, languageFlagCount: transcript.languageFlagCount),
                          to: dir.metadata)
        return transcript
    }
}
