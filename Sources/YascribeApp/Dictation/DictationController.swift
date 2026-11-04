import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation
import YascribeDictation
import YascribeLocalASR
import YascribeNotes
import YascribeProviders
import YascribeTranscription

/// Spina dyktowanie z aplikacją: skrót globalny, silnik, historia i ustawienia z `AppModel`.
/// `init` bez wejścia-wyjścia i bez okien zgody: tworzy go `AppModel.load()` także w migawkach.
@MainActor @Observable final class DictationController {
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let capture = MicCapture()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored lazy var engine = DictationEngine(capture: capture, inserter: inserter,
                                                          buildInput: { [weak self] in self?.buildInput($0) },
                                                          record: { [weak self] in self?.record($0) })
    @ObservationIgnored private lazy var monitor = GlobalHotkeyMonitor { [weak self] in self?.handle($0) }
    /// Panel powstaje dopiero przy pierwszym pokazaniu (po `start()`), więc migawki go nie tworzą.
    @ObservationIgnored private lazy var launcher = LauncherPanelController(controller: self, model: model)

    private(set) var history = DictationHistoryFile()
    private(set) var permissions: (inputMonitoring: Bool, accessibility: Bool, microphone: Bool) = (false, false, false)
    private(set) var monitorRunning = false
    /// `start()` był wołany, a `stop()` jeszcze nie (migawki i testy kontrolera nie startują).
    @ObservationIgnored private var active = false
    /// Plik historii nie dał się odczytać ani odłożyć: zapis by go nadpisał.
    @ObservationIgnored private var historyLocked = false
    /// Pokolenie pętli obserwacji: `stop()` + `start()` przed odpaleniem starego `onChange` nie zostawia dwóch łańcuchów.
    @ObservationIgnored private var trackGeneration = 0

    init(model: AppModel) { self.model = model }

    /// Poziom mikrofonu 0…1 dla pastylki (odczyt pod zamkiem; nieobserwowany, UI odpytuje).
    var level: Float { capture.level }

    // MARK: Cykl życia

    func start() {
        guard !active else { return }
        active = true
        trackGeneration += 1
        applySettings()
        trackPhase(trackGeneration)
    }

    /// Zamknięcie aplikacji: tap off, nagrywanie przerwane (mikrofon zwolniony); trwającej transkrypcji nie rusza.
    func stop() {
        active = false
        monitor.stop()
        monitorRunning = false
        engine.apply(.cancel)
        launcher.hide()
    }

    /// Po każdej zmianie ustawień dyktowania i po nadaniu uprawnienia.
    func applySettings() {
        let s = model.settings.dictationOrDefault
        monitor.configure(hotkey: s.hotkeyOrDefault, mode: s.triggerModeOrDefault)
        // `configure` buduje nową maszynę: trwająca sesja toggle musi dalej kończyć się naciśnięciem.
        monitor.setListening(engine.phase == .listening)
        refreshPermissions()
        guard active else { return }
        if s.showLauncherOrDefault { launcher.show() } else { launcher.hide() }
        if permissions.inputMonitoring {
            monitorRunning = monitor.start()
        } else {
            monitor.stop()
            monitorRunning = false
        }
    }

