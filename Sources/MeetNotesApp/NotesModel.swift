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
    private(set) var correcting: Set<String> = []
    private(set) var titling: Set<String> = []
    var templates = TemplatesFile()

    /// Podłączane przez `AppModel` (bez cyklu własności).
    var clientFor: (UUID) -> OpenAICompatibleClient? = { _ in nil }
    var presetFor: (URL) -> Preset? = { _ in nil }
    var presetsInfo: () -> (presets: [Preset], defaultID: UUID?) = { ([], nil) }
    var onChange: () -> Void = {}
    /// Komunikaty dla użytkownika (np. nieczytelny plik notatek odłożony na bok) — podłączane do `AppModel.lastError`.
    var report: (String) -> Void = { _ in }

    private var saveTasks: [String: Task<Void, Never>] = [:]

    func state(_ id: String) -> GenState { generation[id] ?? .idle }

    /// Model podsumowania dla tego nagrania: z jego presetu, a gdy go tam nie ma — z presetu domyślnego (patrz `SummaryModel`).
    func summaryChoice(for item: SessionItem) -> SummaryChoice? {
        let info = presetsInfo()
        return SummaryModel.resolve(frozen: presetFor(item.url), defaultPresetID: info.defaultID, presets: info.presets)
    }

    func isCorrecting(_ id: String) -> Bool { correcting.contains(id) }
    func isTitling(_ id: String) -> Bool { titling.contains(id) }

    // MARK: Notatka na żądanie

    func generate(item: SessionItem, useCorrected: Bool, template: Template, context: String) {
        let id = item.id
        guard state(id) != .generating else { return }
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
        let generator = NoteGenerator(client: client, model: choice.assignment.model)
        // Język notatki z presetu NAGRANIA (jego język i „Notes language"), także gdy model pochodzi z innego presetu.
        let language = presetFor(item.url)?.effectiveNotesLanguage
        let session = item.url
        Task {
            do {
                _ = try await generator.generate(session: session, template: template, transcript: transcript,
                                                 context: context, notesLanguage: language, onProblem: { [weak self] msg in Task { @MainActor in self?.report(msg) } })
                self.generation[id] = .idle
            } catch NoteGenerationError.nothingToSummarize {
                self.generation[id] = .failed("Nothing to summarize: the transcript has no usable text.")
            } catch NoteGenerationError.failed(let message) {
                self.generation[id] = .failed(message)
            } catch {
                self.generation[id] = .failed("\(error)")
            }
            self.onChange()
        }
    }

    // MARK: Po transkrypcji: korekta (gdy preset ma model) i autotytuł (gdy ma model podsumowania)

    func afterTranscription(sessionURL: URL, runID: String, snapshot: RunSnapshot, transcript: Transcript) async {
        let id = sessionURL.lastPathComponent
        var working = transcript
        if let corr = snapshot.preset.correction, !corr.model.isEmpty, let client = clientFor(corr.providerID) {
            correcting.insert(id)
            onChange()
            let result = await Corrector(client: client, assignment: corr).correct(transcript, language: snapshot.language)
            correcting.remove(id)
            if result.batches > 0 {
                try? JSONFile.save(result, to: RunDirectory(session: sessionURL, runID: runID).corrected)
                working = result.transcript
            }
            onChange()
        }
        // Ten sam wybór modelu co przy „Generate notes": preset nagrania → domyślny → dowolny z `summary` (`SummaryModel`).
        let info = presetsInfo()
        if let choice = SummaryModel.resolve(frozen: snapshot.preset, defaultPresetID: info.defaultID, presets: info.presets),
           let client = clientFor(choice.assignment.providerID) {
            titling.insert(id)
            onChange()
            _ = await AutoTitle.generate(client: client, model: choice.assignment.model, transcript: working,
                                         notesLanguage: snapshot.preset.effectiveNotesLanguage,
                                         store: NotesStore(session: sessionURL), onProblem: { [weak self] msg in Task { @MainActor in self?.report(msg) } })
            titling.remove(id)
            onChange()
        }
    }

    // MARK: My notes i tytuł

    /// Autozapis z opóźnieniem: ostatnia zmiana wygrywa, zapis 0,6 s po ostatnim znaku.
    func saveMyNotes(_ text: String, for item: SessionItem) {
        let id = item.id
        let session = item.url
        saveTasks[id]?.cancel()
        saveTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                if let note = try NotesStore(session: session).writeMyNotes(text) { self.report(note) }
            } catch {
                self.report("Couldn't save your notes: \(error)")
            }
        }
    }

    func setManualTitle(_ title: String, for item: SessionItem) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let note = try NotesStore(session: item.url).updateMeta({ $0.manualTitle = t.isEmpty ? nil : t }) { report(note) }
        } catch {
            report("Couldn't save the title: \(error)")
        }
        onChange()
    }
}
