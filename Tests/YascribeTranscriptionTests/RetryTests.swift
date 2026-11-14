import Foundation
import Testing
@testable import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var sleeps: [Duration] = []
    private var n = 0
    var slept: [Duration] { lock.withLock { sleeps } }
    var calls: Int { lock.withLock { n } }
    func sleep(_ d: Duration) { lock.withLock { sleeps.append(d) } }
    func call() -> Int { lock.withLock { n += 1; return n } }
}

private let schedule: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

/// Ponawia `op`, która pada `failures` razy kodem `status`, a potem zwraca "ok".
private func attempt(status: Int, failures: Int, log: Log) async throws -> String {
    try await ASRRetry.run(delays: schedule, sleep: { log.sleep($0) }) {
        if log.call() <= failures { throw ProviderError.http(status, "x") }
        return "ok"
    }
}

@Test func retryWaitsLongerEachTimeAndSucceedsAfterTransientLimit() async throws {
    let log = Log()
    #expect(try await attempt(status: 429, failures: 3, log: log) == "ok")
    #expect(log.slept == schedule)
    #expect(log.calls == 4)
}

@Test func retryStopsAsSoonAsACallSucceeds() async throws {
    let log = Log()
    _ = try await attempt(status: 503, failures: 1, log: log)
    #expect(log.slept == [.seconds(1)])
    #expect(log.calls == 2)
}

@Test func retryGivesUpAfterTheLastDelayWithTheLastError() async {
    let log = Log()
    await #expect(throws: ProviderError.http(500, "x")) { _ = try await attempt(status: 500, failures: 99, log: log) }
    #expect(log.calls == schedule.count + 1)
    #expect(log.slept == schedule)
}

@Test(arguments: [400, 401, 404, 422]) func retryIgnoresClientErrors(status: Int) async {
    let log = Log()
    await #expect(throws: ProviderError.http(status, "x")) { _ = try await attempt(status: status, failures: 99, log: log) }
    #expect(log.calls == 1)
    #expect(log.slept.isEmpty)
}

@Test func retryIgnoresTransportAndOtherErrors() async {
    let log = Log()
    await #expect(throws: URLError.self) {
        try await ASRRetry.run(delays: schedule, sleep: { log.sleep($0) }) { _ = log.call(); throw URLError(.timedOut) }
    }
    #expect(log.calls == 1)
}

@Test func cancellationWhileWaitingStopsWithoutAnotherSend() async {
    let log = Log()
    await #expect(throws: CancellationError.self) {
        try await ASRRetry.run(delays: schedule, sleep: { _ in throw CancellationError() }) {
            _ = log.call(); throw ProviderError.http(429, "x")
        }
    }
    #expect(log.calls == 1)
}

@Test func defaultScheduleGrowsAndIsBounded() {
    #expect(ASRRetry.delays.count >= 3)
    #expect(ASRRetry.delays == ASRRetry.delays.sorted())
    #expect(Set(ASRRetry.delays).count == ASRRetry.delays.count)
}

@Test func runnerRetriesATransientFailureInsteadOfLeavingAGap() async throws {
    let dir = try makeSession(system: tone(seconds: 3, rate: 16_000))
    let asr = ListeningASR(failWhen: { $0 <= 2 }) // dwa pierwsze żądania: HTTP 500
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr),
                                          retryDelays: [.zero, .zero]).run()
    #expect(t.failedChunks.isEmpty)
    #expect(!t.utterances.isEmpty)
    #expect(asr.requests == 3)
    let meta = try #require(try JSONFile.load(RunMetadata?.self, from: RunDirectory(session: dir, runID: "r1").metadata, default: nil))
    #expect(meta.requestCount == 3) // każda próba to płatne żądanie
}

@Test func runnerKeepsTheGapWhenTheLimitNeverLifts() async throws {
    let dir = try makeSession(system: tone(seconds: 3, rate: 16_000))
    let asr = ListeningASR(failWhen: { _ in true })
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr),
                                          retryDelays: [.zero, .zero]).run()
    #expect(t.failedChunks.count == 1)
    #expect(asr.requests == 3)
}

@Test func runnerSendsOneRequestAtATime() async throws {
    // AC#2: ograniczona równoległość = 1 żądanie na przebieg (pętla okien jest sekwencyjna).
    let (samples, _) = burstTrack(seconds: 600, rate: 16_000)
    let dir = try makeSession(system: samples)
    let asr = ListeningASR(delayMillis: 5)
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr)).run()
    #expect(asr.requests >= 3)
    #expect(asr.maxInFlight == 1)
}

