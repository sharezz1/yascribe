import Foundation
import Testing
import MeetNotesProviders
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

@Test func wordsLandOnTheSessionTimelineWhereTheSoundWas() async throws {
    // P4 w skali 3 minut: bramka, pakowanie, WAV, przeliczenie czasu i kotwice naraz.
    let (samples, starts) = burstTrack(seconds: 180, rate: 16_000)
    let dir = try makeSession(system: samples)
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr)).run()
    let words = t.utterances.flatMap(\.words)
    #expect(words.count == starts.count)
    for (w, s) in zip(words.sorted { $0.start < $1.start }, starts) {
        #expect(abs(w.start - s) < 0.03, "słowo w \(w.start) s, dźwięk w \(s) s")
    }
    #expect(asr.requests == 1) // 18 fragmentów po 2,4 s mieści się w jednym oknie
}

@Test func speakersComeFromChannelsWithMicOffsetApplied() async throws {
    // Mikrofon rusza 165 ms po systemie (zmierzone u Narady) — słowa „ja" muszą to uwzględnić.
    let sys = silence(seconds: 5, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 13, rate: 16_000)
    let mic = silence(seconds: 12, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 6, rate: 16_000)
    let dir = try makeSession(system: sys, mic: mic, micOffset: 0.165)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    let them = try #require(t.utterances.first { $0.speaker == .them })
    let me = try #require(t.utterances.first { $0.speaker == .me })
    #expect(abs(them.start - 5.0) < 0.03)
    #expect(abs(me.start - 12.165) < 0.03)
}

@Test func echoCancelledMicIsPreferredOverRaw() throws {
    let sum = SessionSummary(startedHostTime: 0, timebase: ns, wallClock: nil, endReason: nil, crashed: false, tracks: [
        .init(id: "system", sampleRate: 48_000, channels: 2, deviceUIDs: [], gaps: [], clock: []),
        .init(id: "mic_raw", sampleRate: 16_000, channels: 1, deviceUIDs: [], gaps: [], clock: []),
        .init(id: "mic_aec", sampleRate: 16_000, channels: 1, deviceUIDs: [], gaps: [], clock: []),
    ])
    #expect(TranscriptionRunner.tracks(in: sum).map(\.id) == ["system", "mic_aec"])
}

@Test func silentSessionSendsNothing() async throws {
    // P6 na całym potoku.
    let dir = try makeSession(system: silence(seconds: 60, rate: 16_000), mic: silence(seconds: 60, rate: 16_000))
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr)).run()
    #expect(asr.requests == 0)
    #expect(t.utterances.isEmpty)
}

@Test func interruptedRunResumesWithoutPayingAgain() async throws {
    // P5: pierwszy przebieg pada na 2. i dalszych oknach; drugi wysyła tylko brakujące.
    let (samples, _) = burstTrack(seconds: 600, rate: 16_000) // 60 fragmentów → kilka okien
    let dir = try makeSession(system: samples)
    let first = ListeningASR(failWhen: { $0 >= 2 })
    let t1 = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(first)).run()
    let total = first.requests
    #expect(total >= 3)
    #expect(t1.failedChunks.count == total - 1) // luki jawne, nie cisza udająca treść
    let second = ListeningASR()
    let t2 = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(second)).run()
    #expect(second.requests == total - 1)
    #expect(t2.failedChunks.isEmpty)
}

@Test func progressReachesOneAndMetadataCarriesTheSnapshot() async throws {
    let (samples, _) = burstTrack(seconds: 300, rate: 16_000)
    let dir = try makeSession(system: samples)
    let seen = Recorder()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR()))
        .run { seen.add($0.fraction) }
    #expect(seen.values.first == 0)
    #expect(seen.values.last == 1)
    let meta = try JSONFile.load(RunMetadata?.self, from: RunDirectory(session: dir, runID: "r1").metadata, default: nil)
    #expect(meta?.snapshot.model == "microsoft/mai-transcribe-2")
    #expect(meta?.snapshot.language == .polish)
}

@Test func confabulatedEnglishIsFlaggedAndExcludedFromNotes() async throws {
    // P11: preset polski, ASR zwraca płynną angielszczyznę.
    struct EnglishASR: HTTPClient {
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let d = try JSONSerialization.data(withJSONObject: ["text": "I think there is a problem with the production of the products."])
            return (d, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(EnglishASR())).run()
    let u = try #require(t.utterances.first)
    #expect(u.languageMismatch == .english)
    #expect(u.excludedFromNotes)
    #expect(u.approximateTiming) // brak słów z czasem → czas całego okna
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.withLock { v.append(x) } }
    var values: [Double] { lock.withLock { v } }
}

@Test func fullPipelineHandlesA48kStereoSystemTrack() async throws {
    let (mono, starts) = burstTrack(seconds: 60, rate: 48_000)
    let stereo = mono.flatMap { [$0, $0] }
    let dir = try makeSession(system: stereo, systemRate: 48_000, systemChannels: 2)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    let words = t.utterances.flatMap(\.words).sorted { $0.start < $1.start }
    #expect(words.count == starts.count)
    for (w, s) in zip(words, starts) {
        // 50 ms zamiast 30: filtr przepróbkowania rozmywa krawędzie tonu o kilka ms.
        #expect(abs(w.start - s) < 0.05, "słowo w \(w.start) s, dźwięk w \(s) s")
    }
}
