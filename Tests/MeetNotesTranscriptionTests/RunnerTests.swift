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
    // Check S10 #2: okno z inną geometrią niż w planie nie jest brane z dysku.
    let file = RunDirectory(session: dir, runID: "r1").chunk("system", 0)
    var stale = try #require(try JSONFile.load(ChunkResult?.self, from: file, default: nil))
    stale.chunk.segments[0].sourceStart += 1_600
    try JSONFile.save(stale, to: file)
    let third = ListeningASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(third)).run()
    #expect(third.requests == 1)
}

@Test func progressReachesOneAndMetadataCarriesTheSnapshot() async throws {
    let (samples, _) = burstTrack(seconds: 300, rate: 16_000)
    let dir = try makeSession(system: samples)
    let seen = Recorder()
    let asr = ListeningASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr))
        .run { seen.add($0.fraction) }
    #expect(seen.values.first == 0)
    #expect(seen.values.last == 1)
    let meta = try JSONFile.load(RunMetadata?.self, from: RunDirectory(session: dir, runID: "r1").metadata, default: nil)
    #expect(meta?.snapshot.model == "microsoft/mai-transcribe-2")
    #expect(meta?.snapshot.language == .polish)
    // Check S10 #1: na tych licznikach stoi bramka C5 („cisza nie poszła").
    #expect(asr.requests > 0)
    #expect(meta?.requestCount == asr.requests)
    #expect(meta?.chunkCount == asr.requests)
    #expect((meta?.audioSecondsSent ?? 0) > 0)
    #expect((meta?.audioSecondsSent ?? .infinity) < 300)
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

@Test func requestsCarryTheSnapshotModelAndLanguage() async throws {
    // Przegląd S18 BLOKUJĄCE #1: żądanie ASR idzie modelem i językiem migawki, nie z innego pola.
    let (samples, _) = burstTrack(seconds: 300, rate: 16_000)
    let dir = try makeSession(system: samples)
    let snap = try snapshot()
    let asr = SnapshotRecordingASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: snap, client: client(asr)).run()
    #expect(!asr.sent.isEmpty)
    #expect(asr.sent.allSatisfy { $0 == Sent(model: snap.model, language: snap.language.rawValue) })
}

@Test func resumeSendsTheSnapshotFromInputJSON() async throws {
    // Przegląd S18 Q3: drugi przebieg tego samego runID wysyła migawkę z `input.json`, nigdy bieżący preset.
    let (samples, _) = burstTrack(seconds: 600, rate: 16_000)
    let dir = try makeSession(system: samples)
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(),
                                      client: client(ListeningASR(failWhen: { $0 >= 2 }))).run()
    let saved = try #require(try JSONFile.load(RunInput?.self, from: RunDirectory(session: dir, runID: "r1").input, default: nil)).snapshot
    let expected = Sent(model: saved.model, language: saved.language.rawValue)
    // bieżący preset z innym modelem i językiem: odmowa albo migawka z pliku — nic innego nie wychodzi
    var current = try snapshot(language: .english)
    current.model = "other/model"
    let refused = SnapshotRecordingASR()
    _ = try? await TranscriptionRunner(session: dir, runID: "r1", snapshot: current, client: client(refused)).run()
    #expect(refused.sent.allSatisfy { $0 == expected })
    // wznowienie jak `AppModel.resume`: migawka z pliku, brakujące okna idą nią
    let resumed = SnapshotRecordingASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: saved, client: client(resumed)).run()
    #expect(!resumed.sent.isEmpty)
    #expect(resumed.sent.allSatisfy { $0 == expected })
}

struct Sent: Equatable {
    var model: String?
    var language: String?
}

/// Nagrywa `model` i `language` z ciała każdego żądania; odpowiada jak `ListeningASR`.
final class SnapshotRecordingASR: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Sent] = []
    private let inner = ListeningASR()
    var sent: [Sent] { lock.withLock { seen } }
    func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        lock.withLock { seen.append(Sent(model: body["model"] as? String, language: body["language"] as? String)) }
        return try await inner.send(r)
    }
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

@Test func crosstalkFromSpeakersIsDroppedBeforeASR() async throws {
    // W§1, rozdz. 17, ChatGPT #1: mikrofon słyszy głośniki, bramka energii uznałaby to za mowę.
    var sys = silence(seconds: 2, rate: 16_000)
    for _ in 0..<5 { sys += tone(seconds: 0.4, rate: 16_000) + silence(seconds: 0.3, rate: 16_000) }
    sys += silence(seconds: 5, rate: 16_000)
    // echo: 100 ms drogi akustycznej, ~14 dB ciszej
    var mic = Array(([Int16](repeating: 0, count: 1_600) + sys.map { Int16(Double($0) * 0.2) }).prefix(sys.count))
    // check S11 #3: własna mowa w ciszy systemu (7–9 s), inny ton niż echo — musi zostać
    #expect(mic.count >= Int(9 * 16_000))
    mic.replaceSubrange(Int(7 * 16_000)..<Int(9 * 16_000), with: tone(seconds: 2, rate: 16_000, hz: 500))
    let dir = try makeSession(system: sys, mic: mic)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    #expect(t.utterances.contains { $0.speaker == .them })
    let me = t.utterances.filter { $0.speaker == .me }
    #expect(!me.isEmpty)
    #expect(me.allSatisfy { $0.start > 6.5 }) // echo z 2–5,6 s odpadło
}

@Test func runIDEscapingTheRunsDirectoryIsRejected() async throws {
    // ChatGPT #13.
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000))
    await #expect(throws: RunError.badRunID("../x")) {
        _ = try await TranscriptionRunner(session: dir, runID: "../x", snapshot: try snapshot(), client: client(ListeningASR())).run()
    }
}

