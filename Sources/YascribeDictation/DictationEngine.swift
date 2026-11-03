import Foundation
import Observation

/// Metadane wpisu historii ustalane w chwili `.stop` (zmiana ustawień w trakcie nie zmienia wpisu).
public struct DictationRecordMeta: Equatable, Sendable {
    public var app: String?
    public var asrModel: String?
    public var correctionModel: String?

    public init(app: String? = nil, asrModel: String? = nil, correctionModel: String? = nil) {
        self.app = app; self.asrModel = asrModel; self.correctionModel = correctionModel
    }
}

/// Mikrofon dyktowania. `stop()` zwraca próbki 16 kHz mono i zwalnia mikrofon; `level` 0…1 dla miernika;
/// `onFailure` przy awarii źródła albo końcu strumienia w trakcie nagrywania.
public protocol AudioCapturing: AnyObject, Sendable {
    func start(onFailure: @escaping @Sendable (String) -> Void) throws
    func stop() -> [Int16]
    var level: Float { get }
}

/// `blocked` = secure input: nic nie wkładamy ani nie zapisujemy w schowku.
public enum InsertResult: Equatable, Sendable {
    case inserted, copiedOnly(reason: String), blocked(reason: String)
}

public protocol TextInserting: AnyObject, Sendable {
    func insert(_ text: String) async -> InsertResult
    /// Odczyt zapamiętuje cel wklejenia: czytać dokładnie raz na sesję, przy jej starcie.
    var frontmostAppName: String? { get }
}

public enum DictationPhase: Equatable, Sendable {
    case idle, listening, processing, finished(InsertResult), failed(String), refused(String)
}

/// Sesja dyktowania: mikrofon → potok → wstawienie → historia. Audio tylko w pamięci, nigdy na dysku.
/// Obserwowana jest tylko `phase` (UI widzi też przejścia wewnętrzne: auto-stop, powrót do `.idle`, awarię mikrofonu).
@MainActor @Observable public final class DictationEngine {
    public static let missingModelMessage = "Choose a dictation model in Settings."

    struct Retained {
        var input: DictationPipelineInput
        var meta: DictationRecordMeta
        var app: String?
        var seconds: Double
        var date: Date
    }

    private let capture: any AudioCapturing
    private let inserter: any TextInserting
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let maxDuration: Duration
    private let resultVisibleFor: Duration
    private let buildInput: (_ pcm: [Int16]) -> (input: DictationPipelineInput, meta: DictationRecordMeta)?
    private let record: (DictationEntry) -> Void

    public private(set) var phase: DictationPhase = .idle
    /// Każde przejście unieważnia spóźnione wznowienia (timery, `onFailure`, potok) z poprzedniej sesji.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var startApp: String?
    /// Próbki po błędzie ASR do jednego `retry()`.
    @ObservationIgnored private(set) var retained: Retained?
    @ObservationIgnored private(set) var maxTimer: Task<Void, Never>?
    @ObservationIgnored private(set) var resetTimer: Task<Void, Never>?
    @ObservationIgnored private(set) var work: Task<Void, Never>?

    public init(capture: any AudioCapturing, inserter: any TextInserting, now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                maxDuration: Duration = .seconds(300), resultVisibleFor: Duration = .seconds(2),
                buildInput: @escaping (_ pcm: [Int16]) -> (input: DictationPipelineInput, meta: DictationRecordMeta)?,
                record: @escaping (DictationEntry) -> Void) {
        self.capture = capture; self.inserter = inserter; self.now = now; self.sleep = sleep
        self.maxDuration = maxDuration; self.resultVisibleFor = resultVisibleFor
        self.buildInput = buildInput; self.record = record
    }

    public var isBusy: Bool { phase == .listening || phase == .processing }

    public var canRetry: Bool {
        if case .failed = phase { return retained != nil }
        return false
    }

    public func apply(_ action: HotkeyAction) {
        switch action {
        case .start: start()
        case .stop: stop()
        case .cancel:
            guard phase == .listening else { return }
            releaseMic()
            phase = .idle
        }
    }

