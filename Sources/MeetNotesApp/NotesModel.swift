import Foundation
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesTranscription
import Observation

/// Generowanie notatek, korekta, autotytuł i autozapis My notes (spec 1.5 §4.1). Logika w `MeetNotesNotes`;
/// ten model tylko spina ją z interfejsem i trzyma stan „w toku".
@MainActor
@Observable
final class NotesModel {
    enum GenState: Equatable {
        case idle
        case generating
        case failed(String)
    }

    /// Klucz: id sesji (nazwa katalogu).
    var generation: [String: GenState] = [:]
    /// Bieżący krok generowania (klucz: id sesji) — „Condensing part 2 of 6 (pass 1)…"; `nil` poza generowaniem.
    private(set) var progress: [String: NoteProgress] = [:]
    private(set) var correcting: Set<String> = []
    private(set) var titling: Set<String> = []
    /// Powód ostatniego nieudanego przebiegu korekty (klucz: id sesji). Znika po udanym ponowieniu.
    private(set) var correctionFailure: [String: String] = [:]
    var templates = TemplatesFile()

    /// Podłączane przez `AppModel` (bez cyklu własności).
    var clientFor: (UUID) -> OpenAICompatibleClient? = { _ in nil }
    var presetFor: (URL) -> Preset? = { _ in nil }
    var presetsInfo: () -> (presets: [Preset], defaultID: UUID?) = { ([], nil) }
    /// `GlobalSettings.summaryThinkingEnabled`: czy model API może „myśleć" przy notatce.
    var summaryThinking: () -> Bool = { true }
    /// Przerywniki do usunięcia z poprawionego tekstu (F20 P2); pusta lista = nic nie usuwamy.
    var fillerWords: () -> [String] = { [] }
    var onChange: () -> Void = {}
    /// Komunikaty dla użytkownika (np. nieczytelny plik notatek odłożony na bok) — podłączane do `AppModel.lastError`.
    var report: (String) -> Void = { _ in }
    /// Trwa przenoszenie folderu nagrań — widok spotkania jest tylko do odczytu, zapisy blokujemy też tutaj (R3),
    /// żeby skrót z menu nie obszedł interfejsu. Zapis po usunięciu starego miejsca odtworzyłby osierocony katalog.
    var isMoving: () -> Bool = { false }
    private static let movingMessage = "Meetings are being moved to a new folder. Try again when that finishes."

