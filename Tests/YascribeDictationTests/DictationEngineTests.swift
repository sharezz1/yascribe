import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeDictation

private struct Boom: Error {}

/// Atrapa mikrofonu. Bezpieczna jako `@unchecked Sendable`, bo cały stan jest pod `lock`.
private final class FakeCapture: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0, stops = 0
    private var onFailure: (@Sendable (String) -> Void)?
    private let samples: [Int16]
    private let startError: (any Error)?

    init(seconds: Double = 1, startError: (any Error)? = nil) {
        samples = [Int16](repeating: 100, count: Int(seconds * 16_000))
        self.startError = startError
    }

    func start(onFailure: @escaping @Sendable (String) -> Void) throws {
        try lock.withLock {
            starts += 1
            if let startError { throw startError }
            self.onFailure = onFailure
        }
    }
    func stop() -> [Int16] { lock.withLock { stops += 1; return samples } }
    var level: Float { 0 }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func fail(_ message: String) { lock.withLock { onFailure }?(message) }
}

/// Atrapa wstawiania. Stan pod `lock`.
private final class FakeInserter: TextInserting, @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private var app: String?
    private let result: InsertResult

    init(result: InsertResult = .inserted, app: String? = "Front") { self.result = result; self.app = app }

    func insert(_ text: String) async -> InsertResult { lock.withLock { texts.append(text) }; return result }
    var frontmostAppName: String? {
        get { lock.withLock { app } }
        set { lock.withLock { app = newValue } }
    }
    var inserted: [String] { lock.withLock { texts } }
}

/// Transkryber z kolejką odpowiedzi; ostatnia się powtarza. Stan pod `lock`.
private final class ScriptedASR: TranscriptionClient, @unchecked Sendable {
    let provider = Provider(name: "Stub", baseURL: URL(string: "http://localhost:1")!)
    private let lock = NSLock()
    private var replies: [Result<String, Boom>]
    private var count = 0

    init(_ replies: [Result<String, Boom>]) { self.replies = replies }

    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        let reply = lock.withLock {
            count += 1
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
        return TranscriptionResult(text: try reply.get(), words: nil)
    }
    var calls: Int { lock.withLock { count } }
}

/// Czasy z `fire` mijają od razu, pozostałe praktycznie nigdy (ale dają się anulować).
private func sleeper(fire: Set<Duration>) -> @Sendable (Duration) async throws -> Void {
    { d in
        if fire.contains(d) { return }
        try await Task.sleep(for: .seconds(3600))
    }
}

@MainActor private final class Harness {
    let capture: FakeCapture
    let inserter: FakeInserter
    let asr: ScriptedASR
    var records: [DictationEntry] = []
    var clock = Date(timeIntervalSince1970: 1_000)
    var modelAvailable = true
    var meta = DictationRecordMeta(app: "MetaApp", asrModel: "asr-1", correctionModel: nil)
    var engine: DictationEngine!

    init(capture: FakeCapture = FakeCapture(), inserter: FakeInserter = FakeInserter(),
         asr: [Result<String, Boom>] = [.success("hello")],
         fire: Set<Duration> = [], maxDuration: Duration = .seconds(300), resultVisibleFor: Duration = .seconds(2)) {
        self.capture = capture; self.inserter = inserter; self.asr = ScriptedASR(asr)
        engine = DictationEngine(capture: capture, inserter: inserter, now: { [unowned self] in clock },
                                 sleep: sleeper(fire: fire), maxDuration: maxDuration, resultVisibleFor: resultVisibleFor,
                                 buildInput: { [unowned self] pcm in
                                     guard modelAvailable else { return nil }
                                     let input = DictationPipelineInput(pcm: pcm, language: nil, asrModel: meta.asrModel ?? "",
                                                                        transcriber: self.asr, shape: .audioTranscriptions, chat: nil,
                                                                        vocabulary: PromptVocabulary(), removeFillers: nil,
                                                                        replacement: ReplacementRules(UserDictionary()))
                                     return (input, meta)
                                 },
                                 record: { [unowned self] in records.append($0) })
    }

