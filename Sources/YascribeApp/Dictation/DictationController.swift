import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation
import YascribeDictation
import YascribeNotes
import YascribeProviders
import YascribeTranscription

/// Spina dyktowanie z aplikacją: skrót globalny, silnik, historia i ustawienia z `AppModel`.
/// `init` bez wejścia-wyjścia i bez okien zgody: tworzy go `AppModel.load()` także w migawkach.
@MainActor @Observable final class DictationController {
    static let missingLanguageMessage = "Choose a dictation language in Settings."

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let capture = MicCapture()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored lazy var engine = DictationEngine(capture: capture, inserter: inserter,
                                                          buildInput: { [weak self] in self?.buildInput($0) },
                                                          record: { [weak self] in self?.record($0) })
    @ObservationIgnored private lazy var monitor = GlobalHotkeyMonitor { [weak self] in self?.handle($0) }

    private(set) var history = DictationHistoryFile()
    private(set) var permissions: (inputMonitoring: Bool, accessibility: Bool, microphone: Bool) = (false, false, false)
    private(set) var monitorRunning = false
    /// `start()` był wołany, a `stop()` jeszcze nie (migawki i testy kontrolera nie startują).
    @ObservationIgnored private var active = false
    /// Plik historii nie dał się odczytać ani odłożyć: zapis by go nadpisał.
    @ObservationIgnored private var historyLocked = false

    init(model: AppModel) { self.model = model }

    /// Poziom mikrofonu 0…1 dla pastylki (odczyt pod zamkiem; nieobserwowany, UI odpytuje).
    var level: Float { capture.level }

    // MARK: Cykl życia

    func start() {
        guard !active else { return }
        active = true
        applySettings()
        trackPhase()
    }

    /// Zamknięcie aplikacji: tap off, nagrywanie przerwane (mikrofon zwolniony); trwającej transkrypcji nie rusza.
    func stop() {
        active = false
        monitor.stop()
        monitorRunning = false
        engine.apply(.cancel)
    }

    /// Po każdej zmianie ustawień dyktowania i po nadaniu uprawnienia.
    func applySettings() {
        let s = model.settings.dictationOrDefault
        monitor.configure(hotkey: s.hotkeyOrDefault, mode: s.triggerModeOrDefault)
        // `configure` buduje nową maszynę: trwająca sesja toggle musi dalej kończyć się naciśnięciem.
        monitor.setListening(engine.phase == .listening)
        refreshPermissions()
        guard active else { return }
        if permissions.inputMonitoring {
            monitorRunning = monitor.start()
        } else {
            monitor.stop()
            monitorRunning = false
        }
    }

