import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

// TASK-119: ukryte wypowiedzi (np. rozmowa z tła) nie trafiają do LLM, kopii, Ask ani sugestii; zapis przez AppModel.

private let secret = "hintergrund gerede"

private func u(_ speaker: Speaker, _ start: Double, _ text: String) -> Utterance {
    Utterance(speaker: speaker, start: start, end: start + 2, text: text, words: [], approximateTiming: false, languageMismatch: nil)
}

private let raw = Transcript(utterances: [u(.me, 1, secret), u(.them, 4, "the forecast is ready")], failedChunks: [])

/// Zapisuje treść każdego żądania; odpowiedź stała.
private final class BodiesHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var bodies: [String] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { seen.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self)) }
        // Echo ostatniej wiadomości użytkownika: korektor dostaje te same ponumerowane linie (bez zmian), tytuł i Overview — cokolwiek.
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let user = ((body?["messages"] as? [[String: Any]])?.last?["content"] as? String) ?? ""
        let reply = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": user]]]])
        return (reply, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor private func appModel(root: URL) -> AppModel {
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", root.path, 1)
    defer { if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") } }
    return AppModel()
}

@Suite @MainActor struct TranscriptHiddenAppTests {
    @Test func itemDropsHiddenEverywhereExceptTheTranscriptView() {
        var item = SessionItem(url: URL(fileURLWithPath: "/nonexistent"), startedAt: Date(), transcript: raw, runID: "run")
        item.corrected = CorrectedTranscript(transcript: Transcript(utterances: [u(.me, 1, "Hintergrund."), u(.them, 4, "The forecast.")], failedChunks: []),
                                             model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
        item.edits = TranscriptEdits().settingHidden([.init(speaker: .me, start: 1)], true, now: Date(timeIntervalSince1970: 50))
        for corrected in [true, false] {
            let t = item.transcript(corrected: corrected)
            #expect(t?.utterances.count == 1)
            #expect(!(t.map { NotePromptBuilder.transcriptLines($0) } ?? []).joined().lowercased().contains("hintergrund"))
            let full = item.transcript(corrected: corrected, includeHidden: true)
            #expect(full?.utterances.count == 2 && full?.utterances[0].hidden == true)
            // Nawet pełny transkrypt (widok) nie daje ukrytego tekstu do promptu: flaga wyklucza z notatek.
            #expect(!(full.map { NotePromptBuilder.transcriptLines($0) } ?? []).joined().lowercased().contains("hintergrund"))
            #expect(item.hiddenCount(corrected: corrected) == 1)
        }
        // Ask: indeks archiwum z tego samego odczytu.
        let source = ArchiveModel.source(for: item, notes: NotesModel(), transcript: item.transcript(corrected: true))
        #expect(!String(describing: source).lowercased().contains("hintergrund"))
        // Notatka z innym stanem ukryć jest nieaktualna — także wygenerowana po ukryciu, jeśli transkrypt wzięto przed nim.
        #expect(!item.notesPredateHiding)
        item.notes.summary = NoteSummary(title: nil, markdown: "x", templateID: "t", model: "m", context: "", generatedAt: Date(timeIntervalSince1970: 99))
        #expect(item.notesPredateHiding)
        item.notes.summary?.hiddenChangedAt = Date(timeIntervalSince1970: 50.4) // summary.json: sekundy
        #expect(!item.notesPredateHiding)
        item.notes.summary?.hiddenChangedAt = Date(timeIntervalSince1970: 10)
        #expect(item.notesPredateHiding)
        #expect(!MeetingArchive.notesPredateHiding(summary: NoteSummary(title: nil, markdown: "x", templateID: "t", model: "m", context: "",
                                                                         generatedAt: Date()), edits: nil))
    }

    @Test func setHiddenSavesRestoresAndKeepsCorruptFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = appModel(root: root)
        let session = root.appendingPathComponent("session")
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        let item = SessionItem(url: session, startedAt: Date(), transcript: raw, runID: "run")
        // Istniejąca poprawka tekstu (TASK-109) zostaje.
        try TranscriptEdits(edits: [.init(index: 1, speaker: .them, start: 4, text: "edited")]).save(run: run)
        let key = TranscriptEdits.Hidden(speaker: .me, start: 1)
        #expect(model.setHidden(item, runID: "run", keys: [key], hidden: true))
        #expect(TranscriptEdits.load(run: run)?.hidden == [key])
        #expect(TranscriptEdits.load(run: run)?.edits.map(\.text) == ["edited"])
        #expect(TranscriptEdits.load(run: run)?.hiddenChangedAt != nil)
        #expect(model.setHidden(item, runID: "run", keys: [key], hidden: false))
        #expect(TranscriptEdits.load(run: run)?.hidden == nil)
        // Inny przebieg niż bieżący: bez zapisu.
        #expect(!model.setHidden(item, runID: "other", keys: [key], hidden: true))
        // Uszkodzony plik: bajty zostają, komunikat.
        try Data("{broken".utf8).write(to: run.edits)
        #expect(!model.setHidden(item, runID: "run", keys: [key], hidden: true))
        #expect(try Data(contentsOf: run.edits) == Data("{broken".utf8))
        #expect(model.lastError?.hasPrefix("Couldn't save the edit") == true)
    }

    /// Korekta, autotytuł i Overview po transkrypcji (także wznowienie w tym samym przebiegu, gdy `edits.json` już jest).
    @Test func correctionTitleAndOverviewNeverSeeHiddenText() async throws {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: session) }
        let id = "2026-10-23T09-00-00Z-cccc"
        let run = RunDirectory(session: session, runID: id)
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        try JSONFile.save(raw, to: run.transcript)
        try TranscriptEdits(hidden: [.init(speaker: .me, start: 1)]).save(run: run)
        let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
        let preset = Preset(name: "Test", language: .english, asr: RoleAssignment(providerID: provider.id, model: "asr"),
                            correction: RoleAssignment(providerID: provider.id, model: "corr"),
                            summary: RoleAssignment(providerID: provider.id, model: "sum"))
        let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
        let http = BodiesHTTP()
        let model = NotesModel()
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        await model.afterTranscription(sessionURL: session, runID: id, snapshot: snapshot, transcript: raw)
        #expect(model.correctionFailureMessage(session.lastPathComponent) == nil)
        #expect(http.bodies.count >= 2) // korekta + tytuł/Overview
        #expect(!http.bodies.joined().lowercased().contains("hintergrund"))
        // Ukryta linia zostaje surowa pod tym samym indeksem; flaga nie trafia do pliku.
        let saved = try #require(CorrectedTranscript.load(session: session, runID: id))
        #expect(saved.transcript.utterances.map(\.text) == [secret, "the forecast is ready"])
        #expect(!(try String(contentsOf: run.corrected, encoding: .utf8)).contains("hidden"))
        // Odcisk Overview liczony bez ukrytych: po przywróceniu wypowiedzi Overview przestaje być aktualne.
        let meta = NotesStore(session: session).readMeta()
        let edits = TranscriptEdits.load(run: run)
        let basis = MeetingArchive.overviewBasis(raw: raw, corrected: saved.transcript, edits: edits)
        #expect(Overview.cached(meta, runID: id, transcript: basis.raw, correctedTranscript: basis.corrected) != nil)
        #expect(Overview.cached(meta, runID: id, transcript: raw, correctedTranscript: saved.transcript) == nil)
    }

    /// Pamięć `transcript(of:)`: wariant z ukrytymi (widok) nie może wyciec do domyślnego (kopia, Ask, notatka).
    @Test func displayCacheKeepsVariantsApart() {
        let model = appModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())"))
        var item = SessionItem(url: URL(fileURLWithPath: "/nonexistent"), startedAt: Date(), transcript: raw, runID: "run")
        item.edits = TranscriptEdits(hidden: [.init(speaker: .me, start: 1)])
        #expect(model.transcript(of: item, corrected: false, includeHidden: true)?.utterances.count == 2)
        #expect(model.transcript(of: item, corrected: false)?.utterances.count == 1)
        #expect(model.transcript(of: item, corrected: false, includeHidden: true)?.utterances.count == 2)
    }

    /// Bez modelu korekty autotytuł i Overview biorą surowy transkrypt — też bez ukrytego tekstu.
    @Test func titleAndOverviewWithoutCorrectionNeverSeeHiddenText() async throws {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: session) }
        let id = "2026-10-23T09-00-00Z-dddd"
        let run = RunDirectory(session: session, runID: id)
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        try JSONFile.save(raw, to: run.transcript)
        try TranscriptEdits(hidden: [.init(speaker: .me, start: 1)]).save(run: run)
        let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
        let preset = Preset(name: "Test", language: .english, asr: RoleAssignment(providerID: provider.id, model: "asr"),
                            summary: RoleAssignment(providerID: provider.id, model: "sum"))
        let http = BodiesHTTP()
        let model = NotesModel()
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        await model.afterTranscription(sessionURL: session, runID: id, snapshot: try RunSnapshot(preset: preset, provider: provider, probe: nil), transcript: raw)
        #expect(http.bodies.count == 2) // tytuł + Overview
        #expect(!http.bodies.joined().lowercased().contains("hintergrund"))
    }

    @Test func aliasSuggestionsSkipHiddenPairs() {
        let term = DictionaryTerm("Nimbu")
        let dictionary = UserDictionary(terms: [term])
        let r = Transcript(utterances: [u(.me, 1, "we use nimboo here"), u(.me, 3, "and nimboo there")], failedChunks: [])
        let c = CorrectedTranscript(transcript: Transcript(utterances: [u(.me, 1, "we use Nimbu here"), u(.me, 3, "and Nimbu there")], failedChunks: []),
                                    model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
        func find(_ edits: TranscriptEdits) -> [AliasSuggestion] {
            var fixed = c
            fixed.transcript = edits.markingHidden(fixed.transcript)
            return AliasSuggestions.find(in: [.init(id: "s", raw: edits.markingHidden(r), corrected: fixed)], dictionary: dictionary,
                                         dismissed: [], fillerWords: [], isCommonWord: { _ in false })
        }
        let visible = find(TranscriptEdits())
        let hidden = find(TranscriptEdits(hidden: [.init(speaker: .me, start: 1), .init(speaker: .me, start: 3)]))
        #expect(hidden.isEmpty)
        // Kontrola: bez ukryć ta sama para daje sugestię (inaczej test niczego nie sprawdza).
        #expect(!visible.isEmpty)
    }

    @Test func clickSelectsWithCommandAndRangeWithShift() {
        let state = MeetingViewState()
        let visible = [0, 2, 3, 5, 7]
        state.click(2, command: true, shift: false, runID: "r", corrected: true, visible: visible)
        state.click(5, command: false, shift: true, runID: "r", corrected: true, visible: visible)
        #expect(state.selected(runID: "r", corrected: true) == [2, 3, 5])
        state.click(3, command: true, shift: false, runID: "r", corrected: true, visible: visible)
        #expect(state.selected(runID: "r", corrected: true) == [2, 5])
        // Inna wersja albo przebieg: zaznaczenie nie obowiązuje; klik w nowej zaczyna od zera.
        #expect(state.selected(runID: "r", corrected: false).isEmpty)
        #expect(state.selected(runID: "x", corrected: true).isEmpty)
        state.click(0, command: true, shift: false, runID: "r", corrected: false, visible: visible)
        #expect(state.selected(runID: "r", corrected: false) == [0])
        state.clearSelection()
        #expect(state.selected(runID: "r", corrected: false).isEmpty)
    }
}