    /// Start, upływ `seconds` na zegarze, stop i czekanie na potok.
    func dictate(seconds: Double = 1.5) async {
        engine.apply(.start)
        clock += seconds
        engine.apply(.stop)
        await engine.work?.value
    }

    /// `onFailure` wraca na główny aktor przez `Task`; ograniczone oddanie wątku zamiast zegara.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor @Suite struct DictationEngineTests {
    @Test func startStopInsertsAndRecords() async {
        let h = Harness()
        h.engine.apply(.start)
        #expect(h.engine.phase == .listening)
        #expect(h.engine.isBusy)
        h.clock += 2.5
        h.engine.apply(.stop)
        #expect(h.engine.phase == .processing)
        await h.engine.work?.value
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.inserter.inserted == ["hello"])
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.maxTimer == nil)
        #expect(h.records.count == 1)
        let e = h.records.first
        #expect(e?.raw == "hello")
        #expect(e?.text == "hello")
        #expect(e?.seconds == 2.5)
        #expect(e?.date == Date(timeIntervalSince1970: 1_000))
        #expect(e?.asrModel == "asr-1")
        #expect(e?.correctionFailed == false)
        #expect(e?.inserted == true)
        #expect(e?.app == "Front")
        h.capture.fail("End of stream")   // spóźniony sygnał źródła po zwolnieniu mikrofonu
        await h.settle()
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.capture.stopCount == 1)
    }

    @Test func tooShortRecordingLeavesNoTrace() async {
        let h = Harness(capture: FakeCapture(seconds: 0.15))
        await h.dictate(seconds: 0.15)
        #expect(h.engine.phase == .idle)
        #expect(h.records.isEmpty)
        #expect(h.inserter.inserted.isEmpty)
        #expect(h.asr.calls == 0)
        #expect(h.capture.stopCount == 1)
    }

    @Test func missingModelIsRefused() {
        let h = Harness()
        h.modelAvailable = false
        h.engine.apply(.start)
        #expect(h.engine.phase == .refused("Choose a dictation model in Settings."))
        #expect(h.capture.startCount == 0)
        #expect(!h.engine.isBusy)
    }

    @Test func cancelDoesNotInsertOrRecord() async {
        let h = Harness()
        h.engine.apply(.start)
        h.engine.apply(.cancel)
        #expect(h.engine.phase == .idle)
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.maxTimer == nil)
        #expect(h.engine.work == nil)
        #expect(h.asr.calls == 0)
        #expect(h.records.isEmpty)
        #expect(h.inserter.inserted.isEmpty)
        h.engine.apply(.stop)   // spóźnione puszczenie klawisza po anulowaniu
        h.capture.fail("End of stream")
        await h.settle()
        #expect(h.engine.phase == .idle)
        #expect(h.capture.stopCount == 1)
    }

    @Test func copiedOnlyIsRecordedAsNotInserted() async {
        let h = Harness(inserter: FakeInserter(result: .copiedOnly(reason: "No Accessibility")))
        await h.dictate()
        #expect(h.engine.phase == .finished(.copiedOnly(reason: "No Accessibility")))
        #expect(h.records.count == 1)
        #expect(h.records.first?.inserted == false)
        #expect(h.records.first?.text == "hello")
    }

    @Test func blockedInsertionIsNotRecorded() async {
        let h = Harness(inserter: FakeInserter(result: .blocked(reason: "Secure input")))
        await h.dictate()
        #expect(h.engine.phase == .finished(.blocked(reason: "Secure input")))
        #expect(h.records.isEmpty)
    }

    @Test func captureFailureOnStartIsFailed() {
        let h = Harness(capture: FakeCapture(startError: Boom()))
        h.engine.apply(.start)
        guard case .failed = h.engine.phase else { Issue.record("phase \(h.engine.phase)"); return }
        #expect(h.engine.maxTimer == nil)
        #expect(!h.engine.canRetry)
        h.engine.apply(.stop)
        #expect(h.capture.stopCount == 0)
        #expect(h.records.isEmpty)
    }

    @Test func captureFailureMidRecordingIsFailed() async {
        let h = Harness()
        h.engine.apply(.start)
        h.capture.fail("Microphone disconnected")
        await h.settle()
        #expect(h.engine.phase == .failed("Microphone disconnected"))
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.maxTimer == nil)
        #expect(!h.engine.canRetry)
        h.engine.apply(.stop)
        #expect(h.engine.work == nil)
        #expect(h.asr.calls == 0)
        #expect(h.records.isEmpty)
    }

    @Test func asrFailureKeepsAudioForOneRetry() async {
        let h = Harness(asr: [.failure(Boom()), .success("hello")])
        await h.dictate()
        guard case .failed = h.engine.phase else { Issue.record("phase \(h.engine.phase)"); return }
        #expect(h.engine.canRetry)
        #expect(h.records.isEmpty)
        h.engine.retry()
        #expect(h.engine.phase == .processing)
        await h.engine.work?.value
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.records.count == 1)
        #expect(h.records.first?.seconds == 1.5)
        #expect(!h.engine.canRetry)
        h.engine.retry()
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.asr.calls == 2)
    }

    @Test func appNameIsSnapshottedAtStart() async {
        let h = Harness()
        h.inserter.frontmostAppName = "Editor"
        h.engine.apply(.start)
        h.inserter.frontmostAppName = "Other"
        h.engine.apply(.stop)
        await h.engine.work?.value
        #expect(h.records.first?.app == "Editor")

        let n = Harness(inserter: FakeInserter(app: nil))
        await n.dictate()
        #expect(n.records.first?.app == "MetaApp")
    }

    @Test func refuseSetsRefusedPhase() {
        let h = Harness()
        h.engine.refuse("Dictation is unavailable while recording a meeting.")
        #expect(h.engine.phase == .refused("Dictation is unavailable while recording a meeting."))
        h.engine.apply(.start)
        #expect(h.engine.phase == .listening)
        h.engine.refuse("Stop")
        #expect(h.engine.phase == .refused("Stop"))
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.maxTimer == nil)
    }

    @Test func maxDurationStopsAutomatically() async {
        let h = Harness(fire: [.milliseconds(50)], maxDuration: .milliseconds(50))
        h.engine.apply(.start)
        #expect(h.engine.phase == .listening)
        await h.engine.maxTimer?.value
        await h.engine.work?.value
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.records.count == 1)
        h.engine.apply(.stop)   // puszczenie klawisza po automatycznym stopie
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.capture.stopCount == 1)
    }

    @Test func pipelineErrorIsFailedAndNotRecorded() async {
        let h = Harness(asr: [.failure(Boom())])
        await h.dictate()
        guard case .failed = h.engine.phase else { Issue.record("phase \(h.engine.phase)"); return }
        #expect(h.records.isEmpty)
        #expect(h.inserter.inserted.isEmpty)
        h.engine.retry()
        await h.engine.work?.value
        guard case .failed = h.engine.phase else { Issue.record("phase \(h.engine.phase)"); return }
        #expect(!h.engine.canRetry)   // tylko jedno ponowienie, także nieudane
        #expect(h.asr.calls == 2)
    }

    @Test func startWhileBusyIgnored() async {
        let h = Harness()
        h.engine.apply(.start)
        h.engine.apply(.start)
        h.engine.toggleFromLauncher()   // w listening = stop
        #expect(h.engine.phase == .processing)
        h.engine.apply(.start)
        h.engine.toggleFromLauncher()
        h.engine.apply(.cancel)         // w trakcie przetwarzania ignorowane
        #expect(h.engine.phase == .processing)
        await h.engine.work?.value
        #expect(h.capture.startCount == 1)
        #expect(h.capture.stopCount == 1)
        #expect(h.engine.phase == .finished(.inserted))
        #expect(h.records.count == 1)
    }

    @Test func resultReturnsToIdleAndDropsRetry() async {
        let h = Harness(asr: [.failure(Boom()), .success("hello")], fire: [.milliseconds(1)], resultVisibleFor: .milliseconds(1))
        await h.dictate()
        await h.engine.resetTimer?.value
        #expect(h.engine.phase == .idle)
        #expect(!h.engine.canRetry)
        #expect(h.engine.retained == nil)   // próbki zwolnione z pamięci
        h.engine.retry()
        #expect(h.engine.phase == .idle)
        #expect(h.asr.calls == 1)
    }
}