@Test func resumingWithADifferentPresetIsRefused() async throws {
    // ChatGPT #4: te same granice okien nie mogą przenieść wyników na inny język albo model.
    let (samples, _) = burstTrack(seconds: 60, rate: 16_000)
    let dir = try makeSession(system: samples)
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(language: .english),
                                          client: client(ListeningASR())).run()
    }
    // przegląd S11 #1: inne progi przesłuchu → inne granice okien
    let strict = { var c = CrosstalkFilter(); c.correlationThreshold = 0.5; return c }()
    await #expect(throws: RunError.inputMismatch) {
        _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(),
                                          client: client(ListeningASR()), crosstalk: strict).run()
    }
}

@Test func snapshotCarriesTheWholePresetAndRefusesChatShape() throws {
    // ChatGPT #14 (pełna migawka) i #7 (bez znaczników słów nie ma spotkania).
    let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(name: "Polish", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "m"),
                        summary: RoleAssignment(providerID: provider.id, model: "s", prompt: "Decisions and owners"))
    #expect(try RunSnapshot(preset: preset, provider: provider, probe: nil).preset.summary?.prompt == "Decisions and owners")
    let chat = ProbeResult(providerID: provider.id, model: "m", role: .asr, works: true, shape: .chatAudio)
    #expect(throws: RunSnapshotError.chatShapeNotForMeetings) { _ = try RunSnapshot(preset: preset, provider: provider, probe: chat) }
}

@Test func failedEchoCancelledMicFallsBackToRaw() {
    // Hermes 4.2: martwy mic_aec nie może wypchnąć żywego mic_raw.
    let sum = SessionSummary(startedHostTime: 0, timebase: ns, tracks: [
        .init(id: "system", sampleRate: 48_000, channels: 2),
        .init(id: "mic_raw", sampleRate: 16_000, channels: 1),
        .init(id: "mic_aec", sampleRate: 16_000, channels: 1, failure: "inputDeviceChanged"),
    ])
    #expect(TranscriptionRunner.tracks(in: sum).map(\.id) == ["system", "mic_raw"])
}

@Test func gapTimesAreOnTheSessionTimeline() async throws {
    // 🟡 ChatGPT: luka „Me" przesunięta o opóźnienie startu mikrofonu.
    let mic = silence(seconds: 3, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 3, rate: 16_000)
    let dir = try makeSession(system: silence(seconds: 8, rate: 16_000), mic: mic, micOffset: 0.5)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(),
                                          client: client(ListeningASR(failWhen: { _ in true }))).run()
    let f = try #require(t.failedChunks.first)
    #expect(abs(f.start - 3.3) < 0.05) // 0,5 s przesunięcia + 2,8 s (ton w 3. s minus 0,2 s zapasu bramki)
}

@Test func eightyFiveMinutesStayAlignedAcrossWindowBoundaries() async throws {
    // P4 deterministycznie, bez „jeśli jest plik" (ChatGPT #15, Hermes 3.2). Długi: ~1 min w debug.
    let (samples, starts) = burstTrack(seconds: 85 * 60, rate: 16_000)
    let dir = try makeSession(system: samples)
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r85", snapshot: try snapshot(), client: client(asr)).run()
    let words = t.utterances.flatMap(\.words).sorted { $0.start < $1.start }
    #expect(words.count == starts.count)
    #expect(asr.requests > 10) // wiele okien, więc wiele granic
    for (w, s) in zip(words, starts) { #expect(abs(w.start - s) < 0.03) }
    for (a, b) in zip(words, words.dropFirst()) { #expect(a.end <= b.start) } // bez nakładek
    #expect(words.allSatisfy { $0.end > $0.start })
}

@Test func sessionTimeComesFromClockAnchorsNotJustTheOffset() throws {
    // Check S10 #3 (T8): zegar mikrofonu chodzi 0,1% wolniej — czas z kotwic, nie z offsetSeconds.
    let anchors = try JSONDecoder().decode([SessionSummary.ClockAnchor].self, from: Data("""
        [{"frameIndex": 0, "hostTime": 1200000000}, {"frameIndex": 1600000, "hostTime": 101300000000}]
        """.utf8))
    let sum = SessionSummary(startedHostTime: 0, timebase: ns, tracks: [
        .init(id: "system", sampleRate: 16_000, channels: 1, firstSampleHostTime: 1_000_000_000, offsetSeconds: 0),
        .init(id: "mic_raw", sampleRate: 16_000, channels: 1, firstSampleHostTime: 1_200_000_000, offsetSeconds: 0.2,
              clock: anchors),
    ])
    // ramka 50 s → 50,05 s czasu hosta od startu mikrofonu; sam offset dałby 50,2
    #expect(abs(SessionClock(summary: sum).sessionSeconds(track: "mic_raw", trackSeconds: 50) - 50.25) < 0.001)
}

@Test func utteranceBreaksOnlyAtTheGap() throws {
    // Check S10 #4: przerwa 1,0 s łączy słowa, 1,5 s zaczyna nową wypowiedź (Merger.utteranceGap = 1,2 s).
    let result = try JSONDecoder().decode(TranscriptionResult.self, from: Data("""
        {"text": "a b c", "words": [{"word": "a", "start": 0, "end": 0.5}, {"word": "b", "start": 1.5, "end": 2},
                                    {"word": "c", "start": 3.5, "end": 4}]}
        """.utf8))
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 0, sourceEnd: 80_000, chunkStart: 0)], length: 80_000)
    let t = Merger.merge([ChunkResult(track: "system", chunk: chunk, result: result)], speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])),
                         language: .polish)
    #expect(t.utterances.map(\.text) == ["a b", "c"])
}
