import Foundation
import YascribeNotes
import YascribeProviders
import YascribeTranscription
import Observation

/// Generowanie notatek, korekta, autotytuł i autozapis My notes (spec 1.5 §4.1). Logika w `YascribeNotes`;
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
    /// Wszystkie trwające korekty i autotytuły, każdy z biletem (F2, F3): sesja zajęta, dopóki trwa którykolwiek; komunikat
    /// i wynik należą do najnowszego (`RunOperations`).
    private(set) var corrections = RunOperations()
    private(set) var titles = RunOperations()
    /// Powód ostatniego nieudanego przebiegu korekty (klucz: id sesji). Znika po udanym ponowieniu.
    private(set) var correctionFailure: [String: String] = [:]
    private(set) var overviewFailure: Set<String> = []
    var templates = TemplatesFile()

    /// Podłączane przez `AppModel` (bez cyklu własności).
    var clientFor: (UUID) -> OpenAICompatibleClient? = { _ in nil }
    var presetFor: (URL) -> Preset? = { _ in nil }
    var presetsInfo: () -> (presets: [Preset], defaultID: UUID?) = { ([], nil) }
    /// Dostawcy, którzy jeszcze istnieją; nadpisanie wskazujące innego jest nieważne (faza 2.0.1).
    var knownProviderIDs: () -> Set<UUID> = { [] }
    /// `GlobalSettings.summaryThinkingEnabled`: czy model API może „myśleć" przy notatce.
    var summaryThinking: () -> Bool = { true }
    /// Przerywniki do usunięcia z poprawionego tekstu (F20 P2); pusta lista = nic nie usuwamy.
    var fillerWords: () -> [String] = { [] }
    /// Słownik użytkownika i jego reguły Replacement (F21); przebieg czyta je razem, przed pierwszym `await`.
    var dictionary: () -> UserDictionary = { UserDictionary() }
    var replacementRules: () -> ReplacementRules = { ReplacementRules(UserDictionary()) }
    var onChange: () -> Void = {}
    /// Komunikaty dla użytkownika (np. nieczytelny plik notatek odłożony na bok) — podłączane do `AppModel.lastError`.
    var report: (String) -> Void = { _ in }
    /// Trwa przenoszenie folderu nagrań — widok spotkania jest tylko do odczytu, zapisy blokujemy też tutaj (R3),
    /// żeby skrót z menu nie obszedł interfejsu. Zapis po usunięciu starego miejsca odtworzyłby osierocony katalog.
    var isMoving: () -> Bool = { false }
    private static let movingMessage = "Meetings are being moved to a new folder. Try again when that finishes."

    /// Trwające generowanie (klucz: id sesji); token odróżnia przebieg anulowany od nowego na tej samej sesji.
    private var generationRuns: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    /// Bilety realnie działających zadań (id sesji → tokeny). Wpis zostaje do faktycznego końca zadania, także po
    /// „Cancel" — dopóki zadanie może jeszcze zapisać notatkę, sesja jest zajęta (TASK-25: usunięcie w tym oknie
    /// przeniosłoby katalog, a późny zapis by go odtworzył). Zbiór na sesję, bo po Cancel może wystartować nowe zadanie.
    private var inflight: [String: Set<UUID>] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var staleReported: Set<String> = []
    /// Treść My notes czekająca na autozapis (klucz: id sesji).
    private var pendingSaves: [String: (session: URL, text: String)] = [:]

    /// Sesje z zadaniem generowania, które jeszcze się nie zakończyło (także anulowane w trakcie).
    var generatingSessions: Set<String> { Set(inflight.keys) }

    private func startTicket(_ id: String, _ token: UUID) { inflight[id, default: []].insert(token) }

    /// Zdejmuje tylko własny bilet: starsze zakończenie nie zwalnia nowszego zadania tej samej sesji.
    private func endTicket(_ id: String, _ token: UUID) {
        inflight[id]?.remove(token)
        if inflight[id]?.isEmpty == true { inflight[id] = nil }
    }

    /// Zapis notatek spotkania w trybie ścisłym: brak katalogu sesji = odmowa, nie odtworzenie (TASK-25).
    private func store(_ session: URL) -> NotesStore { NotesStore(session: session, requiresExistingSession: true) }

    /// Jest treść czekająca na autozapis (klucz: id sesji).
    func hasPendingNotes(_ id: String) -> Bool { pendingSaves[id] != nil }

    func state(_ id: String) -> GenState { generation[id] ?? .idle }

    /// Model podsumowania dla tego nagrania: z jego presetu, a gdy go tam nie ma — z presetu domyślnego (patrz `SummaryModel`).
    func summaryChoice(for item: SessionItem) -> SummaryChoice? {
        let info = presetsInfo()
        return SummaryModel.resolve(frozen: presetFor(item.url), override: usableOverride(.summary, for: item),
                                    defaultPresetID: info.defaultID, presets: info.presets)
    }

    /// To samo bez nadpisania: model, do którego wraca „Use preset".
    func presetSummaryChoice(for item: SessionItem) -> SummaryChoice? {
        let info = presetsInfo()
        return SummaryModel.resolve(frozen: presetFor(item.url), defaultPresetID: info.defaultID, presets: info.presets)
    }

    func presetCorrection(for item: SessionItem) -> RoleAssignment? {
        CorrectionModel.resolve(frozen: presetFor(item.url), override: nil)
    }

    func correctionAssignment(for item: SessionItem) -> RoleAssignment? {
        CorrectionModel.resolve(frozen: presetFor(item.url), override: usableOverride(.correction, for: item))
    }

    func overrides(for item: SessionItem) -> ModelOverrides { item.notes.meta.modelOverrides ?? ModelOverrides() }

    private func usableOverride(_ role: Role, for item: SessionItem) -> RoleOverride? {
        overrides(for: item).usable(role, knownProviders: knownProviderIDs())
    }

    /// Zapisane nadpisanie jest, ale nie działa (np. dostawca usunięty): wracamy do presetu i mówimy o tym.
    private func reportStaleOverride(_ role: Role, for item: SessionItem) {
        guard overrides(for: item).isStale(role, knownProviders: knownProviderIDs()),
              staleReported.insert("\(item.id)/\(role.rawValue)").inserted else { return } // raz na uruchomienie, nie przy każdym przebiegu
        report("The model you chose for this meeting is no longer available. Using the preset's.")
    }

    /// Zapisuje wybór modelu przy sesji (`nil` = wróć do presetu). Niczego nie uruchamia; trwające przebiegi zostają przy modelu z chwili startu.
    func setOverride(_ role: Role, _ value: RoleOverride?, item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        do {
            if let note = try store(item.url).updateMeta({ $0.setOverride(role, value) }) { report(note) }
        } catch {
            report("Couldn't save the model choice: \(error)")
        }
        onChange()
    }

    func isCorrecting(_ id: String) -> Bool { corrections.isActive(id) }
    func isTitling(_ id: String) -> Bool { titles.isActive(id) }
    func correctionFailureMessage(_ id: String) -> String? { correctionFailure[id] }

    /// „Improve transcript"/Retry: preset nagrania ma model korekty, jest transkrypt i nic nie trwa, a korekta
    /// albo padła (całkiem lub z częścią partii: „N parts kept as heard”), albo jej nie ma (np. aplikacja zamknięta w trakcie).
    func canRetryCorrection(_ item: SessionItem) -> Bool {
        // Bez wypowiedzi (np. wszystkie okna padły offline) nie ma czego poprawiać: przycisk nic by nie zrobił; wtedy jest „Retry Failed Parts”.
        guard !isCorrecting(item.id), state(item.id) != .generating, item.runID != nil,
              let transcript = item.transcript, !transcript.utterances.isEmpty else { return false }
        guard correctionAssignment(for: item) != nil else { return false }
        // Własny model korekty pozwala puścić ją jeszcze raz także po udanej, żeby porównać modele (nadpisuje corrected.json).
        return usableOverride(.correction, for: item) != nil || correctionFailure[item.id] != nil
            || item.corrected == nil || (item.corrected?.failedBatches ?? 0) > 0
    }

    func retryCorrection(_ item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        guard canRetryCorrection(item), let c = correctionAssignment(for: item),
              let runID = item.runID, let t = item.transcript else { return }
        reportStaleOverride(.correction, for: item)
        let url = item.url
        // Język przebiegu, który się poprawia (I2): po „Transcribe again…" inny niż w `preset.json` sesji.
        let language = RunLanguage.of(item.runSnapshot, fallback: presetFor(url)).language
        Task { _ = await runCorrection(sessionURL: url, runID: runID, assignment: c, language: language, transcript: t) }
    }

    /// Jedna korekta; stan ZAWSZE się kończy: sukces (corrected.json), albo `correctionFailure` z powodem.
    private func runCorrection(sessionURL: URL, runID: String, assignment: RoleAssignment, language: LanguageCode?,
                               transcript: Transcript) async -> Transcript {
        let id = sessionURL.lastPathComponent
        // Bilet od pierwszej linii, przed każdym wczesnym wyjściem: inaczej starsza korekta, kończąc się, nadpisałaby
        // porażkę nowszej, która padła bez klienta (fix round 2).
        let ticket = corrections.start(session: id, runID: runID)
        guard !assignment.model.isEmpty, let client = clientFor(assignment.providerID) else {
            if corrections.finish(ticket).ownsMessage {
                correctionFailure[id] = "Couldn't reach the correction provider. Check Settings."
            }
            onChange()
            return transcript
        }
        // Słownik, reguły i uczestnicy z jednej chwili, przed pierwszym `await`: edycja słownika w trakcie sondy kontekstu
        // nie miesza wersji wejścia i polecenia. Uczestnicy z `meta.json` teraz, więc późne powiązanie wydarzenia też się liczy.
        let dict = dictionary(), rules = replacementRules()
        let link = store(sessionURL).readMeta().calendarEvent
        let input = Replacement.apply(transcript, rules: rules)
        correctionFailure[id] = nil
        onChange()
        let limits = ChatLimits.for(client.provider, call: .correctionBatch)
        // Kontekst lokalnego serwera sprawdzamy w chwili użycia (`/api/ps` zna tylko model załadowany); API: bez budżetu.
        let budget = client.provider.isLocal
            ? ContextBudget.resolve(provider: client.provider, detected: await ContextProbe.detect(client: client, model: assignment.model)) : nil
        let vocabulary = DictionaryPrompt.make(dict, link: link, maxChars: DictionaryPrompt.maxChars(budget: budget))
        let used = vocabulary.isEmpty ? nil : vocabulary
        let result = await Corrector(client: client, assignment: assignment, batchTimeout: limits.soft, chatTimeout: limits.transport,
                                     temperature: limits.temperature, budget: budget, fillerWords: fillerWords(), vocabulary: used)
            .correct(input, language: language)
        // Komunikat należy do najnowszej korekty sesji, wynik — do najnowszej korekty tego przebiegu (F2): starsza, kończąc się
        // później, nie nadpisuje `corrected.json` ani śladu nowszej. Sprawdzenie i zapis bez `await` pomiędzy.
        let outcome = corrections.finish(ticket)
        defer { onChange() }
        if result.failedCompletely {
            if outcome.ownsMessage { correctionFailure[id] = result.firstError ?? "The correction didn't go through." }
            return transcript
        }
        if result.batches > 0, outcome.mayPublish {
            let run = RunDirectory(session: sessionURL, runID: runID)
            // Katalogu spotkania, którego już nie ma, nie odtwarzamy późnym zapisem (TASK-25): także sam zapis
            // nie tworzy rodziców, więc usunięcie w trakcie korekty kończy się porażką zapisu, nie nową sesją.
            guard FileManager.default.fileExists(atPath: sessionURL.path) else { return transcript }
            let saved = (try? JSONFile.save(result, to: run.corrected, createParents: false)) != nil
            // Ślad do odbioru §8.4 tylko po zapisanej korekcie (R18): stary ślad obok nowego `corrected.json` kłamałby.
            if let error = VocabularyTrace.update(promptLines: used?.promptLines, at: run.url.appendingPathComponent("vocabulary.txt"),
                                                  correctionSaved: saved) {
                report("Couldn't save the vocabulary trace: \(error)")
            }
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
        guard !isCorrecting(id) else { return }
        guard let source = item.transcript(corrected: useCorrected) else {
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
        reportStaleOverride(.summary, for: item)
        generation[id] = .generating
        let limits = ChatLimits.for(client.provider, call: .note)
        var generator = NoteGenerator(client: client, model: choice.assignment.model, timeout: limits.soft,
                                      chatTimeout: limits.transport, maxTokens: limits.maxTokens,
                                      requiresExistingSession: true)
        generator.thinking = choice.thinking ?? summaryThinking()
        // Język notatki z presetu NAGRANIA (jego język i „Notes language"), także gdy model pochodzi z innego presetu.
        let language = presetFor(item.url)?.effectiveNotesLanguage
        let session = item.url
        // Słownik, reguły i uczestnicy z chwili kliknięcia, przed pierwszym `await` (sonda kontekstu); Replacement idempotentny.
        let dict = dictionary(), link = item.notes.meta.calendarEvent
        let transcript = Replacement.apply(source, rules: replacementRules())
        let token = UUID()
        startTicket(id, token) // bilet przed pierwszym `await`: Cancel nie zwalnia sesji przed końcem zadania
        let task = Task {
            do {
                // Lokalny serwer: kontekst sprawdzamy w chwili użycia (`/api/ps` zna tylko model załadowany); budżet włącza map-reduce.
                // API nie dostaje budżetu, więc nigdy nie dzieli transkryptu.
                let budget = client.provider.isLocal
                    ? ContextBudget.resolve(provider: client.provider, detected: await ContextProbe.detect(client: client, model: choice.assignment.model)) : nil
                let vocabulary = DictionaryPrompt.make(dict, link: link, maxChars: DictionaryPrompt.maxChars(budget: budget))
                _ = try await generator.generate(session: session, template: template, transcript: transcript,
                                                 context: context, notesLanguage: language, budget: budget,
                                                 vocabulary: vocabulary.isEmpty ? nil : vocabulary,
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
        // Tylko tryb migawek, w którym nic naprawdę nie trwa: wyczyszczenie rejestru nikomu nie zabiera biletu.
        if isCorrecting { _ = corrections.start(session: id, runID: "preview") } else { corrections = RunOperations() }
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
    /// Bilet trzyma sesję zajętą aż do tej chwili — także gdy przebieg był anulowany.
    private func finishGeneration(_ id: String, _ token: UUID, _ result: GenState) {
        if inflight[id]?.contains(token) == true { endTicket(id, token) }
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
        // Wznowienie też bierze własny model sesji (jeśli jest), nie tylko preset.
        let saved = store(sessionURL).readMeta().modelOverrides
        let known = knownProviderIDs()
        if let corr = CorrectionModel.resolve(frozen: snapshot.preset, override: saved?.usable(.correction, knownProviders: known)) {
            working = await runCorrection(sessionURL: sessionURL, runID: runID, assignment: corr,
                                          language: snapshot.language, transcript: transcript)
        }
        // Korekta bywa wolna: w tym czasie nowszy przebieg mógł zostać bieżącym — wtedy autotytuł z tego tekstu nie powstaje (R23).
        guard RunSelection.shouldPostProcess(session: sessionURL, runID: runID) else { return }
        // Ten sam wybór modelu co przy „Generate notes": preset nagrania → domyślny → dowolny z `summary` (`SummaryModel`).
        let info = presetsInfo()
        if let choice = SummaryModel.resolve(frozen: snapshot.preset, override: saved?.usable(.summary, knownProviders: known),
                                             defaultPresetID: info.defaultID, presets: info.presets),
           let client = clientFor(choice.assignment.providerID) {
            let corrected = CorrectedTranscript.load(session: sessionURL, runID: runID)?.transcript
            let ticket = titles.start(session: id, runID: runID)
            onChange()
            let limits = ChatLimits.for(client.provider, call: .title)
            // Tytuł z tekstu po Replacement — także bez korekty w presecie i po jej porażce (wtedy `working` jest surowy).
            _ = await AutoTitle.generate(client: client, model: choice.assignment.model,
                                         transcript: Replacement.apply(working, rules: replacementRules()),
                                         notesLanguage: snapshot.preset.effectiveNotesLanguage,
                                         store: store(sessionURL), timeout: limits.soft, chatTimeout: limits.transport,
                                         maxTokens: limits.maxTokens,
                                         stillCurrent: { RunSelection.shouldPostProcess(session: sessionURL, runID: runID) },
                                         onProblem: { [weak self] msg in Task { @MainActor in self?.report(msg) } })
            if RunSelection.shouldPostProcess(session: sessionURL, runID: runID) {
                let ok = await Overview.generate(client: client, model: choice.assignment.model,
                    transcript: Replacement.apply(corrected ?? transcript, rules: replacementRules()),
                    notesLanguage: snapshot.preset.effectiveNotesLanguage, store: store(sessionURL), runID: runID, sourceTranscript: transcript,
                    correctedTranscript: corrected,
                    timeout: limits.soft, chatTimeout: limits.transport, maxTokens: limits.maxTokens,
                    stillCurrent: { Overview.sourceIsCurrent(session: sessionURL, runID: runID, transcript: transcript, correctedTranscript: corrected) })
                if !ok { overviewFailure.insert(id) } else { overviewFailure.remove(id) }
            }
            _ = titles.finish(ticket)
            onChange()
        }
    }

    func generateOverview(_ item: SessionItem) {
        guard !isMoving(), !titles.isActive(item.id), !corrections.isActive(item.id), let runID = item.runID,
              let source = item.transcript, let transcript = item.transcript(corrected: true) else { return }
        guard let choice = summaryChoice(for: item), let client = clientFor(choice.assignment.providerID) else {
            overviewFailure.insert(item.id)
            return
        }
        let ticket = titles.start(session: item.id, runID: runID)
        let limits = ChatLimits.for(client.provider, call: .title)
        let language = (item.runSnapshot?.preset ?? presetFor(item.url))?.effectiveNotesLanguage
        let text = Replacement.apply(transcript, rules: replacementRules())
        let corrected = item.corrected?.transcript
        onChange()
        Task {
            let ok = await Overview.generate(client: client, model: choice.assignment.model, transcript: text,
                notesLanguage: language, store: store(item.url), runID: runID, sourceTranscript: source, correctedTranscript: corrected, timeout: limits.soft,
                chatTimeout: limits.transport, maxTokens: limits.maxTokens,
                stillCurrent: { Overview.sourceIsCurrent(session: item.url, runID: runID, transcript: source, correctedTranscript: corrected) })
            let outcome = titles.finish(ticket)
            if outcome.ownsMessage {
                if ok { overviewFailure.remove(item.id) } else { overviewFailure.insert(item.id) }
            }
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
            // Porażka zapisu trafia do użytkownika; tekst zostaje w buforze na następną próbę (TASK-25).
            if let error = self.writePending(id) { self.report(error) }
        }
    }

    /// Zapisuje od razu wszystko, co czeka na autozapis — przed przenoszeniem folderu nagrań.
    func flushPendingSaves() {
        for (id, task) in saveTasks { task.cancel(); if let error = writePending(id) { report(error) } }
        saveTasks = [:]
    }

    /// Zapisuje najnowsze My notes tej sesji i zwraca powód, gdy się nie udało (`nil` = zapisane albo nic nie czekało).
    /// Usuwanie spotkania woła to przed przeniesieniem katalogu do Kosza i odmawia, gdy zapis padnie.
    func flushPendingSaves(for id: String) -> String? {
        saveTasks.removeValue(forKey: id)?.cancel()
        return writePending(id)
    }

    /// Bufor znika dopiero po udanym zapisie: porażka nie gubi tekstu i zostaje na następną próbę (TASK-25).
    /// Tryb ścisły: katalog spotkania, którego już nie ma, nie powstaje od nowa.
    private func writePending(_ id: String) -> String? {
        guard let p = pendingSaves[id] else { return nil }
        guard !isMoving() else { return "Your notes weren't saved: \(Self.movingMessage)" }
        do {
            if let note = try store(p.session).writeMyNotes(p.text) { report(note) }
            pendingSaves[id] = nil
            return nil
        } catch {
            return "Couldn't save your notes: \(error.localizedDescription)"
        }
    }

    func setManualTitle(_ title: String, for item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let note = try store(item.url).updateMeta({ $0.manualTitle = t.isEmpty ? nil : t }) { report(note) }
        } catch {
            report("Couldn't save the title: \(error)")
        }
        onChange()
    }

    /// Przypisanie spotkania do folderu (TASK-26); `nil` = „No folder". Pliki nagrania zostają na miejscu.
    func setFolder(_ folderID: String?, for item: SessionItem) {
        guard !isMoving() else { report(Self.movingMessage); return }
        do {
            if let note = try store(item.url).updateMeta({ $0.folderID = folderID }) { report(note) }
        } catch {
            report("Couldn't save the folder: \(error)")
        }
        onChange()
    }
}