    public func toggleFromLauncher() {
        if phase == .listening { stop() } else if !isBusy { start() }
    }

    /// W trakcie nagrywania zwalnia mikrofon; trwającej transkrypcji nie przerywa.
    public func refuse(_ message: String) {
        guard phase != .processing else { return }
        if phase == .listening { releaseMic() }
        retained = nil
        finish(.refused(message))
    }

    /// Zamknięcie aplikacji: czeka na koniec trwającej transkrypcji i wstawienia (`retry()` podmienia `work`, stąd pętla).
    /// To samo `work` po zakończeniu = nie ma na co czekać (bez kręcenia się na głównym aktorze).
    public func waitUntilIdle() async {
        while phase == .processing, let w = work {
            await w.value
            if work == w { break }
        }
    }

    public func retry() {
        guard canRetry, let r = retained else { return }
        retained = nil
        resetTimer?.cancel()
        session += 1
        phase = .processing
        process(r, keepOnFailure: false)
    }

    private func start() {
        guard !isBusy else { return }
        resetTimer?.cancel()
        retained = nil
        session += 1
        // Sprawdzenie modelu przed zajęciem mikrofonu; właściwe wejście powstaje przy `.stop`.
        guard buildInput([]) != nil else { return finish(.refused(Self.missingModelMessage)) }
        startApp = inserter.frontmostAppName
        let token = session
        do {
            try capture.start { [weak self] message in
                Task { @MainActor in self?.micFailed(message, token: token) }
            }
        } catch {
            return finish(.failed(Self.describe(error)))
        }
        startedAt = now()
        phase = .listening
        maxTimer = Task { [weak self, sleep, maxDuration] in
            do { try await sleep(maxDuration) } catch { return }
            guard !Task.isCancelled, let self, self.session == token else { return }
            self.stop()
        }
    }

    private func stop() {
        guard phase == .listening else { return }
        let pcm = releaseMic()
        let seconds = now().timeIntervalSince(startedAt)
        guard let built = buildInput(pcm) else { return finish(.refused(Self.missingModelMessage)) }
        phase = .processing
        process(Retained(input: built.input, meta: built.meta, app: startApp ?? built.meta.app, seconds: seconds, date: startedAt),
                keepOnFailure: true)
    }

    private func micFailed(_ message: String, token: Int) {
        guard session == token, phase == .listening else { return }
        releaseMic()
        finish(.failed(message))
    }

    private func process(_ r: Retained, keepOnFailure: Bool) {
        let token = session
        work = Task { [self] in
            let output: DictationOutput?
            do { output = try await DictationPipeline.run(r.input) } catch {
                guard session == token else { return }
                if keepOnFailure { retained = r }
                return finish(.failed(Self.describe(error)))
            }
            guard session == token else { return }
            guard let output else {
                phase = .idle
                return
            }
            let result = await inserter.insert(output.text)
            guard session == token else { return }
            switch result {
            case .blocked: break   // secure input: tekst nie trafia nigdzie, także do historii
            case .inserted, .copiedOnly:
                record(DictationEntry(date: r.date, raw: output.raw, text: output.text, correctionFailed: output.correctionFailed,
                                      app: r.app, seconds: r.seconds, asrModel: r.meta.asrModel,
                                      correctionModel: r.meta.correctionModel, inserted: result == .inserted))
            }
            finish(.finished(result))
        }
    }

    @discardableResult private func releaseMic() -> [Int16] {
        maxTimer?.cancel()
        maxTimer = nil
        session += 1
        return capture.stop()
    }

    /// Stan wyniku; po `resultVisibleFor` powrót do `.idle` porzuca zachowane próbki.
    private func finish(_ result: DictationPhase) {
        session += 1
        phase = result
        let token = session
        resetTimer?.cancel()
        resetTimer = Task { [weak self, sleep, resultVisibleFor] in
            do { try await sleep(resultVisibleFor) } catch { return }
            guard !Task.isCancelled, let self, self.session == token else { return }
            self.retained = nil
            self.phase = .idle
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