    /// Pole skrótu w Settings przechwytuje klawisze: tap nie może wtedy uruchamiać dyktowania (ani trwająca sesja trwać).
    func setCapturingHotkey(_ on: Bool) {
        if on { engine.apply(.cancel) }
        monitor.setCapturing(on)
        monitor.setListening(engine.phase == .listening)
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
    private func trackPhase(_ generation: Int) {
        guard active, generation == trackGeneration else { return }
        let phase = withObservationTracking { engine.phase } onChange: { [weak self] in
            // `onChange` przychodzi przed zmianą: stan czytamy świeżo w kolejnym obrocie.
            Task { @MainActor in self?.trackPhase(generation) }
        }
        monitor.setListening(phase == .listening)
        refreshPermissions()
    }

    // MARK: Start

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .start:
            if admit() {
                engine.apply(.start)
            } else if !engine.isBusy {
                monitor.setListening(false)   // odmowa: maszyna myśli, że słucha; przy trwającej sesji nie ruszamy jej
            }
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

    /// `false` = nie startujemy (odmowa już pokazana albo sesja trwa).
    private func admit() -> Bool {
        switch HotkeyStartDecision.decide(phase: engine.phase, isRecordingMeeting: model.recording.isRecording,
                                          languageAvailable: language != nil) {
        case .start: return true
        case .ignore: return false
        case .beep: NSSound.beep(); return false
        case .refuse(let message): engine.refuse(message); return false
        }
    }

    /// Jawny język dyktowania, inaczej język aktywnego presetu (preset „Auto" ma `nil`, więc Auto nie przechodzi).
    private var language: LanguageCode? { model.settings.dictationOrDefault.language ?? model.activePreset?.language }

    // MARK: Wejście potoku

    /// Wołane z `[]` przy starcie tylko po to, by sprawdzić model: wtedy bez Keychain, sieci i ładowania modeli.
    private func buildInput(_ pcm: [Int16]) -> (input: DictationPipelineInput, meta: DictationRecordMeta)? {
        let s = model.settings.dictationOrDefault
        // Model Yascribe (Parakeet) ma jedną pozycję na liście: wybrany dostawca bez nazwy modelu znaczy właśnie ją.
        let onDevice = s.asr.flatMap { a in
            model.provider(a.providerID)?.api == .fluidAudio ? RoleAssignment(providerID: a.providerID, model: LocalASRModels.parakeetV3) : nil
        }
        guard let asr = s.usableASR ?? onDevice, let provider = model.provider(asr.providerID) else { return nil }
        // Brak lokalnego modelu: odmowa przy starcie, a nie po wypowiedzi (sam odczyt magazynu, bez ładowania).
        if provider.api == .fluidAudio, RunGate.check(status: model.localASR.store.status()) != nil { return nil }
        let correction = s.usableCorrection
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
        // Brak klienta przy `.stop` (klucz, model): nagranie jest już zrobione, więc nie odmawiamy po cichu ani nie
        // wyświetlamy alertu — transkrypcja zgłasza powód i silnik przechodzi w `.failed` z „Retry".
        let errorBefore = model.lastError
        guard let client = model.transcriptionClient(for: asr.providerID) else {
            let reason = model.lastError ?? "Couldn't start transcription."
            model.lastError = errorBefore
            return (DictationPipelineInput(pcm: pcm, language: language, asrModel: asr.model,
                                           transcriber: UnavailableTranscriber(provider: provider, reason: reason), shape: shape,
                                           chat: nil, vocabulary: PromptVocabulary(), removeFillers: fillers,
                                           replacement: model.replacementRules), meta)
        }
        let transcriber: any TranscriptionClient = client is any ReleasableClient
            ? ReleasingTranscriber(inner: client, support: model.localASR) : client

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
/// `beginRun`/`endRun` w tym samym zakresie: póki trwa, model nie da się usunąć.
private struct ReleasingTranscriber: TranscriptionClient {
    let inner: any TranscriptionClient
    let support: LocalASRSupport
    var provider: Provider { inner.provider }

    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        await support.beginRun()
        let result: Result<TranscriptionResult, any Error>
        do { result = .success(try await inner.transcribe(wav: wav, model: model, language: language, shape: shape)) }
        catch { result = .failure(error) }
        await (inner as? any ReleasableClient)?.release()
        await support.endRun()
        return try result.get()
    }
}

/// Klient, którego nie dało się zbudować przy `.stop`: każda transkrypcja kończy się prawdziwym powodem.
private struct UnavailableTranscriber: TranscriptionClient {
    struct Unavailable: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    let provider: Provider
    let reason: String

    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        throw Unavailable(reason: reason)
    }
}