// Segment przechodzący przez sklejenie fragmentów okna kończy się we fragmencie, w którym leży jego koniec.
@Test(arguments: [true, false]) func segmentAcrossSpliceKeepsItsEnd(segmentTiming: Bool) {
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                           ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    let result = TranscriptionResult(text: "dzień dobry", words: [TranscribedWord(word: "dzień dobry", start: 0, end: 5.1)],
                                     segmentTiming: segmentTiming ? true : nil)
    let t = Merger.merge([ChunkResult(track: "system", chunk: chunk, result: result)], speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])), language: .polish)
    #expect(abs(t.utterances[0].start - 5.0) < 1e-6)
    // Słowo zostaje przycięte do swojego fragmentu (7,4 s); segment sięga do 17,4 s.
    #expect(abs(t.utterances[0].end - (segmentTiming ? 17.4 : 7.4)) < 1e-3)
    // Segment to kilka sekund, nie słowo: czas przybliżony (etykieta w UI). Słowa — dokładny.
    #expect(t.utterances[0].approximateTiming == segmentTiming)
}

// Koniec segmentu w sztucznej przerwie (2,4–2,7 s) albo dokładnie na początku następnego fragmentu należy do poprzedniego
// fragmentu (7,4 s); próbkę dalej — już do następnego (15,0 s).
@Test(arguments: [2.4, 2.5, 2.6, 2.7, 2.7 + 1 / 16_000]) func segmentEndingInTheSpliceGapEndsWithItsFragment(end: Double) {
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                           ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    let result = TranscriptionResult(text: "dzień dobry", words: [TranscribedWord(word: "dzień dobry", start: 0, end: end)],
                                     segmentTiming: true)
    let t = Merger.merge([ChunkResult(track: "system", chunk: chunk, result: result)], speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])), language: .polish)
    #expect(abs(t.utterances[0].start - 5.0) < 1e-6)
    #expect(abs(t.utterances[0].end - (end > 2.7 ? 15.0 : 7.4)) < 1e-3)
}

// Dwa segmenty stykające się na granicy fragmentów (7,6 s wyciętej ciszy) to dwie wypowiedzi, nie jedna.
@Test func adjacentSegmentsAcrossTheSpliceStayApart() {
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                           ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    let result = TranscriptionResult(text: "raz dwa", words: [TranscribedWord(word: "raz", start: 0, end: 2.7),
                                                              TranscribedWord(word: "dwa", start: 2.7, end: 4.0)], segmentTiming: true)
    let t = Merger.merge([ChunkResult(track: "system", chunk: chunk, result: result)], speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])), language: .polish)
    #expect(t.utterances.map(\.text) == ["raz", "dwa"])
    #expect(abs(t.utterances[0].end - 7.4) < 1e-3)
}

@Test(arguments: [true, false]) func approximateTimingFollowsEachUtteranceAcrossWindows(segmentFirst: Bool) {
    let results = [
        ChunkResult(track: "system", chunk: Chunk(index: 0, segments: [ChunkSegment(sourceStart: 0, sourceEnd: 32_000, chunkStart: 0)], length: 32_000),
                    result: TranscriptionResult(text: "raz", words: [TranscribedWord(word: "raz", start: 0, end: 1)], segmentTiming: segmentFirst ? true : nil)),
        ChunkResult(track: "system", chunk: Chunk(index: 1, segments: [ChunkSegment(sourceStart: 16_000, sourceEnd: 48_000, chunkStart: 0)], length: 32_000),
                    result: TranscriptionResult(text: "dwa trzy", words: [TranscribedWord(word: "dwa trzy", start: 0, end: 1)], segmentTiming: segmentFirst ? nil : true)),
        ChunkResult(track: "system", chunk: Chunk(index: 2, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 112_000, chunkStart: 0)], length: 32_000),
                    result: TranscriptionResult(text: "cztery", words: [TranscribedWord(word: "cztery", start: 0, end: 1)]))]
    let t = Merger.merge(results, speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])), language: .polish)
    #expect(t.utterances.map(\.text) == ["raz dwa trzy", "cztery"])
    #expect(t.utterances.map(\.approximateTiming) == [true, false])
}

@Test(arguments: [nil, [TranscribedWord]()]) func windowWithoutWordTimesBecomesOneApproximateUtterance(words: [TranscribedWord]?) {
    // Voxtral bez `word`: tylko tekst. Wypowiedź obejmuje fragmenty okna, `sourceSpan` nie gra roli.
    let chunk = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                           ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    let t = Merger.merge([ChunkResult(track: "system", chunk: chunk, result: TranscriptionResult(text: "dzień dobry", words: words))],
                         speakers: ["system": .them],
                         clock: SessionClock(summary: SessionSummary(startedHostTime: 0, timebase: ns, tracks: [])), language: .polish)
    #expect(t.utterances.count == 1)
    #expect(t.utterances[0].approximateTiming)
    #expect(t.utterances[0].text == "dzień dobry")
    #expect(abs(t.utterances[0].start - 5.0) < 1e-6 && abs(t.utterances[0].end - 17.4) < 1e-6)
}