    /// Trwające generowanie (klucz: id sesji); token odróżnia przebieg anulowany od nowego na tej samej sesji.
    private var generationRuns: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]
    /// Treść My notes czekająca na autozapis (klucz: id sesji).
    private var pendingSaves: [String: (session: URL, text: String)] = [:]

    func state(_ id: String) -> GenState { generation[id] ?? .idle }

    /// Model podsumowania dla tego nagrania: z jego presetu, a gdy go tam nie ma — z presetu domyślnego (patrz `SummaryModel`).
    func summaryChoice(for item: SessionItem) -> SummaryChoice? {
        let info = presetsInfo()
        return SummaryModel.resolve(frozen: presetFor(item.url), defaultPresetID: info.defaultID, presets: info.presets)
    }

    func isCorrecting(_ id: String) -> Bool { correcting.contains(id) }
    func isTitling(_ id: String) -> Bool { titling.contains(id) }
    func correctionFailureMessage(_ id: String) -> String? { correctionFailure[id] }

    /// „Improve transcript"/Retry: preset nagrania ma model korekty, jest transkrypt i nic nie trwa, a korekta
    /// albo padła (całkiem lub z częścią partii: „N parts kept as heard”), albo jej nie ma (np. aplikacja zamknięta w trakcie).
    func canRetryCorrection(_ item: SessionItem) -> Bool {
        guard !correcting.contains(item.id), state(item.id) != .generating, item.transcript != nil, item.runID != nil else { return false }
        guard let c = presetFor(item.url)?.correction, !c.model.isEmpty else { return false }
        return correctionFailure[item.id] != nil || item.corrected == nil || (item.corrected?.failedBatches ?? 0) > 0
    }

    func retryCorrection(_ item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        guard canRetryCorrection(item), let preset = presetFor(item.url), let c = preset.correction,
              let runID = item.runID, let t = item.transcript else { return }
        let url = item.url
        Task { _ = await runCorrection(sessionURL: url, runID: runID, assignment: c, language: preset.language, transcript: t) }
    }

    /// Jedna korekta; stan ZAWSZE się kończy: sukces (corrected.json), albo `correctionFailure` z powodem.
    private func runCorrection(sessionURL: URL, runID: String, assignment: RoleAssignment, language: LanguageCode?,
                               transcript: Transcript) async -> Transcript {
        let id = sessionURL.lastPathComponent
        guard !assignment.model.isEmpty, let client = clientFor(assignment.providerID) else {
            correctionFailure[id] = "Couldn't reach the correction provider. Check Settings."
            onChange()
            return transcript
        }
        correctionFailure[id] = nil
        correcting.insert(id)
        onChange()
        let limits = ChatLimits.for(client.provider, call: .correctionBatch)
        // Kontekst lokalnego serwera sprawdzamy w chwili użycia (`/api/ps` zna tylko model załadowany); API: bez budżetu.
        let budget = client.provider.isLocal
            ? ContextBudget.resolve(provider: client.provider, detected: await ContextProbe.detect(client: client, model: assignment.model)) : nil
        let result = await Corrector(client: client, assignment: assignment, batchTimeout: limits.soft, chatTimeout: limits.transport,
                                     temperature: limits.temperature, budget: budget, fillerWords: fillerWords())
            .correct(transcript, language: language)
        correcting.remove(id)
        defer { onChange() }
        if result.failedCompletely {
            correctionFailure[id] = result.firstError ?? "The correction didn't go through."
            return transcript
        }
        if result.batches > 0 {
            try? JSONFile.save(result, to: RunDirectory(session: sessionURL, runID: runID).corrected)
            return result.transcript
        }
        return transcript
    }

    // MARK: Notatka na żądanie

    func generate(item: SessionItem, useCorrected: Bool, template: Template, context: String) {
        let id = item.id
        guard !isMoving() else { report(Self.movingMessage); return }
        guard state(id) != .generating else { return }
        // Jeden lokalny serwer obsługuje żądania po kolei: czekanie za korektą liczyłoby się do limitu części („didn't answer").
        guard !correcting.contains(id) else { return }
        guard let transcript = item.transcript(corrected: useCorrected) else {
            generation[id] = .failed("This meeting has no transcript yet.")
            return
        }
        guard let choice = summaryChoice(for: item) else {
            generation[id] = .failed("No preset has a summary model. Choose one in Presets.")
            return
        }
        guard let client = clientFor(choice.assignment.providerID) else {
            generation[id] = .failed("Couldn't reach the summary provider. Check Settings.")
            return
        }
        generation[id] = .generating
        let limits = ChatLimits.for(client.provider, call: .note)
        var generator = NoteGenerator(client: client, model: choice.assignment.model, timeout: limits.soft,
                                      chatTimeout: limits.transport, maxTokens: limits.maxTokens)
        generator.thinking = summaryThinking()
        // Język notatki z presetu NAGRANIA (jego język i „Notes language"), także gdy model pochodzi z innego presetu.
        let language = presetFor(item.url)?.effectiveNotesLanguage
        let session = item.url
        let token = UUID()
        let task = Task {
            do {
                // Lokalny serwer: kontekst sprawdzamy w chwili użycia (`/api/ps` zna tylko model załadowany); budżet włącza map-reduce.
                // API nie dostaje budżetu, więc nigdy nie dzieli transkryptu.
                let budget = client.provider.isLocal
                    ? ContextBudget.resolve(provider: client.provider, detected: await ContextProbe.detect(client: client, model: choice.assignment.model)) : nil
                _ = try await generator.generate(session: session, template: template, transcript: transcript,
                                                 context: context, notesLanguage: language, budget: budget,
                                                 onProblem: { [weak self] msg in Task { @MainActor in self?.report(msg) } },
                                                 progress: { [weak self] p in
                                                     Task { @MainActor in if self?.generationRuns[id]?.token == token { self?.progress[id] = p } }
                                                 })
                try Task.checkCancellation()
                self.finishGeneration(id, token, .idle)
            } catch is CancellationError {
                self.finishGeneration(id, token, .idle) // anulowane: bez baneru błędu, żadnej notatki na dysku
            } catch NoteGenerationError.nothingToSummarize {
                self.finishGeneration(id, token, .failed("Nothing to summarize: the transcript has no usable text."))
            } catch NoteGenerationError.failed(let message) {
                self.finishGeneration(id, token, .failed(message))
            } catch {
                self.finishGeneration(id, token, .failed("\(error)"))
            }
        }
        generationRuns[id] = (token, task)
    }

    /// Tylko migawki (`Snapshots.swift`): stan „w toku" bez uruchamiania pracy. Bez argumentów czyści stan.
    func setPreview(_ id: String, generating: NoteProgress? = nil, correcting isCorrecting: Bool = false) {
        generation[id] = generating == nil ? nil : .generating
        progress[id] = generating
        if isCorrecting { correcting.insert(id) } else { correcting.remove(id) }
    }

    /// „Cancel" przy generowaniu: zatrzymuje kolejne wywołania serwera i od razu zwalnia sesję (bez błędu, bez notatki).
    func cancelGeneration(_ id: String) {
        guard let run = generationRuns.removeValue(forKey: id) else { return }
        run.task.cancel()
        generation[id] = .idle
        progress[id] = nil
        onChange()
    }

    /// Kończy przebieg, o ile nie został anulowany (wtedy stan już ustawił `cancelGeneration`, a nowy przebieg może trwać).
    private func finishGeneration(_ id: String, _ token: UUID, _ result: GenState) {
        if generationRuns[id]?.token == token {
            generationRuns[id] = nil
            progress[id] = nil
            generation[id] = result
        }
        onChange()
    }

    // MARK: Po transkrypcji: korekta (gdy preset ma model) i autotytuł (gdy ma model podsumowania)

    func afterTranscription(sessionURL: URL, runID: String, snapshot: RunSnapshot, transcript: Transcript) async {
        let id = sessionURL.lastPathComponent
        var working = transcript
        if let corr = snapshot.preset.correction, !corr.model.isEmpty {
            working = await runCorrection(sessionURL: sessionURL, runID: runID, assignment: corr,
                                          language: snapshot.language, transcript: transcript)
        }
        // Ten sam wybór modelu co przy „Generate notes": preset nagrania → domyślny → dowolny z `summary` (`SummaryModel`).
        let info = presetsInfo()
        if let choice = SummaryModel.resolve(frozen: snapshot.preset, defaultPresetID: info.defaultID, presets: info.presets),
           let client = clientFor(choice.assignment.providerID) {
            titling.insert(id)
            onChange()
            let limits = ChatLimits.for(client.provider, call: .title)
            _ = await AutoTitle.generate(client: client, model: choice.assignment.model, transcript: working,
                                         notesLanguage: snapshot.preset.effectiveNotesLanguage,
                                         store: NotesStore(session: sessionURL), timeout: limits.soft, chatTimeout: limits.transport,
                                         maxTokens: limits.maxTokens, onProblem: { [weak self] msg in Task { @MainActor in self?.report(msg) } })
            titling.remove(id)
            onChange()
        }
    }

    // MARK: My notes i tytuł

    /// Autozapis z opóźnieniem: ostatnia zmiana wygrywa, zapis 0,6 s po ostatnim znaku.
    func saveMyNotes(_ text: String, for item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        let id = item.id
        pendingSaves[id] = (item.url, text)
        saveTasks[id]?.cancel()
        saveTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self.writePending(id)
        }
    }

    /// Zapisuje od razu wszystko, co czeka na autozapis — przed przenoszeniem folderu nagrań.
    func flushPendingSaves() {
        for (id, task) in saveTasks { task.cancel(); writePending(id) }
        saveTasks = [:]
    }

    private func writePending(_ id: String) {
        guard let p = pendingSaves.removeValue(forKey: id) else { return }
        guard !isMoving() else { report("Couldn't save your notes: \(Self.movingMessage)"); return }
        do {
            if let note = try NotesStore(session: p.session).writeMyNotes(p.text) { report(note) }
        } catch {
            report("Couldn't save your notes: \(error)")
        }
    }

    func setManualTitle(_ title: String, for item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let note = try NotesStore(session: item.url).updateMeta({ $0.manualTitle = t.isEmpty ? nil : t }) { report(note) }
        } catch {
            report("Couldn't save the title: \(error)")
        }
        onChange()
    }
}