    func refreshPermissions() {
        let now = (inputMonitoring: monitor.permissionGranted, accessibility: AXIsProcessTrusted(),
                   microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        if now != permissions { permissions = now }
    }

    func requestInputMonitoring() {
        monitor.requestPermission()
        refreshPermissions()
    }

    func requestAccessibility() {
        // Systemowe okno z przyciskiem do Ustawień; zgodę nadaje użytkownik.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshPermissions()
    }

    /// Obserwacja `engine.phase` z ponownym uzbrajaniem: sesja kończona przez silnik (auto-stop, awaria, odmowa) gasi
    /// „słucham” w maszynie skrótu, inaczej następne naciśnięcie w trybie toggle byłoby martwym `.stop`.
    private func trackPhase() {
        guard active else { return }
        let phase = withObservationTracking { engine.phase } onChange: { [weak self] in
            // `onChange` przychodzi przed zmianą: stan czytamy świeżo w kolejnym obrocie.
            Task { @MainActor in self?.trackPhase() }
        }
        monitor.setListening(phase == .listening)
        refreshPermissions()
    }

    // MARK: Start

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .start:
            if admit() { engine.apply(.start) } else { monitor.setListening(false) }
        case .stop, .cancel:
            engine.apply(action)
        }
    }

    /// Przycisk pastylki (Task 9).
    func toggleFromLauncher() {
        if engine.phase != .listening, !admit() { return }
        engine.toggleFromLauncher()
        // Od razu, nie dopiero z obserwacji: naciśnięcie skrótu tuż po kliknięciu ma zakończyć tę sesję.
        monitor.setListening(engine.phase == .listening)
    }

    /// `false` = odmowa już pokazana (dźwięk albo pastylka).
    private func admit() -> Bool {
        switch DictationGate.canStartDictation(isRecordingMeeting: model.recording.isRecording, isBusy: engine.isBusy) {
        case .failure(.recordingMeeting):
            NSSound.beep()   // pastylka jest ukryta w trakcie nagrania spotkania
            return false
        case .failure(let refusal):
            engine.refuse(refusal.message)
            return false
        case .success:
            break
        }
        guard language != nil else {
            engine.refuse(Self.missingLanguageMessage)
            return false
        }
        return true
    }

    /// Jawny język dyktowania, inaczej język aktywnego presetu (preset „Auto" ma `nil`, więc Auto nie przechodzi).
    private var language: LanguageCode? { model.settings.dictationOrDefault.language ?? model.activePreset?.language }

    // MARK: Wejście potoku

    /// Wołane z `[]` przy starcie tylko po to, by sprawdzić model: wtedy bez Keychain, sieci i ładowania modeli.
    private func buildInput(_ pcm: [Int16]) -> (input: DictationPipelineInput, meta: DictationRecordMeta)? {
        let s = model.settings.dictationOrDefault
        guard let asr = s.asr, let provider = model.provider(asr.providerID) else { return nil }
        let correction = s.correctionEnabled ? s.correction?.model : nil
        let meta = DictationRecordMeta(asrModel: asr.model, correctionModel: correction?.model)
        let language = language
        let shape = model.probeCache.result(provider: asr.providerID, model: asr.model, role: .asr, language: language)?.shape
            ?? .audioTranscriptions
        let fillers = model.settings.removeFillersEnabled ? (model.settings.fillerWords ?? FillerWords.defaults) : nil
        guard !pcm.isEmpty else {
            // Wejście sondy jest odrzucane; klient bez klucza nigdy nie wysyła żądania.
            return (DictationPipelineInput(pcm: [], language: language, asrModel: asr.model,
                                           transcriber: OpenAICompatibleClient(provider: provider, key: nil), shape: shape, chat: nil,
                                           vocabulary: PromptVocabulary(), removeFillers: fillers, replacement: model.replacementRules), meta)
        }
        guard let client = model.transcriptionClient(for: asr.providerID) else { return nil }   // powód w `lastError`
        let support = model.localASR
        let transcriber: any TranscriptionClient = client is ReleasableClient
            ? ReleasingTranscriber(inner: client) { await MainActor.run { support.endRun() } } : client

        var chat: ChatFunction?
        var vocabulary = PromptVocabulary()
        if let correction {
            switch model.makeClient(for: correction.providerID) {
            case .success(let c):
                let budget = ContextBudget.resolve(provider: c.provider, detected: nil)
                vocabulary = DictionaryPrompt.make(model.dictionary, link: nil, maxChars: DictionaryPrompt.maxChars(budget: budget))
                let id = correction.model
                chat = { system, user in try await c.chat(model: id, system: system, user: user, thinking: false) }
            case .failure(let problem):
                // Korekta niedostępna = nieudana korekta: wstawiamy surowy tekst, wpis z `correctionFailed`.
                chat = { _, _ in throw problem }
            }
        }
        return (DictationPipelineInput(pcm: pcm, language: language, asrModel: asr.model, transcriber: transcriber, shape: shape,
                                       chat: chat, vocabulary: vocabulary, removeFillers: fillers,
                                       replacement: model.replacementRules), meta)
    }

    // MARK: Historia

    /// Wzorzec `AppModel.load()`: nieczytelny plik odkładamy obok jako `…corrupt-<data>`; błąd do `errors`.
    func loadHistory(stamp: String, errors: inout [String]) {
        let url = model.paths.dictationHistory
        do {
            history = try JSONFile.load(DictationHistoryFile.self, from: url, default: DictationHistoryFile())
            historyLocked = false
        } catch {
            history = DictationHistoryFile()
            let name = url.lastPathComponent
            let aside = url.deletingLastPathComponent().appendingPathComponent("\(name).corrupt-\(stamp)")
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            historyLocked = !moved
            errors.append("Couldn't read \(name) (\(moved ? "moved to \(aside.lastPathComponent)" : "couldn't move it aside")): \(error)")
        }
    }

    private func record(_ entry: DictationEntry) {
        history.add(entry)
        saveHistory()
    }

    func deleteEntry(_ id: UUID) {
        history.remove(id)
        saveHistory()
    }

    func clearHistory() {
        history.clear()
        saveHistory()
    }

    func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func saveHistory() {
        let name = model.paths.dictationHistory.lastPathComponent
        guard !historyLocked else {
            model.lastError = "Couldn't save dictation history: \(name) couldn't be read, so it is left untouched."
            return
        }
        do { try JSONFile.save(history, to: model.paths.dictationHistory) } catch {
            model.lastError = "Couldn't save dictation history: \(error)"
        }
    }
}

/// Lokalny ASR trzyma model w pamięci do `release()` (jak po przebiegu spotkania): zwalniamy po każdej transkrypcji.
private struct ReleasingTranscriber: TranscriptionClient {
    let inner: any TranscriptionClient
    let ended: @Sendable () async -> Void
    var provider: Provider { inner.provider }

    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        let result: Result<TranscriptionResult, any Error>
        do { result = .success(try await inner.transcribe(wav: wav, model: model, language: language, shape: shape)) }
        catch { result = .failure(error) }
        await (inner as? any ReleasableClient)?.release()
        await ended()
        return try result.get()
    }
}
